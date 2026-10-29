//! FORK: run a closure on the app thread, from any thread.
//!
//! KooshaPari/Khostty#76, #79.
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
//! ## Lifetime — why this is heap allocated
//!
//! The caller posts a task and waits for it. If the wait times out, the caller
//! returns while the task may still be queued. With the task on the caller's
//! stack, the app thread would later write through `ctx` into a stack frame
//! that had already died: a use-after-free. That is exactly what the first
//! version of this boundary did.
//!
//! So the task is heap allocated, and it outlives the caller. The app thread
//! also checks `cancelled` before touching the payload, because the payload
//! itself may still be stack memory the caller has abandoned.
//!
//! ## Contract
//!
//! - The caller owns the task (heap) and, while waiting, the payload (stack).
//!   Once the caller stops waiting it must mark the task cancelled.
//! - The app thread runs the closure only if the task was not cancelled, then
//!   marks it done and frees it.
//! - The closure must be short. It runs on the thread that drives the terminal;
//!   anything slow there is a UI stall, not just a slow request.
//! - This module imports std and nothing else, so core and IPC can both use it
//!   without an import cycle.

const std = @import("std");

/// A closure to run on the app thread.
pub const Task = struct {
    ctx: *anyopaque,
    run: *const fn (ctx: *anyopaque) void,

    mutex: std.Io.Mutex = .init,
    /// Written by the app thread last, read by the caller first.
    done: bool = false,
    /// Set by the caller when it gives up waiting. The app thread must check
    /// it before touching `ctx`, because the payload may already be gone.
    cancelled: bool = false,
    /// Set by the app thread when it takes ownership of the payload.
    claimed: bool = false,

    /// Allocate a task on the heap.
    ///
    /// The allocator must be thread-safe: the task is created on a connection
    /// thread and freed on the app thread. `std.heap.c_allocator` is used for
    /// exactly this reason elsewhere in the GTK IPC runtime.
    pub fn create(
        gpa: std.mem.Allocator,
        ctx: anytype,
        func: *const fn (*anyopaque) void,
    ) !*Task {
        const task = try gpa.create(Task);
        task.* = .{ .ctx = @ptrCast(ctx), .run = func };
        return task;
    }

    /// Free the task.
    ///
    /// Only safe once BOTH sides are finished with it: the app thread will not
    /// touch it again, and the caller has stopped polling it. The app thread
    /// alone cannot know the second part, so the CALLER frees the task once it
    /// observes `done`. That is why `runOnAppThread` owns the free.
    pub fn destroy(self: *Task, gpa: std.mem.Allocator) void {
        gpa.destroy(self);
    }

    /// Claim the task for execution.
    ///
    /// Returns false if the caller already gave up, in which case the payload
    /// may be gone and must not be touched.
    pub fn claim(self: *Task) bool {
        const io = threadIo();
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (self.cancelled) return false;
        self.claimed = true;
        return true;
    }

    /// Mark the task finished by the app thread.
    pub fn finish(self: *Task) void {
        const io = threadIo();
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        self.done = true;
    }

    /// Give up waiting.
    ///
    /// Returns true if the caller won the race: the app thread had not yet
    /// claimed the task, so it will not touch the payload. Returns false if
    /// the app thread already claimed it, which means the closure is running
    /// RIGHT NOW and may still be reading the payload.
    ///
    /// The caller must therefore keep its payload alive until the app thread
    /// reports the task done, even after a timeout. `runOnAppThread` handles
    /// that by waiting for `done` after cancelling.
    pub fn cancel(self: *Task) bool {
        const io = threadIo();
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (self.claimed) return false;
        self.cancelled = true;
        return true;
    }

    /// Has the app thread finished with this task?
    pub fn isDone(self: *Task) bool {
        const io = threadIo();
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        return self.done;
    }
};

/// The I/O implementation the mutex primitives need.
fn threadIo() std.Io {
    return @import("../../global.zig").io();
}
