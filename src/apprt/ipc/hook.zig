//! FORK: runtime-agnostic event publication for the agent IPC surface.
//!
//! KooshaPari/Khostty#48 (Phase B4/B5).
//!
//! ## Why this exists
//!
//! `AppHost.publish*` is the only way the runtime's own events (title change,
//! resize, bell, child exit) reach an agent, and it lives in a GTK-only type.
//! The core `Surface` is compiled for macOS, GTK and wasm, so it cannot name
//! that type without either per-apprt `comptime` branching or an import cycle
//! (`App.zig` -> `app_host.zig` -> `App.zig`).
//!
//! Instead `CoreApp` carries an optional `Hook`. Core `Surface` calls it
//! unconditionally; on every build that has no IPC host the value is null and
//! each call is a no-op. This module deliberately imports nothing so that it
//! stays a leaf in the dependency graph.
//!
//! ## Contract
//!
//! Callbacks are invoked on whichever thread produced the event - normally the
//! app's IO thread - and must not block. The GTK implementation forwards to
//! `events.Broker.publish`, which is already safe for that.

const Hook = @This();

/// Opaque owner, normally the `AppHost`. Passed back to every callback.
ctx: *anyopaque,

/// A surface's title changed.
/// The callee re-reads the title from the surface, so nothing is copied here.
title: *const fn (ctx: *anyopaque, pane_id: u64) void,

/// A surface's grid dimensions changed, in cells.
resize: *const fn (ctx: *anyopaque, pane_id: u64, cols: u16, rows: u16) void,

/// A surface rang the bell.
bell: *const fn (ctx: *anyopaque, pane_id: u64) void,

/// A surface's child process ended. `exit_code` and `signal` are optional
/// because a runtime may not retain them.
child_exit: *const fn (
    ctx: *anyopaque,
    pane_id: u64,
    exit_code: ?i32,
    signal: ?u8,
) void,
