//! QUARANTINED — parked, does not run by default. Not deleted.
//!
//! Run it with:
//!
//!     zig build test-agent-ipc -Dtest-filter="pane.write" \
//!       -Dtest-quarantine=write-parser-race
//!
//! Why it is parked
//! ----------------
//! Tracking issue: KooshaPari/Khostty#48.
//! Owning follow-up fix node: `race-test-valid-repro` (plan) — a correct repro
//! must be written *against the real defect*, which is an app-thread vs
//! IPC-thread race, not an IPC-thread vs IPC-thread race. See below.
//!
//! The original version of this test asserted a claim that is **false**, so it
//! failed for a reason unrelated to the bug it claimed to demonstrate. The
//! claim was: "`pane.write` mutates the parser from several IPC connection
//! threads at once, so the parser is corrupted."
//!
//! That is not what the code does. `Manager.write` holds the one manager mutex
//! across the whole host call:
//!
//!     pub fn write(self: *Manager, io: std.Io, id: PaneId, data: []const u8) Error!usize {
//!         self.mutex.lockUncancelable(io);
//!         defer self.mutex.unlock(io);
//!         return self.host.write(id, data);
//!     }
//!
//! (`src/apprt/ipc/pane.zig:414-419`). `host.write` is `writeToParser`, and it
//! runs *inside* that critical section, so every `stream.nextSlice(data)` call
//! this test makes is serialized against every other one. Four threads calling
//! `Manager.write` therefore execute one-at-a-time. There is no
//! concurrent `nextSlice` to interleave, so there is no data race to observe.
//! `pane.zig:17-18` states this contract explicitly: "one manager mutex
//! serializes registry access *and* host calls, so host implementations do not
//! need to be thread safe."
//!
//! The test still failed, every run, and it failed for a mundane reason: it
//! never sends the OSC terminator (`ESC \` / ST). Every payload is an
//! *unterminated* OSC 2 title, so no thread ever completes a title sequence and
//! the title is never set at all. The test then hit its own first failure
//! shape ("no title at all") on a completely single-threaded code path. So
//! "fails unconditionally" was true, but not for the reason stated, and no
//! amount of threads would ever make it pass.
//!
//! What the real defect is
//! ----------------------
//! The underlying hazard is still real and still documented, just not at the
//! seam this test drove. It is an **app-thread vs IPC-thread** race:
//!
//!   * the terminal parser is owned by the app's IO thread;
//!   * an IPC connection thread reaches it through `writeToParser`
//!     (`src/apprt/ipc/app_host.zig:290-298`), which calls
//!     `stream.nextSlice(data)` with no synchronization of its own;
//!   * pty output reaches the *same* parser from the app thread, and the app
//!     thread never takes `Manager`'s mutex, so the manager mutex cannot
//!     serialize the two.
//!
//! `app_host.zig:36-49` and `protocol.md` section 7 ("The app-thread hop is not
//! wired yet") both say this outright, and the fix they name — queue the bytes
//! through `CoreSurface.queueIo` so the app thread owns the parser — is
//! unchanged by this quarantine. That hop does not exist yet, so there is no
//! second thread to race against and no correct repro to write against it
//! today.
//!
//! How to write the real repro when the hop lands (node `race-test-valid-repro`)
//! ----------------------------------------------------------------------------
//! The test has to span the two *different* threads, not four copies of the same
//! one. `Manager`'s mutex is a correct serializer for N IPC threads and always
//! will be; it is simply the wrong lock for app-thread-vs-IPC-thread. A valid
//! repro drives `stream.nextSlice` from the app thread (simulating pty output)
//! while a connection thread is inside `writeToParser`, and asserts the
//! corruption that only *that* pairing can produce. It also has to terminate
//! its OSC sequences so the success condition is reachable at all.
//!
//! Until then this file stays exactly as-is minus the skip gate below. The
//! repro, the payload construction, the marker scheme, and the vtable wiring
//! that routes `pane.write` at the real parser are all retained so the next
//! person does not rebuild them.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

// The name this test is parked under. `-Dtest-quarantine` must match it
// exactly for the test to run; anything else (including the default, empty
// string) skips it.
const quarantine_name = "write-parser-race";

const quarantine = @import("test_quarantine");

/// The skip gate. Returns true (and skips) unless the build was invoked with
/// `-Dtest-quarantine=write-parser-race`.
///
/// This is a *runtime* gate on purpose, not a `comptime` one: gating at
/// comptime would mean the body below is never analyzed, which would silently
/// turn this file into dead code that rots. As written, the whole repro is
/// still compiled and type-checked on every default `zig build test-agent-ipc`,
/// so a future edit that breaks it fails the required check at compile time —
/// it just cannot fail at runtime.
///
/// Zig's test runner reports `error.SkipZigTest` as SKIPPED, not failed, so the
/// required `ci/zig-fork-tests` check stays green while the evidence stays in
/// the tree.
fn quarantineGate() bool {
    if (std.mem.eql(u8, quarantine.name, quarantine_name)) return false;

    std.debug.print(
        "SKIP pane.write parser race: quarantined (invalid premise). " ++
            "To run it: zig build test-agent-ipc " ++
            "-Dtest-filter=\"pane.write\" -Dtest-quarantine=" ++
            quarantine_name ++ "\n",
        .{},
    );
    return true;
}

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
    // QUARANTINED. Skipped by default so this cannot redden the required
    // `ci/zig-fork-tests` check. The body below is still compiled and
    // type-checked on every default build; only the run is gated.
    if (quarantineGate()) return error.SkipZigTest;

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
