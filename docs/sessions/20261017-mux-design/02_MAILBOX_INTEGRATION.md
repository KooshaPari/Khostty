# C2 — Mailbox Integration Analysis (Phase 1 mux shell)

**Phase:** C (Phase 1 mux shell design)
**Status:** DONE
**Date:** 2026-10-17
**Scope:** Map the existing mailbox wiring so the mux shell can route
agent requests to the right surface/termio message queue without
introducing new locks.

---

## TL;DR

There are **two mailboxes per surface**, not one:

1. **`App.Mailbox`** (runtime-level) — routes `apprt.surface.Message`
   to the **app thread** for `set_title`, `child_exited`,
   `desktop_notification`, and other "lifecycle" messages.
2. **`termio.Mailbox`** (IO-thread-level) — routes `termio.Message` to
   the **IO thread** for `write_small`/`write_stable`/`write_alloc`,
   `resize`, `focused`, `inspector`, and other per-keystroke messages.

The mux shell's `pane.Manager` is the lock-owner for both, and the
`AppHost` vtable is the dispatcher. No new locks are needed for the
mux shell; it composes as a client of the existing locks.

---

## Surface mailboxes — `src/apprt/surface.zig:187-207`

```zig
pub const Mailbox = struct {
    surface: *Surface,
    app: App.Mailbox,

    pub fn push(self: Mailbox, msg: Message, timeout: ...) ... {
        return self.app.push(.{
            .surface_message = .{
                .surface = self.surface,
                .message = msg,
            },
        }, timeout);
    }
};
```

`apprt.surface.Mailbox` is a thin wrapper that rewraps the surface
message as `.{ .surface_message = ... }` and pushes to the app's mailbox.
This is the route used by the GTK runtime to dispatch `set_title`,
`child_exited`, etc. from the app thread to the surface.

`App.Mailbox` is a per-app FIFO queue, drained by the app's main loop.
When a `surface_message` arrives, the app loop looks up the surface by
pointer and calls the surface's `Message` handler.

---

## CoreSurface IO mailbox — `src/Surface.zig:879-900`

```zig
fn queueIo(
    self: *CoreSurface,
    msg: termio.Message,
    mutex: termio.Queue.Mutex,
) void {
    self.io.queueMessage(msg, mutex);
}
```

`queueIo` routes via `self.io` (a `termio.Queue`) to the **termio
thread**, not the app thread. The two queues are deliberately
separate so that a flood of PTY output (termio) cannot starve
lifecycle events (app) and vice-versa.

Caller examples:

- `Surface.zig:935,965` — `inspector = true/false`
- `Surface.zig:1037,1230,1261,1860` — resize, write, etc.

---

## Race discovered in `app_host.zig:290-298` (B2)

The current `publishWriteAlloc` path calls
`stream.nextSlice(data)` **directly from the IPC thread**, which races
with the termio thread's `stream` reader. The proper fix is:

```zig
core.queueIo(.{ .write_alloc = data }, .unlocked);
```

This delegates to the termio thread via the existing
`CoreSurface.queueIo` path, which already has the right lock.
Documented in `01_RESEARCH.md` (FWD-PATH B2). The mux shell does not
need to fix this race — the fix lives in `app_host.zig`. The mux
shell benefits because its own writes go through `Manager.write`,
which already uses `queueIo`.

---

## Mailbox ownership and mutex handoff

When `App.Mailbox.push` is called with a full queue, the queue hands
the message's mutex to the calling thread (`.unlocked`) or blocks
(`.locked`). This is the convention that lets the mux shell's
`Manager.write` enqueue from the IPC thread without holding any
mutex across the syscall.

| Mutex state | When to use                                                               | Effect                                     |
| ----------- | ------------------------------------------------------------------------- | ------------------------------------------ |
| `.unlocked` | Caller does not hold the termio mutex (typical for IPC thread)            | Queue hands the mutex to the termio thread |
| `.locked`   | Caller already holds the termio mutex (rare; only for in-thread re-entry) | Queue assumes the mutex is already held    |

The mux shell's IPC handler thread never holds a termio mutex
(because it is not the termio thread), so it always uses `.unlocked`.

---

## Message ownership transfer

`Message` is passed by value; ownership transfers from the IPC thread
to the termio thread on enqueue. The IPC thread must NOT retain a
reference to `data` after `queueIo` returns — the termio thread may
read or free the slice at any point. The mux shell's `Manager.write`
already respects this; the agent protocol's `pane.write` method
copies the data into a fresh `gpa.dupe` slice before calling
`Manager.write`, so the agent socket buffer is independent.

---

## What is _not_ in C2

- Concrete timeouts for `App.Mailbox.push`. The mux shell's `Config`
  will expose these in a future PR (C6); for the skeleton, the
  default `App.Mailbox.Queue.Timeout` is used.
- The reverse direction (termio → app). The mux shell does not need
  to send messages to the app thread; it only consumes events from
  the termio thread via the events broker.
- The `pane.Manager` lock — the broker serializes publishes, and
  `Manager` takes the broker only when constructing the setup
  (`src/apprt/ipc/mux_shell.zig:setup`). See C4 §4 for the lock
  ordering rule.

---

## Out-of-scope deferred items

- Per-surface thread-pool draining of the termio queue. Currently
  each surface has a single termio thread; multi-threaded termio is
  a Phase 3+ concern.
- Mailbox back-pressure metrics. Phase 1 surfaces mailbox-full as
  a `pane.write` error; metrics come later.
