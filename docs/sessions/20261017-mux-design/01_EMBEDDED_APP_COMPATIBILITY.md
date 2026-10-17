# C1 — Embedded App Compatibility Survey (Phase 1 mux shell)

**Phase:** C (Phase 1 mux shell design)
**Status:** DONE
**Date:** 2026-10-17
**Scope:** Determine which `apprt.App` variant the headless `khostty-mux` binary
will host in-process. Required before C4 (architecture) can finalize the
process model.

---

## TL;DR

Three deployment shapes were considered. **Shape Q1(a) is the answer for the
headless mux shell binary**: a fresh `App` (GTK runtime, windowed) is
embedded in the same process as the IPC server. The windowed App is
embedded in headless mode (no actual window is shown; surfaces are created
on demand via the existing `new_surface` action).

| Shape | When it wins | Mux shell fit? |
|---|---|---|
| **Q1(a) — headless App in-process** | Headless binary, no per-window state, single address space, simplest dependency chain | **YES — adopted for Phase 1** |
| Q1(b) — shared App with windowed | Windowed binary (the user's main `khostty` process) where the mux shell is a library | No, the windowed binary already has its own App; embedding another would conflict |
| Q1(c) — external worker process | Multi-host, security boundary, process isolation | No, adds IPC and lifecycle complexity for no Phase 1 win |

---

## Q1(a) detail — headless App in headless binary

The mux shell binary runs `apprt_gtk` (the only currently-windowed runtime)
with the `headless` app config. It creates an `App`, calls `app.run()`,
and the GTK main loop drives both the surface mailbox and the IPC accept
loop. No second process, no IPC between App instances, no race between
windowed and headless runtimes.

**Pros:**

* No new process model. The same `App.zig` and `Surface.zig` paths that
  the windowed binary uses are exercised in the test build.
* The agent IPC layer (`apprt.ipc`) is already designed against a
  `*CoreApp` and an `AppHost` vtable (`src/apprt/ipc/app_host.zig:106`).
  This is the exact shape Q1(a) needs.
* The C5 skeleton (see `04_MUX_ARCHITECTURE.md` §3) wires
  `pane.Manager` + `events.Broker` + `app_host.AppHost` directly. No
  bridge required.

**Cons:**

* macOS code-signing will mark the binary as a "background-only" process
  unless we explicitly use `LSUIElement` Info.plist. This is a
  distributable concern, not a Phase 1 concern.
* The headless App still loads the GTK theme/CSS pipeline. Memory
  cost is non-trivial (~30-50 MiB). Acceptable for Phase 1.

**Required changes:**

* `build.zig`: a new `install` step for the `khostty-mux` binary (out of
  scope for C1 — covered by C5/C6).
* `src/apprt/gtk/App.zig`: the existing `headless` app config path is
  already there. No change needed.

---

## Q1(b) — shared App with the windowed binary

The user's windowed `khostty` process embeds the mux shell as a library.
The library hosts the same `pane.Manager` and `events.Broker` and exposes
the same `apprt.ipc` socket. The windowed binary adds surfaces via the
existing `new_split` action, which the AppHost already knows how to handle
(`src/apprt/ipc/app_host.zig:235-310`).

**Pros:**

* No second process from the user's perspective. The agent connects to
  the running windowed binary's socket.
* Single set of surfaces; no "which App is the source of truth" question.

**Cons:**

* The windowed binary already uses its `App` for the windowed UI. Adding
  the mux shell to the same process makes the windowed binary a server
  for the entire time it is open. This is a long-running socket lifetime
  tied to the lifetime of a windowed app, which is not what the agent
  protocol expects (the agent expects the server to outlive any windowed
  instance).
* Mixing headless and windowed behavior in one `App` is a known fragile
  pattern in this codebase (see `app_host.zig`'s `unavailableReason()`
  logic, which carefully partitions behaviors by runtime).

**Verdict:** Defer to Phase 2 if at all. The user's windowed binary should
spawn the mux shell as a child process, not host it in-process.

---

## Q1(c) — external worker process

The mux shell binary hosts a stripped-down App that *only* creates
surfaces and forwards output to the windowed binary via a separate IPC
channel (libghostty's internal `apprt.apprt` socket).

**Pros:**

* Strong isolation. The windowed binary can crash without taking the
  agent's surface with it.
* Each binary can be optimized for its purpose (windowed vs. headless).

**Cons:**

* Two new IPC channels: `apprt.ipc` (agent) and `apprt.apprt` (windowed
  binary ↔ mux shell). This is the "two-socket warning" documented in
  `04_MUX_ARCHITECTURE.md` §2.2.
* The windowed binary must support being a "client" of the mux shell's
  AppHost, which is a new code path.
* Lifecycle: who restarts the mux shell when it dies? The windowed
  binary, which is the more crash-prone of the two.

**Verdict:** Defer to Phase 3. Phase 1 should ship the simpler shape
(Q1(a)) and gather operational data before adding the second process.

---

## What is *not* in scope for C1

* The concrete `App.init` call inside `khostty-mux` (covered by C5
  skeleton; the live binary's main is TODO(phase-1)).
* The CLI parsing for `--headless` vs `--windowed` (C6).
* The interaction with the existing `ghostty -e` (exec) command, which
  spawns a new process for a single command. The mux shell is a
  long-running service; the exec command is a one-shot. They share
  no infrastructure.

---

## Out-of-scope deferred items

* macOS code-signing with `LSUIElement`. The operator's machine has
  `khostty` already running and code-signing is not blocking.
* Windows. The mux shell is POSIX-only in Phase 1.
* WASM. The mux shell requires real socket I/O and a process model that
  the wasm artifact cannot provide.
