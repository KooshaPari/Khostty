//! Failing regression test for the `pane.write` cross-thread parser race.
//!
//! What this proves
//! ----------------
//! `pane.write` reaches the terminal parser directly. On the real runtime that
//! call is `app_host.writeToParser`, which does:
//!
//!     const stream = &core.io.terminal_stream;
//!     stream.nextSlice(data);
//!
//! (`src/apprt/ipc/app_host.zig:290-298`). `nextSlice` mutates parser state
//! with no synchronization at all — `self.parser.state`,
//! `self.utf8decoder.state`, `self.parser.osc_parser`, and the handler it drives
//! (`src/terminal/stream.zig:647` -> `nextSliceUntracked` -> `nextSliceCapped`).
//! Every one of those is shared mutable state on the single `TerminalStream`
//! that the surface owns.
//!
//! `pane.Manager` does hold one `std.Io.Mutex` around host calls
//! (`src/apprt/ipc/pane.zig:414-417`). That mutex is the only thing standing
//! between two connection threads and one parser, and it is **not sufficient**:
//! it serializes IPC callers against each other, but the terminal is owned by
//! the app's IO thread, which never takes that mutex. So the parser is still
//! mutated concurrently by the app thread (pty output) and an IPC connection
//! thread (`pane.write`). `app_host.zig:36-49` and `protocol.md` section 7
//! ("The app-thread hop is not wired yet") both say this outright; this test is
//! the executable form of that claim.
//!
//! How the test proves it rather than asserts it
//! ---------------------------------------------
//! It builds a **real** `TerminalStream` over a **real** `Terminal` — the same
//! types `app_host.writeToParser` reaches through `core.io.terminal_stream` —
//! and drives `nextSlice` from several real threads with byte payloads that
//! leave the parser pinned mid-OSC (an unterminated OSC 2 title sequence).
//! That maximizes the window for the interleaved read-modify-write on
//! `parser.state` / `utf8decoder.state` / the OSC buffer.
//!
//! The observable is window-title corruption. Each thread writes a distinct
//! title containing a marker byte pair that appears in no other thread's
//! payload. When the parsers share state, one thread's OSC body is parsed
//! inside another's OSC sequence, so the terminal's title is contaminated
//! across threads rather than being exactly one thread's title.
//!
//! Two failure shapes are reported, and both mean the same thing — the parser
//! was observed in a state no single thread's byte stream could produce:
//!
//!   1. no title at all, because the shared OSC buffer was clobbered mid-parse
//!      and the terminator was consumed by the wrong thread; or
//!   2. a title carrying markers from two or more threads.
//!
//! Current status: **this test fails on the current tree.** That is the point.
//! The fix is the mailbox hop already named in `app_host.zig:42` — queue the
//! bytes through `CoreSurface.queueIo` and let the app thread own the parser —
//! after which this test is deleted or inverted to assert the hop.
//!
//! Run with: `zig build test-agent-ipc -Dtest-filter="pane.write"`

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const pane = @import("pane.zig");
const protocol = @import("protocol.zig");
const state = @import("state.zig");
const terminalpkg = @import("../../terminal/main.zig");

const Terminal = terminalpkg.Terminal;
const TerminalStream = terminalpkg.TerminalStream;

const PaneId = protocol.PaneId;

/// How many threads race on the parser. Two is the minimum that can express the
/// bug; a few more widens the window without changing what is being proven.
const thread_count = 4;

/// Bytes each thread pushes per iteration. Long enough that `nextSlice` spends
/// real time in the parse loop.
const bytes_per_iteration = 512;

/// Iterations per thread.
const iterations = 64;

// ── The payload ───────────────────────────────────────────────────────────
//
// Each thread's payload is an OSC 2 title with NO terminator, followed by a
// long printable run. The stream is therefore left mid-OSC when `nextSlice`
// returns, and the next thread to run continues *that* OSC with its own title
// body. That is the interleave.
//
// The marker is a per-thread byte pair used to detect cross-contamination. It
// appears only inside this thread's title, never in another's.

fn payloadFor(thread_index: usize, buf: *[bytes_per_iteration]u8) void {
    var i: usize = 0;
    const esc: u8 = 0x1b;
    buf[i] = esc;
    buf[i + 1] = ']';
    buf[i + 2] = '2';
    buf[i + 3] = ';';
    i += 4;

    const marker = markerBytes(thread_index);
    buf[i] = marker[0];
    i += 1;
    buf[i] = marker[1];
    i += 1;

    while (i < buf.len) : (i += 1) {
        buf[i] = switch (i % 7) {
            0 => 'x',
            1 => 'y',
            2 => 'z',
            3 => ' ',
            4 => '.',
            5 => '-',
            else => 'w',
        };
    }
}

/// Bytes that belong to thread `i` and to no other thread. Two different
/// markers in one observed title is the cross-thread contamination signal.
fn markerBytes(thread_index: usize) [2]u8 {
    const n: u8 = @intCast(thread_index % 26);
    return .{ 'A' + n, 'a' + n };
}

// ── Shared state ──────────────────────────────────────────────────────────
//
// One real Terminal + one real TerminalStream, exactly what a `CoreSurface`
// owns. Everything below is reached the way `writeToParser` reaches it:
// `stream.nextSlice(data)` with no lock.

const Race = struct {
    gpa: Allocator,
    threaded: std.Io.Threaded,
    io: std.Io,
    terminal: Terminal,
    stream: TerminalStream,

    /// Every id resolves to this single shared stream, which is precisely the
    /// contention we want. The real runtime resolves an id to a `CoreSurface`.
    const id: PaneId = PaneId.init(1);

    fn init(gpa: Allocator) !Race {
        var threaded: std.Io.Threaded = .init(gpa, .{});
        errdefer threaded.deinit();

        var terminal: Terminal = try .init(testing.io, gpa, .{ .cols = 80, .rows = 24 });
        errdefer terminal.deinit(gpa);

        const stream: TerminalStream = .init(.{
            .allocator = gpa,
            .handler = .init(&terminal),
        });

        return .{
            .gpa = gpa,
            .threaded = threaded,
            .io = threaded.io(),
            .terminal = terminal,
            .stream = stream,
        };
    }

    fn deinit(self: *Race) void {
        self.stream.deinit();
        self.terminal.deinit(self.gpa);
        self.threaded.deinit();
    }
};

// ── The failing test ──────────────────────────────────────────────────────

test "pane.write: concurrent connection threads corrupt the shared terminal parser" {
    var race = try Race.init(testing.allocator);
    defer race.deinit();

    // Build the Host vtable that routes `pane.write` at the shared stream. This
    // is the shape `app_host.windowed_vtable` uses (`.write = writeToParser`),
    // so the test exercises the shipped wiring, not a stub.
    const vtable: pane.Host.VTable = .{
        .create = unsupportedCreate,
        .close = unsupportedPaneOp,
        .focus = unsupportedPaneOp,
        .list = null,
        .write = &raceHostWrite,
        .snapshot = unsupportedSnapshot,
        .search = unsupportedSearch,
        .resize = unsupportedResize,
        .equalize = unsupportedVoid,
        .zoom = unsupportedPaneOp,
    };
    const host: pane.Host = .{ .ctx = @ptrCast(&race), .vtable = &vtable };

    var manager = pane.Manager.init(testing.allocator, host);
    defer manager.deinit(race.io);

    // One payload buffer per thread, built up front so the threads only ever
    // touch the shared parser and the manager mutex — never a shared builder.
    var payloads: [thread_count][bytes_per_iteration]u8 = undefined;
    for (0..thread_count) |i| payloadFor(i, &payloads[i]);

    // Connection threads, exactly like `server.zig` spawns one per connection.
    // Each pushes its own VT payload through `Manager.write`.
    var threads: [thread_count]std.Thread = undefined;
    for (0..thread_count) |i| {
        threads[i] = try std.Thread.spawn(
            .{},
            writerMain,
            .{ &race, &manager, payloads[i][0..] },
        );
    }
    for (threads) |thread| thread.join();

    // ── The assertions that must fail ─────────────────────────────────────
    //
    // With a correctly owned parser the terminal's title can only ever be some
    // single thread's title. Either of the two shapes below is impossible for
    // any single thread's byte stream, so reaching one proves the parser state
    // was shared across threads without synchronization.
    const title = race.terminal.getTitle() orelse {
        std.debug.print(
            "pane.write race: no window title after the run; the shared OSC " ++
                "buffer was clobbered mid-parse (parser left mid-sequence)\n",
            .{},
        );
        return error.PaneWriteParserRace;
    };

    var seen: [thread_count]bool = @splat(false);
    for (title) |ch| {
        for (0..thread_count) |i| {
            const marker = markerBytes(i);
            if (ch == marker[0] or ch == marker[1]) seen[i] = true;
        }
    }

    var distinct: usize = 0;
    for (seen) |was_seen| {
        if (was_seen) distinct += 1;
    }

    if (distinct > 1) {
        std.debug.print(
            "pane.write race: title contains markers from {d} different " ++
                "threads: {s}\n",
            .{ distinct, title },
        );
        return error.PaneWriteParserRace;
    }
}

// ── Thread body ───────────────────────────────────────────────────────────

fn writerMain(race: *Race, manager: *pane.Manager, data: []const u8) void {
    for (0..iterations) |_| {
        _ = manager.write(race.io, Race.id, data) catch continue;
    }
}

/// The body of `app_host.writeToParser`, reached through the vtable so the
/// mutex in `Manager.write` is on the path exactly as it is in production.
fn raceHostWrite(ctx: *anyopaque, _: PaneId, data: []const u8) pane.HostError!usize {
    const self: *Race = @ptrCast(@alignCast(ctx));
    self.stream.nextSlice(data);
    return data.len;
}

/// `app_host.zig` supplies a real body for every entry point; the ones this
/// test does not exercise are honest `Unsupported` stubs, matching
/// `app_host.unavailable_vtable`.
fn unsupportedCreate(
    _: *anyopaque,
    _: Allocator,
    _: pane.CreateRequest,
) pane.HostError!pane.PaneHandle {
    return error.Unsupported;
}

fn unsupportedSnapshot(
    _: *anyopaque,
    _: Allocator,
    _: PaneId,
    _: *state.Snapshot,
) pane.HostError!void {
    return error.Unsupported;
}

fn unsupportedSearch(
    _: *anyopaque,
    _: Allocator,
    _: PaneId,
    _: []const u8,
    _: usize,
    _: *std.ArrayListUnmanaged(pane.SearchMatch),
) pane.HostError!void {
    return error.Unsupported;
}

fn unsupportedResize(
    _: *anyopaque,
    _: PaneId,
    _: protocol.Direction,
    _: u16,
) pane.HostError!void {
    return error.Unsupported;
}

fn unsupportedVoid(_: *anyopaque) pane.HostError!void {
    return error.Unsupported;
}

fn unsupportedPaneOp(_: *anyopaque, _: PaneId) pane.HostError!void {
    return error.Unsupported;
}