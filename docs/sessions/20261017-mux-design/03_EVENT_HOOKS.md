# C3 — Event Hook Insertion Points (Phase 1 mux shell)

**Phase:** C (Phase 1 mux shell design)
**Status:** DONE
**Date:** 2026-10-17
**Scope:** Map the four `publish*` hooks on `AppHost` to the GTK
runtime insertion points that fire them.

---

## TL;DR

All four hooks already exist on `AppHost` (`src/apprt/ipc/app_host.zig:130-160`):

* `publishTitleChange(self, core)`
* `publishChildExit(self, core)`
* `publishResize(self, core, cols, rows)`
* `publishBell(self, core)`

When the broker is null, all four are no-ops. The wiring gap is that
the GTK `class.Surface` cannot reach an `AppHost` today. The fix is
to add a `broker` field to `Application.Private` (not to each
`Surface`), with a `setEventBroker`/`broker` accessor pair.

---

## Hook signatures (already exist)

```zig
// src/apprt/ipc/app_host.zig:130
pub fn publishTitleChange(self: *AppHost, core: *CoreSurface) void {
    if (self.broker) |b| b.publish(io, .{
        .title_change = .{ .surface_id = core.surface_id },
    });
}
// Lines 137, 151, 157: same shape for child_exit, resize, bell.
```

All four follow the pattern: if `self.broker` is null, return. If
non-null, publish a typed event. The mux shell's `setup()` calls
`app_host.setEventBroker(&broker)` (`mux_shell.zig:setup`), which
populates `self.broker` and makes the hooks live.

---

## Wiring gap — `Surface` cannot reach `AppHost`

GTK `class.Surface` (`src/apprt/gtk/class/Surface.zig`, 4439 lines) is
a `GObject` subclass. It calls `setTitle`, `childExited`,
`renderSurfaceResize`, and `ringBell`. None of these have access to
the `AppHost` instance today, because `AppHost` is created in
`mux_shell.zig:setup` and there is no path from `Surface` to
`AppHost`.

### Fix — broker lives on `Application`, not `Surface`

Add to `src/apprt/gtk/class/application.zig:170-184` (the `Private`
struct):

```zig
broker: ?*events.Broker = null,
```

Accessor pair:

```zig
pub fn setEventBroker(self: *Application, broker: ?*events.Broker) void {
    self.private.broker = broker;
}
pub fn broker(self: *Application) ?*events.Broker {
    return self.private.broker;
}
```

The mux shell's `main` calls
`gtk_app.setEventBroker(&s.broker)` after the AppHost is constructed.

Why `Application`, not `Surface`?
* The broker is a singleton per process; it has one publisher (the
  AppHost) and many subscribers (the agent connections).
* `Application` is the GTK-level singleton; `Surface` is per-window.
* The `Application.default()` accessor already exists and is what
  the mux shell's main will use to wire the broker.

---

## Four insertion points (1-3 lines each)

### 1. `setTitle` — `src/apprt/gtk/class/Surface.zig:2109`

```zig
pub fn setTitle(self: *Surface, title: []const u8) void {
    const app = Application.default();
    defer app.unref();
    if (app.broker()) |b| b.publish(self.app.io, .{
        .title_change = .{ .surface_id = self.rtCore().surface_id },
    });
    // ... existing title update logic ...
}
```

### 2. `childExited` — `src/apprt/gtk/class/Surface.zig:1521`

```zig
pub fn childExited(self: *Surface, ...) void {
    if (Application.default().broker()) |b| b.publish(self.app.io, .{
        .child_exit = .{ .surface_id = self.rtCore().surface_id, .status = status },
    });
    // ... existing exit handling ...
}
```

### 3. `renderSurfaceResize` — `src/apprt/gtk/class/Surface.zig:3398`

```zig
pub fn renderSurfaceResize(self: *Surface, cols: u16, rows: u16) void {
    if (Application.default().broker()) |b| b.publish(self.app.io, .{
        .resize = .{ .surface_id = self.rtCore().surface_id, .cols = cols, .rows = rows },
    });
    // ... existing resize logic ...
}
```

### 4. `ringBell` — `src/apprt/gtk/class/Surface.zig:2564`

```zig
pub fn ringBell(self: *Surface) void {
    if (Application.default().broker()) |b| b.publish(self.app.io, .{
        .bell = .{ .surface_id = self.rtCore().surface_id },
    });
    // ... existing bell logic ...
}
```

---

## Lock-ordering note

All four hooks acquire the **Broker lock only** (no Manager lock, no
termio lock). This is the safe direction: the broker is the lock-owner
that publishes events, and acquiring its lock alone never deadlocks
against the `Manager -> Broker` ordering rule (C4 §4).

The hooks do NOT hold any GTK lock when they call `b.publish` —
`Application.default()` returns a `*Application` and `broker()`
is a pure field read. This is what makes the hooks safe to call
from any GTK callback context.

---

## What is *not* in C3

* Wiring the broker from `mux_shell.zig:setup` into the GTK
  `Application` instance. This happens in the live binary's `main`,
  not in the test root. The skeleton is content with the AppHost
  holding the broker; the GTK hooks will be live once a real
  `khostty-mux` binary calls `gtk_app.setEventBroker`.
* The reverse direction — an agent command that *sets* a title via
  the broker. The mux shell handles that via the existing
  `apprt.surface.Message.set_title` path; no new hook is needed.
* Per-event-type filtering. The `EventMask` already supports
  per-subscriber filtering (`src/apprt/ipc/events.zig:285`); the
  mux shell does not need to add a new filter dimension.

---

## Out-of-scope deferred items

* A `pane.list` change event. The events broker publishes
  `pane_created` and `pane_closed` from the Manager; a
  `pane_list_changed` event would require the Manager to diff
  before/after, which is a Phase 2+ concern.
* An `app.focused` event. GTK has the underlying signal but the
  mux shell's pane model is per-surface, not per-app; this is a
  Phase 3+ concern.
