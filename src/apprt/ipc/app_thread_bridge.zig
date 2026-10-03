//! K-E02a experimental correlated bridge from worker threads to the core app thread.
//!
//! This deliberately does not mount the socket server. It proves the ownership
//! primitive first: producers publish heap-owned requests, wake the runtime, the
//! app thread executes them during CoreApp.tick, and callers correlate completion.
//! No terminal/App pointer is dereferenced by the producer thread.
//!
//! Request lifetime is split between caller ownership and queued-work ownership.
//! A queued timeout/cancellation may let the caller return because the queued
//! reference keeps the request alive and the callback will be skipped. Once a
//! callback starts executing, the caller cannot time out and invalidate callback
//! context underneath the app thread.

const std = @import("std");
const BlockingQueue = @import("../../datastruct/main.zig").BlockingQueue;

const Allocator = std.mem.Allocator;

pub const BridgeError = error{QueueFull};
pub const WaitError = error{Timeout};

pub const Ticket = u64;

pub const State = enum {
    queued,
    executing,
    completed,
    canceled,
};

pub const Request = struct {
    gpa: Allocator,
    ctx: *anyopaque,
    run: *const fn (*anyopaque) void,
    cleanup: ?*const fn (*anyopaque) void = null,

    /// Starts with caller ownership only. Bridge.submit temporarily retains
    /// queued ownership before publishing into the queue and releases it again
    /// if publication fails.
    refs: std.atomic.Value(u8) = .init(1),

    mutex: std.Thread.Mutex = .{},
    condition: std.Thread.Condition = .{},
    state: State = .queued,

    pub fn create(
        gpa: Allocator,
        ctx: *anyopaque,
        run: *const fn (*anyopaque) void,
    ) Allocator.Error!*Request {
        const self = try gpa.create(Request);
        self.* = .{
            .gpa = gpa,
            .ctx = ctx,
            .run = run,
            .cleanup = null,
        };
        return self;
    }

    pub fn createWithCleanup(
        gpa: Allocator,
        ctx: *anyopaque,
        run: *const fn (*anyopaque) void,
        cleanup: *const fn (*anyopaque) void,
    ) Allocator.Error!*Request {
        const self = try create(gpa, ctx, run);
        self.cleanup = cleanup;
        return self;
    }

    /// Release caller ownership. The caller must first observe completion,
    /// cancellation, or a failed submit. Releasing while queued/executing would
    /// make callback context lifetime ambiguous and is a programmer error.
    pub fn releaseCaller(self: *Request) void {
        self.mutex.lock();
        const safe = self.state == .completed or self.state == .canceled;
        self.mutex.unlock();
        std.debug.assert(safe);
        self.release();
    }

    /// Synchronized state observation for diagnostics/tests. This does not
    /// transfer ownership and must never be used as a substitute for wait().
    pub fn stateSnapshot(self: *Request) State {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.state;
    }

    /// Cancel only if execution has not started. A false result means the caller
    /// must keep its context alive and wait for the executing request to finish.
    pub fn cancelQueued(self: *Request) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.state != .queued) return false;
        self.state = .canceled;
        self.condition.broadcast();
        return true;
    }

    /// Wait for completion/cancellation.
    ///
    /// A timeout while still queued atomically cancels the request and returns
    /// Timeout. If the app thread has already transitioned to executing, the
    /// wait deliberately becomes unbounded until that callback completes; this
    /// prevents a timed-out caller from freeing callback context in use.
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

    fn retainQueued(self: *Request) void {
        const previous = self.refs.fetchAdd(1, .monotonic);
        std.debug.assert(previous > 0);
    }

    fn publishFailed(self: *Request) void {
        _ = self.cancelQueued();
        self.release();
    }

    /// App-thread execution consumes queued ownership exactly once.
    fn runQueued(self: *Request) State {
        self.mutex.lock();
        if (self.state == .canceled) {
            self.mutex.unlock();
            if (self.cleanup) |cleanup| cleanup(self.ctx);
            self.release();
            return .canceled;
        }

        std.debug.assert(self.state == .queued);
        self.state = .executing;
        self.mutex.unlock();

        self.run(self.ctx);

        self.mutex.lock();
        self.state = .completed;
        self.condition.broadcast();
        self.mutex.unlock();

        self.release();
        return .completed;
    }

    /// App-thread shutdown path. Pending work is canceled without executing and
    /// queued ownership is consumed. A caller waiting without a timeout wakes
    /// and observes canceled.
    fn cancelFromQueue(self: *Request) void {
        self.mutex.lock();
        if (self.state == .queued) self.state = .canceled;
        std.debug.assert(self.state == .canceled);
        self.condition.broadcast();
        self.mutex.unlock();
        if (self.cleanup) |cleanup| cleanup(self.ctx);
        self.release();
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

pub const Work = struct {
    ticket: Ticket,
    request: *Request,
};

pub const Bridge = struct {
    const Queue = BlockingQueue(Work, 64);

    io: std.Io,
    queue: Queue = .{},
    next_ticket: std.atomic.Value(Ticket) = .init(1),

    pub fn init(io: std.Io) Bridge {
        return .{ .io = io };
    }

    /// Producer-thread publication. Successful publication transfers one queued
    /// reference to the app thread. QueueFull leaves the request canceled with
    /// caller ownership intact so it can be safely released.
    pub fn submit(self: *Bridge, request: *Request) BridgeError!Ticket {
        const ticket = self.next_ticket.fetchAdd(1, .monotonic);
        request.retainQueued();

        const size = self.queue.push(
            self.io,
            .{ .ticket = ticket, .request = request },
            .{ .instant = {} },
        );
        if (size == 0) {
            request.publishFailed();
            return error.QueueFull;
        }

        return ticket;
    }

    /// Runtime/app-thread operation. Must only be called from CoreApp.tick.
    pub fn drainOnAppThread(self: *Bridge) usize {
        var drained = self.queue.drain(self.io);
        defer drained.deinit(self.io);

        var count: usize = 0;
        while (drained.next()) |work| {
            _ = work.request.runQueued();
            count += 1;
        }
        return count;
    }

    /// CoreApp shutdown operation. Must run on the app thread before bridge
    /// storage is destroyed. Pending callbacks do not execute.
    pub fn cancelPendingOnAppThread(self: *Bridge) usize {
        var drained = self.queue.drain(self.io);
        defer drained.deinit(self.io);

        var count: usize = 0;
        while (drained.next()) |work| {
            work.request.cancelFromQueue();
            count += 1;
        }
        return count;
    }
};

test "bridge executes only when app-thread drain runs and correlates completion" {
    var bridge = Bridge.init(std.testing.io);
    var value: usize = 0;

    const Ctx = struct {
        fn run(ptr: *anyopaque) void {
            const n: *usize = @ptrCast(@alignCast(ptr));
            n.* += 1;
        }
    };

    const request = try Request.create(std.testing.allocator, &value, Ctx.run);
    const ticket = try bridge.submit(request);
    try std.testing.expect(ticket != 0);
    try std.testing.expectEqual(@as(usize, 0), value);

    try std.testing.expectEqual(@as(usize, 1), bridge.drainOnAppThread());
    try std.testing.expectEqual(State.completed, try request.wait(null));
    try std.testing.expectEqual(@as(usize, 1), value);
    request.releaseCaller();
}

test "queued timeout cancels callback but published request remains valid until drain" {
    var bridge = Bridge.init(std.testing.io);
    var value: usize = 0;

    const Ctx = struct {
        fn run(ptr: *anyopaque) void {
            const n: *usize = @ptrCast(@alignCast(ptr));
            n.* += 1;
        }
    };

    const request = try Request.create(std.testing.allocator, &value, Ctx.run);
    _ = try bridge.submit(request);

    try std.testing.expectError(error.Timeout, request.wait(1));
    try std.testing.expectEqual(@as(usize, 1), bridge.drainOnAppThread());
    try std.testing.expectEqual(@as(usize, 0), value);
    request.releaseCaller();
}

test "shutdown cancels pending work and wakes ownership state without executing" {
    var bridge = Bridge.init(std.testing.io);
    var value: usize = 0;

    const Ctx = struct {
        fn run(ptr: *anyopaque) void {
            const n: *usize = @ptrCast(@alignCast(ptr));
            n.* += 1;
        }
    };

    const request = try Request.create(std.testing.allocator, &value, Ctx.run);
    _ = try bridge.submit(request);

    try std.testing.expectEqual(@as(usize, 1), bridge.cancelPendingOnAppThread());
    try std.testing.expectEqual(State.canceled, try request.wait(null));
    try std.testing.expectEqual(@as(usize, 0), value);
    request.releaseCaller();
}

test "tickets are monotonic correlation identities" {
    var bridge = Bridge.init(std.testing.io);
    var value: usize = 0;
    const Ctx = struct {
        fn run(ptr: *anyopaque) void {
            const n: *usize = @ptrCast(@alignCast(ptr));
            n.* += 1;
        }
    };

    const a = try Request.create(std.testing.allocator, &value, Ctx.run);
    const b = try Request.create(std.testing.allocator, &value, Ctx.run);
    const ta = try bridge.submit(a);
    const tb = try bridge.submit(b);
    try std.testing.expect(tb > ta);
    try std.testing.expectEqual(@as(usize, 2), bridge.drainOnAppThread());
    try std.testing.expectEqual(State.completed, try a.wait(null));
    try std.testing.expectEqual(State.completed, try b.wait(null));
    a.releaseCaller();
    b.releaseCaller();
}

test "cancelled queued request runs cleanup exactly once" {
    var bridge = Bridge.init(std.testing.io);
    const Counters = struct { ran: usize = 0, cleaned: usize = 0 };
    var counters: Counters = .{};
    const Ctx = struct {
        fn run(ptr: *anyopaque) void {
            const c: *Counters = @ptrCast(@alignCast(ptr));
            c.ran += 1;
        }
        fn cleanup(ptr: *anyopaque) void {
            const c: *Counters = @ptrCast(@alignCast(ptr));
            c.cleaned += 1;
        }
    };
    const request = try Request.createWithCleanup(std.testing.allocator, &counters, Ctx.run, Ctx.cleanup);
    _ = try bridge.submit(request);
    try std.testing.expect(request.cancelQueued());
    try std.testing.expectEqual(@as(usize, 1), bridge.drainOnAppThread());
    try std.testing.expectEqual(@as(usize, 0), counters.ran);
    try std.testing.expectEqual(@as(usize, 1), counters.cleaned);
    request.releaseCaller();
}

test "wrong request state cannot execute callback twice" {
    var bridge = Bridge.init(std.testing.io);
    var value: usize = 0;
    const Ctx = struct {
        fn run(ptr: *anyopaque) void {
            const n: *usize = @ptrCast(@alignCast(ptr));
            n.* += 1;
        }
    };
    const request = try Request.create(std.testing.allocator, &value, Ctx.run);
    _ = try bridge.submit(request);
    try std.testing.expectEqual(@as(usize, 1), bridge.drainOnAppThread());
    try std.testing.expectEqual(@as(usize, 0), bridge.drainOnAppThread());
    try std.testing.expectEqual(@as(usize, 1), value);
    try std.testing.expectEqual(State.completed, try request.wait(null));
    request.releaseCaller();
}

test "queue-full publication cancels request without executing it" {
    var bridge = Bridge.init(std.testing.io);
    var values: [65]usize = [_]usize{0} ** 65;
    const Ctx = struct {
        fn run(ptr: *anyopaque) void {
            const n: *usize = @ptrCast(@alignCast(ptr));
            n.* += 1;
        }
    };
    var requests: [65]*Request = undefined;
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        requests[i] = try Request.create(std.testing.allocator, &values[i], Ctx.run);
        _ = try bridge.submit(requests[i]);
    }
    requests[64] = try Request.create(std.testing.allocator, &values[64], Ctx.run);
    try std.testing.expectError(error.QueueFull, bridge.submit(requests[64]));
    try std.testing.expectEqual(State.canceled, try requests[64].wait(null));
    requests[64].releaseCaller();
    try std.testing.expectEqual(@as(usize, 64), bridge.drainOnAppThread());
    for (requests[0..64], 0..) |req, idx| {
        try std.testing.expectEqual(State.completed, try req.wait(null));
        try std.testing.expectEqual(@as(usize, 1), values[idx]);
        req.releaseCaller();
    }
    try std.testing.expectEqual(@as(usize, 0), values[64]);
}

test "worker submission remains pending until app thread drains" {
    var bridge = Bridge.init(std.testing.io);
    var value: usize = 0;
    const Ctx = struct {
        fn run(ptr: *anyopaque) void {
            const n: *usize = @ptrCast(@alignCast(ptr));
            n.* += 1;
        }
    };
    const request = try Request.create(std.testing.allocator, &value, Ctx.run);
    const Submit = struct {
        fn main(b: *Bridge, req: *Request, out: *std.atomic.Value(bool)) void {
            _ = b.submit(req) catch return;
            out.store(true, .release);
        }
    };
    var submitted: std.atomic.Value(bool) = .init(false);
    const worker = try std.Thread.spawn(.{}, Submit.main, .{ &bridge, request, &submitted });
    worker.join();
    try std.testing.expect(submitted.load(.acquire));
    try std.testing.expectEqual(@as(usize, 0), value);
    try std.testing.expectEqual(State.queued, request.stateSnapshot());
    try std.testing.expectEqual(@as(usize, 1), bridge.drainOnAppThread());
    try std.testing.expectEqual(@as(usize, 1), value);
    try std.testing.expectEqual(State.completed, try request.wait(null));
    request.releaseCaller();
}
