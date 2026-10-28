//! FORK: run a closure on the app thread, from any thread.
//!
//! KooshaPari/Khostty#76.
//!
//! ## Why a thunk rather than typed slots
//!
//! Every method of the windowed IPC vtable runs on a per-connection thread, but
//! several read state only the app thread may touch: the surface list, GTK
//! widget properties, the IO thread's `terminal`. `pane.create` was the one
//! that aborted deterministically (#71); the rest had simply not lost the race.
//!
//! The first attempt at a boundary used a typed `Slot` carrying a mirrored copy
//! of `PaneInfo`. That forced every payload to be duplicated in this module,
//! including enums — and this fork has already been bitten once by mirroring an
//! enum whose variant order differed (`ResizeSplit.Direction` vs
//! `protocol.Direction`). A thunk carries no payload at all: the caller keeps
//! its own data on its stack and supplies a function that fills it.
//!
//! ## Contract
//!
//! - The caller owns `Task` and everything its closure touches, on its own
//!   stack, and stays blocked until `done`. That makes the caller's arena safe
//!   for the app thread to allocate into: exactly one thread is inside it at a
//!   time, by construction.
//! - The app thread runs the closure and then sets `done` under `mutex`. It
//!   never blocks on a caller beyond one uncontended lock.
//! - The closure must be short. It runs on the thread that drives the terminal;
//!   anything slow there is a UI stall, not just a slow request.
//! - This module imports std and nothing else, so core and IPC can both use it
//!   without an import cycle.

const std = @import("std");

/// A closure to run on the app thread, owned by the calling stack.
pub const Task = struct {
    ctx: *anyopaque,
    run: *const fn (ctx: *anyopaque) void,

    mutex: std.Io.Mutex = .init,
    /// Written by the app thread last, read by the caller first.
    done: bool = false,

    /// Bind a context and the function that consumes it.
    ///
    /// The function receives the context as `*anyopaque` and does its own
    /// cast, which keeps `Task` free of any knowledge of the payload type and
    /// lets callers declare the cast next to the fields they touch.
    pub fn init(ctx: anytype, func: *const fn (*anyopaque) void) Task {
        return .{ .ctx = @ptrCast(ctx), .run = func };
    }
};
