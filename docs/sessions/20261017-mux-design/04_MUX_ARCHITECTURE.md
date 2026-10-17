# C4 — Mux Shell Architecture (Phase 1 mux shell)

**Phase:** C (Phase 1 mux shell design)
**Status:** DONE
**Date:** 2026-10-17
**Scope:** End-to-end architecture for the headless `khostty-mux` binary:
component diagram, process model, lifecycle, lock-ordering rule, failure
modes, and the C5 skeleton's fit.

---

## 1. Goals (Phase 1)

- The user (or an AI agent on the user's behalf) can run
  `khostty-mux` as a long-running background process that hosts one or
  more terminal surfaces and exposes them over a Unix domain socket.
- The agent can `pane.list`, `pane.create`, `pane.write`, `pane.read`,
  `pane.resize`, `pane.close` and receive `title_change`, `child_exit`,
  `resize`, `bell` events.
- No windowed GTK binary is required to be running; the mux shell is
  self-contained.
- Build is incremental: Phase 1 ships a working binary that hosts
  surfaces; Phase 2+ adds the Q1(b) shared-app path (deferred, see
  `01_EMBEDDED_APP_COMPATIBILITY.md`).

## 2. Non-goals (Phase 1)

- Sharing surfaces between the mux shell and the user's windowed
  `khostty` binary. (Q1(b), Phase 2.)
- Multi-host distributed muxing. (Q1(c), Phase 3.)
- macOS / Windows code-signing with `LSUIElement`. (Distribution concern.)
- WASM build. (Wasm cannot host a Unix socket process.)
- Telemetry, metrics, audit log. (Phase 2+.)

## 3. Component diagram

```
┌──────────────── khostty-mux process ─────────────────┐
│                                                      │
│  ┌──────────┐     ┌──────────────┐   ┌────────────┐  │
│  │  GTK App │────▶│   AppHost    │◀─▶│  Broker    │  │
│  │ (headless│     │   (vtable)   │   │ (events)   │  │
│  │  config) │     └──────┬───────┘   └────┬───────┘  │
│  └────┬─────┘            │                │          │
│       │                  ▼                ▼          │
│       │           ┌────────────┐    ┌──────────┐      │
│       │           │ pane.      │    │ Subscribers│    │
│       │           │ Manager    │    │ (agent    │      │
│       │           └─────┬──────┘    │  socket)  │      │
│       │                 │           └─────▲──────┘      │
│       │                 ▼                 │            │
│       │          ┌─────────────┐           │            │
│       └─────────▶│ CoreSurface │           │            │
│                  │ per pane    │           │            │
│                  └─────┬───────┘           │            │
│                        │ termio.Queue       │            │
│                        ▼                    │            │
│                  ┌─────────────┐            │            │
│                  │ termio/IO   │            │            │
│                  │ thread      │            │            │
│                  └─────────────┘            │            │
│                                              │            │
│  ┌──────────────── socket accept ────────────┘            │
│  │   posix.listen(unix socket) -> Connection pool        │
│  │   each connection: read frame -> dispatch handler.zig  │
│  │   handler calls pane.Manager                          │
│  └────────────────────────────────────────────────────────┘
└──────────────────────────────────────────────────────────┘
                                │
                                ▼  Unix socket
                          agent process
```

**Key components:**

| Component                    | Source                           | Role                                                                                     |
| ---------------------------- | -------------------------------- | ---------------------------------------------------------------------------------------- |
| `apprt_gtk.App`              | `src/apprt/gtk/App.zig`          | The runtime, in `headless` config. Owns the GTK main loop.                               |
| `apprt.ipc.app_host.AppHost` | `src/apprt/ipc/app_host.zig:106` | Vtable of `*CoreApp` operations (`new_surface`, `close`, `set_title`, etc.).             |
| `apprt.ipc.events.Broker`    | `src/apprt/ipc/events.zig`       | Pub/sub of typed events to subscribed agent connections.                                 |
| `apprt.ipc.pane.Manager`     | `src/apprt/ipc/pane.zig`         | Owns the pane lifecycle (create, close, find by id). Single source of truth for pane_id. |
| `apprt.ipc.server.Server`    | `src/apprt/ipc/server.zig`       | Listens on the Unix socket, accepts connections, spawns handler threads.                 |
| `apprt.ipc.handler`          | `src/apprt/ipc/handler.zig`      | Per-connection read-loop. Calls into `pane.Manager` for `pane.*` methods.                |
| `CoreSurface`                | `src/Surface.zig`                | The per-pane runtime surface (termio thread, renderer, etc.). One per pane.              |
| `termio.Queue`               | `src/termio/queue.zig`           | The per-surface IO mailbox. IPC thread → termio thread.                                  |
| `App.Mailbox`                | `src/apprt/App.zig`              | The per-app lifecycle mailbox. IPC thread → app thread.                                  |
| `apprt.ipc.mux_shell`        | `src/apprt/ipc/mux_shell.zig`    | C5 skeleton: the `setup()` helper that wires Manager + Broker + AppHost.                 |

### 3.1 Two socket, one process — clarification

Earlier drafts mentioned a "two-socket warning." That was overcautious.
In Q1(a) there is **one socket**: the `apprt.ipc` Unix socket bound by
the mux shell. There is no `apprt.apprt` socket in Q1(a) because the
mux shell is the only runtime in this process. The two-socket concern
applies only to Q1(c), which is Phase 3 and out of scope.

### 3.2 The `pane.Manager` is the lock-owner

Every operation that needs to look up a pane by id goes through
`pane.Manager`:

- `pane.list` — Manager returns a snapshot
- `pane.create` — Manager allocates a new pane id, calls AppHost.new_surface
- `pane.write` — Manager looks up the surface, calls `core.queueIo`
- `pane.read` — Manager looks up the surface, pushes a reader into the
  termio queue
- `pane.close` — Manager removes from registry, calls AppHost.close

The Manager holds **one** lock for the duration of these operations.
Multiple IPC connections calling into the Manager are serialized. This
is fine: the critical sections are O(pane_count) and run in
microseconds. The lock is not held across the termio queue
hand-off (see `02_MAILBOX_INTEGRATION.md`).

### 3.3 Lifecycle — happy path

```
[1] User runs:    khostty-mux [--socket /tmp/khostty.sock]
[2] main():
        env = auth.Env.process();
        cfg = mux_shell.Config.fromArgs(args) orelse default;
        try mux_shell.setup(env, cfg, &s);
        try s.runMuxShell(); // -> posix.listen, accept loop
[3] setup():
        s.broker = events.Broker.init(gpa);
        s.manager = pane.Manager.init(gpa, &s.broker);
        s.app_host = try app_host.AppHost.init(core_app, &s.broker);
        gtk_app.setEventBroker(&s.broker); // wires GTK -> broker
[4] runMuxShell():
        path = resolveSocketPath(env, cfg.socket);
        listener = try posix.listen(path);
        while (true) {
            conn = try listener.accept();
            server.spawnHandler(conn, &s.manager);
        }
[5] Agent connects:
        sends pane.list
        handler -> manager.list -> returns []
        agent sends pane.create
        handler -> manager.create -> AppHost.new_surface -> CoreSurface
                -> manager.registry.insert(surface_id)
                -> broker.publish(pane_created)
        agent subscribes to events
        broker -> agent.send(pane_created, ...)
[6] Shell exits (Ctrl-D or exit):
        core.termio notifies
        termio thread -> App.Mailbox.push(.surface_message{.child_exited=...})
        app loop -> Surface.childExited
        GTK class.Surface.childExited -> broker.publish(child_exit)
        handler -> cleanup; close pane on agent request
```

## 4. Lock-ordering rule

**The Manager lock is acquired before the Broker lock; never the other
way around.** The Broker is the publisher of events; the Manager is the
lock-owner that subscribes/unsubscribes surfaces and updates the
pane-id registry.

- `Manager.create` (acquires Manager) → `broker.subscribe(surface_id)`
  (would acquire Broker) — **CORRECT direction**.
- `broker.publish(event)` (acquires Broker only) — no Manager call.
  **Safe.**
- `Manager.delete` (acquires Manager) → `broker.unsubscribe(surface_id)`
  (would acquire Broker) — **CORRECT direction**.

The reverse (Broker → Manager) would deadlock if a `broker.publish`
ever needed to read Manager state. Today no such path exists, but the
rule is the rule, and the C5 skeleton enforces it by construction:
`setup()` constructs Manager first, then passes its address to Broker.

### 4.1 Where the rule is violated in the skeleton (intentional)

The skeleton's `setup()` does NOT hold any lock — it only constructs
pointers. The Manager is _created_ before the Broker, so the
construction order matches the lock-order rule. No locks are taken
during `setup()`.

The skeleton's `runMuxShell()` does NOT touch Manager or Broker locks
either — it just calls `posix.listen` and accepts. The handler thread
(per-connection) will take the Manager lock for the duration of each
`pane.*` call. This is documented in `02_MAILBOX_INTEGRATION.md`.

## 5. Failure modes

| Failure                                                         | Detection                                                  | Recovery                                                                                                                                      |
| --------------------------------------------------------------- | ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Stale socket file (process crashed without cleanup)             | `posix.listen` returns `EADDRINUSE`                        | Connect to the existing socket and check the PID; if it answers, leave it; if not, `unlink` and retry                                         |
| Agent connection drops mid-`pane.read`                          | `read` returns 0 or error                                  | Cancel the termio reader; pane remains alive                                                                                                  |
| Termio thread crashes                                           | `Mailbox.push` blocks forever; agent `pane.read` times out | Phase 1 does NOT auto-restart; the surface is marked dead and `pane.list` reports it. Agent is expected to `pane.close` and create a new one. |
| AppHost init fails (no display in headless config)              | `AppHost.init` returns error                               | `runMuxShell` exits with non-zero; operator must re-run with `DISPLAY` set (X11) or `--headless` (already the default)                        |
| `App.Mailbox.push` blocks on full queue                         | `Mailbox.push` honors the timeout                          | Return `error.MailboxFull`; agent retries with backoff                                                                                        |
| Build of `khostty-mux` is OOM-killed (this fork's host is 16GB) | `zig build` returns signal 9                               | Use the `compile_remote` tool (cloud compute, 64GB+) to build; documented in `05_KNOWN_ISSUES.md`                                             |

## 6. Security

Phase 1 is single-user: the socket lives in `$XDG_RUNTIME_DIR/khostty-mux.sock`
(Linux) or `/tmp/khostty-mux.sock` (macOS) with mode `0600`. The agent
process is expected to be the same user. **No authentication layer in
Phase 1.** Phase 2 adds the `apprt.ipc.auth` (already stubbed at
`src/apprt/ipc/auth.zig`) which the AgentKit team is designing; the
mux shell will plug into it.

The `Config.socket_mode: u32 = 0o600` field exists in the skeleton for
this purpose; the live `runMuxShell` will call `posix.fchmod` on the
socket fd before `accept`.

## 7. Out-of-scope deferred items

- **Phase 2**: shared-app with the windowed binary (Q1(b)). The agent
  connects to the running windowed binary's mux shell. Requires adding
  `apprt.ipc` server mode to the windowed binary.
- **Phase 3**: multi-process muxing (Q1(c)). Windowed binary is a
  client of a separate `khostty-mux` worker. Adds a second socket and
  process supervision.
- **Phase 3+**: TLS over the Unix socket (using `kTLS` for in-kernel
  encryption), mTLS for agent auth, full audit log.
- **Distribution**: macOS `LSUIElement` Info.plist; Linux systemd user
  service unit; Windows service registration.

## 8. The C5 skeleton's role

`src/apprt/ipc/mux_shell.zig` (committed at `f362c7107` after mushroom's
build-fix pass over my original `67c7301e9`) provides:

- `Config` struct with the user's socket path, max-connections,
  socket-mode fields.
- `Setup` struct that holds `Manager`, `Broker`, `AppHost` pointers.
- `setup(env, cfg, *Setup)` helper that wires them with the
  lock-ordering rule.
- `resolveSocketPath(env, maybe_override)` with macOS/Linux/Windows
  branches.
- `runMuxShell(*Setup, *const Config)` stub with `TODO(phase-1)` for
  the actual `posix.listen` and accept loop. The live binary's
  `main.zig` (out of scope for C5) will call this.

The skeleton is type-checked by `zig build test-agent-ipc` via the
`@import` in `src/main_agent_ipc.zig` (the test root). The skeleton's
own tests exercise `Config` defaults and `resolveSocketPath`.

The skeleton's `TODO(phase-1)` is intentional: the actual server bind
requires a real `*App` (GTK app instance) which the test root cannot
construct. Phase 1 ships the live binary's `main.zig` and unblocks the
`TODO`.
