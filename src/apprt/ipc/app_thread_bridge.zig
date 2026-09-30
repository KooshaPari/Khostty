//! K-E02a experimental correlated bridge from worker threads to the core app thread.
//!
//! This deliberately does not mount the socket server. It proves the ownership
//! primitive first: producers enqueue opaque work, wake the runtime, the app
//! thread executes it during CoreApp.tick, and callers can correlate completion.
//! No terminal/App pointer is dereferenced by the producer thread.

const std = @import("std");
const BlockingQueue = @import("../../datastruct/main.zig").BlockingQueue;

pub const BridgeError = error{
    QueueFull,
    Cancelled,
    TimedOut,
};

pub const Ticket = u64;

pub const Work = struct {
    ticket: Ticket,
    ctx: *anyopaque,
    run: *const fn (*anyopaque) void,
    completion: *Completion,
};

pub const Completion = struct {
    done: std.atomic.Value(bool) = .init(false),
    cancelled: std.atomic.Value(bool) = .init(false),

    pub fn cancel(self: *Completion) void {
        self.cancelled.store(true, .release);
    }

    pub fn isDone(self: *const Completion) bool {
        return self.done.load(.acquire);
    }
};

pub const Bridge = struct {
    const Queue = BlockingQueue(Work, 64);

    io: std.Io,
    queue: Queue = .{},
    next_ticket: std.atomic.Value(Ticket) = .init(1),

    pub fn init(io: std.Io) Bridge {
        return .{ .io = io };
    }

    /// Producer-thread operation. The caller owns Completion until done/cancelled.
    pub fn submit(
        self: *Bridge,
        ctx: *anyopaque,
        run: *const fn (*anyopaque) void,
        completion: *Completion,
    ) BridgeError!Ticket {
        const ticket = self.next_ticket.fetchAdd(1, .monotonic);
        const size = self.queue.push(
            self.io,
            .{ .ticket = ticket, .ctx = ctx, .run = run, .completion = completion },
            .{ .instant = {} },
        );
        if (size == 0) return error.QueueFull;
        return ticket;
    }

    /// Runtime/app-thread operation. Must only be called from CoreApp.tick.
    pub fn drainOnAppThread(self: *Bridge) usize {
        var drained = self.queue.drain(self.io);
        defer drained.deinit(self.io);

        var count: usize = 0;
        while (drained.next()) |work| {
            if (!work.completion.cancelled.load(.acquire)) {
                work.run(work.ctx);
            }
            work.completion.done.store(true, .release);
            count += 1;
        }
        return count;
    }
};

test "bridge executes only when app-thread drain runs and correlates completion" {
    var bridge = Bridge.init(std.testing.io);
    var completion: Completion = .{};
    var value: usize = 0;

    const Ctx = struct {
        fn run(ptr: *anyopaque) void {
            const n: *usize = @ptrCast(@alignCast(ptr));
            n.* += 1;
        }
    };

    const ticket = try bridge.submit(&value, Ctx.run, &completion);
    try std.testing.expect(ticket != 0);
    try std.testing.expectEqual(@as(usize, 0), value);
    try std.testing.expect(!completion.isDone());

    try std.testing.expectEqual(@as(usize, 1), bridge.drainOnAppThread());
    try std.testing.expectEqual(@as(usize, 1), value);
    try std.testing.expect(completion.isDone());
}

test "cancelled work completes without executing" {
    var bridge = Bridge.init(std.testing.io);
    var completion: Completion = .{};
    var value: usize = 0;

    const Ctx = struct {
        fn run(ptr: *anyopaque) void {
            const n: *usize = @ptrCast(@alignCast(ptr));
            n.* += 1;
        }
    };

    _ = try bridge.submit(&value, Ctx.run, &completion);
    completion.cancel();
    try std.testing.expectEqual(@as(usize, 1), bridge.drainOnAppThread());
    try std.testing.expectEqual(@as(usize, 0), value);
    try std.testing.expect(completion.isDone());
}
