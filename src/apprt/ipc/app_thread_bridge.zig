//! K-E02a experiment: lifetime-safe request completion for crossing from
//! agent connection threads into the application-owned thread.
//!
//! This file intentionally does NOT mount the IPC server. It establishes the
//! ownership primitive needed before a queued app-thread callback can be safe.
//! A request has two references: the caller and the queued app-thread work item.
//! Timeout/cancellation may release the caller only while work is still queued;
//! once execution begins, the caller must stay alive until completion so callback
//! context cannot become dangling memory.

const std = @import("std");

const Allocator = std.mem.Allocator;

pub const State = enum {
    queued,
    executing,
    completed,
    canceled,
};

pub const WaitError = error{Timeout};

pub const Request = struct {
    gpa: Allocator,
    callback: *const fn (*anyopaque) void,
    context: *anyopaque,

    /// One reference belongs to the caller and one to the queued app-thread
    /// message. The queued reference is released only by runQueued() or by
    /// abandonQueued() when enqueueing failed before the message became visible.
    refs: std.atomic.Value(u8) = .init(2),

    mutex: std.Thread.Mutex = .{},
    condition: std.Thread.Condition = .{},
    state: State = .queued,

    pub fn create(
        gpa: Allocator,
        context: *anyopaque,
        callback: *const fn (*anyopaque) void,
    ) Allocator.Error!*Request {
        const self = try gpa.create(Request);
        self.* = .{
            .gpa = gpa,
            .callback = callback,
            .context = context,
        };
        return self;
    }

    /// Caller reference. Call exactly once after the caller no longer needs the
    /// request. It is safe to do this after a queued timeout because the queued
    /// reference keeps the request allocated until the app thread observes it.
    pub fn releaseCaller(self: *Request) void {
        self.release();
    }

    /// Queue reference. Use only when enqueueing failed and the work item was
    /// never published to the application mailbox.
    pub fn abandonQueued(self: *Request) void {
        self.release();
    }

    /// Cancel work that has not started. This never claims to cancel an
    /// executing callback.
    pub fn cancelQueued(self: *Request) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.state != .queued) return false;
        self.state = .canceled;
        self.condition.broadcast();
        return true;
    }

    /// Wait for completion. If timeout happens while the request is still
    /// queued, it is atomically changed to canceled and Timeout is returned.
    ///
    /// If execution already started, timeout is deliberately NOT allowed to
    /// return the caller early: doing so could invalidate callback context
    /// while the application thread is still using it. The wait then continues
    /// until the executing callback acknowledges completion.
    pub fn wait(self: *Request, timeout_ns: ?u64) WaitError!State {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.state == .queued) {
            if (timeout_ns) |ns| {
                self.condition.timedWait(&self.mutex, ns) catch |err| switch (err) {
                    error.Timeout => {
                        if (self.state == .queued) {
                            self.state = .canceled;
                            return error.Timeout;
                        }
                    },
                };
            } else {
                self.condition.wait(&self.mutex);
            }
        }

        while (self.state == .executing) {
            self.condition.wait(&self.mutex);
        }

        return self.state;
    }

    /// Application-thread side. A canceled queued request skips the callback.
    /// The queued reference is always consumed exactly once by this function.
    pub fn runQueued(self: *Request) State {
        self.mutex.lock();
        if (self.state == .canceled) {
            self.mutex.unlock();
            self.release();
            return .canceled;
        }

        std.debug.assert(self.state == .queued);
        self.state = .executing;
        self.mutex.unlock();

        self.callback(self.context);

        self.mutex.lock();
        self.state = .completed;
        self.condition.broadcast();
        self.mutex.unlock();

        self.release();
        return .completed;
    }

    fn release(self: *Request) void {
        const previous = self.refs.fetchSub(1, .acq_rel);
        std.debug.assert(previous > 0);
        if (previous == 1) {
            const gpa = self.gpa;
            gpa.destroy(self);
        }
    }
};

test "queued request completes and keeps caller ownership until release" {
    const testing = std.testing;

    var called = false;
    const Callback = struct {
        fn run(raw: *anyopaque) void {
            const flag: *bool = @ptrCast(@alignCast(raw));
            flag.* = true;
        }
    };

    const request = try Request.create(testing.allocator, &called, Callback.run);
    try testing.expectEqual(State.completed, request.runQueued());
    try testing.expectEqual(State.completed, try request.wait(null));
    try testing.expect(called);
    request.releaseCaller();
}

test "queued timeout cancels callback without freeing published request" {
    const testing = std.testing;

    var called = false;
    const Callback = struct {
        fn run(raw: *anyopaque) void {
            const flag: *bool = @ptrCast(@alignCast(raw));
            flag.* = true;
        }
    };

    const request = try Request.create(testing.allocator, &called, Callback.run);

    try testing.expectError(error.Timeout, request.wait(1));
    try testing.expectEqual(State.canceled, request.runQueued());
    try testing.expect(!called);

    request.releaseCaller();
}

test "explicit queued cancellation is observed by application side" {
    const testing = std.testing;

    var called = false;
    const Callback = struct {
        fn run(raw: *anyopaque) void {
            const flag: *bool = @ptrCast(@alignCast(raw));
            flag.* = true;
        }
    };

    const request = try Request.create(testing.allocator, &called, Callback.run);
    try testing.expect(request.cancelQueued());
    try testing.expectEqual(State.canceled, try request.wait(null));
    try testing.expectEqual(State.canceled, request.runQueued());
    try testing.expect(!called);
    request.releaseCaller();
}

test "failed enqueue can abandon queued ownership without leak" {
    const testing = std.testing;

    var called = false;
    const Callback = struct {
        fn run(raw: *anyopaque) void {
            const flag: *bool = @ptrCast(@alignCast(raw));
            flag.* = true;
        }
    };

    const request = try Request.create(testing.allocator, &called, Callback.run);
    request.abandonQueued();
    request.releaseCaller();
    try testing.expect(!called);
}
