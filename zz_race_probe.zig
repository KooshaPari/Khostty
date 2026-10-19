//! Standalone empirical probe for the pane.write cross-thread parser race.
//! Not part of the build; lives in scratch to iterate fast.
const std = @import("std");
const terminalpkg = @import("src/terminal/main.zig");

const Terminal = terminalpkg.Terminal;
const TerminalStream = terminalpkg.TerminalStream;

const Allocator = std.mem.Allocator;

// OSC 52 uses captureTrailing(.allocating) -> unsynchronized realloc.
fn payload(buf: []u8, tag: u8) []u8 {
    var i: usize = 0;
    buf[i] = 0x1b; i += 1; // ESC
    buf[i] = ']'; i += 1; // ]
    buf[i] = '5'; i += 1;
    buf[i] = '2'; i += 1;
    buf[i] = ';'; i += 1;
    while (i < buf.len) : (i += 1) {
        buf[i] = tag;
    }
    return buf;
}

const Shared = struct {
    gpa: Allocator,
    threaded: std.Io.Threaded,
    io: std.Io,
    terminal: Terminal,
    stream: TerminalStream,

    fn init(gpa: Allocator) !Shared {
        var threaded: std.Io.Threaded = .init(gpa, .{});
        errdefer threaded.deinit();
        var terminal: Terminal = try .init(std.testing.io, gpa, .{ .cols = 80, .rows = 24 });
        errdefer terminal.deinit(gpa);
        const stream: TerminalStream = .init(.{ .allocator = gpa, .handler = .init(&terminal) });
        return .{
            .gpa = gpa,
            .threaded = threaded,
            .io = threaded.io(),
            .terminal = terminal,
            .stream = stream,
        };
    }
};

const N = 2;
const ITERS = 200;
const SLICE = 512;

fn writer(s: *Shared, data: []const u8) void {
    for (0..ITERS) |_| {
        s.stream.nextSlice(data);
    }
}

test "probe: unsynchronized two-thread nextSlice" {
    var s = try Shared.init(std.testing.allocator);
    defer s.terminal.deinit(s.gpa);
    defer s.threaded.deinit();

    var bufs: [N][SLICE]u8 = undefined;
    for (0..N) |i| _ = payload(&bufs[i], 'a' + @as(u8, @intCast(i)));

    var threads: [N]std.Thread = undefined;
    for (0..N) |i| {
        threads[i] = try std.Thread.spawn(.{}, writer, .{ &s, bufs[i][0..] });
    }
    for (threads) |t| t.join();
}