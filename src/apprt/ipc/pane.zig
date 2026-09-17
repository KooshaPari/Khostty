//! Pane lifecycle for the agent IPC surface: create, close, focus, list,
//! write, state, search.
//!
//! `pane.zig` sits between the JSON command handler (`handler.zig`) and the
//! application runtime (`app_host.zig`). It owns:
//!
//!   * the `Host` vtable, which is the entire surface the IPC layer needs from
//!     the app runtime. Anything not expressible here is not expressible over
//!     IPC, which keeps the coupling honest and the manager unit testable
//!     against `fake_host.zig`.
//!   * the pane registry and the pane ceiling.
//!   * serialization of pane payloads.
//!
//! Split actions always go through the app runtime's existing action system;
//! `pane.zig` never invents behavior the runtime lacks (see `protocol.md` 4.1).
//!
//! Locking: one manager mutex serializes registry access *and* host calls, so
//! host implementations do not need to be thread safe and two concurrent
//! `pane.create` calls cannot race the registry. Consequences, both documented
//! rather than accidental:
//!
//!   * a host call must never call back into the same `Manager` (no reentrancy);
//!   * `Manager` -> `events.Broker` is the only lock ordering used, and nothing
//!     under the broker lock calls back into the manager.
//!
//! Allocator contract: arena parameters belong to the caller and must outlive
//! the returned value. Host implementations must allocate every string they
//! hand back from that arena.
//!
//!     zig test src/apprt/ipc/pane.zig

const std = @import("std");
const Allocator = std.mem.Allocator;

const protocol = @import("protocol.zig");
const state = @import("state.zig");
const events = @import("events.zig");

const PaneId = protocol.PaneId;
const Obj = protocol.Obj;
const Arr = protocol.Arr;
const WriteError = protocol.WriteError;

/// Pane ceiling per instance. Agents that need more can raise it; the point is
/// that an unbounded `pane.create` loop cannot exhaust the runtime.
pub const default_max_panes: usize = 64;

/// Errors a host may return. Every app-runtime failure is mapped into this set
/// so the handler can translate it to a protocol error code without knowing the
/// runtime's error taxonomy.
pub const HostError = error{
    /// The pane id does not address a live pane.
    PaneNotFound,
    /// The pane existed but exited before the operation completed.
    PaneClosed,
    /// The runtime cannot service this operation (for example: no split
    /// support, or a daemonized build with no panes).
    Unsupported,
    /// The runtime hit its own pane limit.
    TooManyPanes,
    /// Unexpected runtime failure.
    Internal,
    OutOfMemory,
};

/// What an agent asked for in `pane.create`.
pub const CreateRequest = struct {
    /// Split direction, already resolved from `split`/`dir` by the handler.
    dir: protocol.Direction = .right,
    /// Pane to split relative to; null means "the focused pane".
    parent: ?PaneId = null,
    cwd: ?[]const u8 = null,
    title: ?[]const u8 = null,
    /// Focus the new pane.
    focus: bool = true,
    /// Reserved for v2; upstream `new_split` accepts no arguments today.
    command: ?[]const u8 = null,
};

/// What a host reports after creating a pane.
pub const PaneHandle = struct {
    id: PaneId,
    pid: ?u32 = null,
    title: ?[]const u8 = null,
    cols: ?u16 = null,
    rows: ?u16 = null,
    focused: ?bool = null,

    pub fn writeJson(self: PaneHandle, w: *std.Io.Writer) WriteError!void {
        var o = try Obj.init(w);
        try o.paneId("pane_id", self.id);
        try o.optUint("pid", if (self.pid) |v| v else null);
        try o.optString("title", self.title);
        try o.optUint("cols", if (self.cols) |v| v else null);
        try o.optUint("rows", if (self.rows) |v| v else null);
        try o.optBool("focused", self.focused);
        try o.close('}');
    }
};

/// One entry of `pane.list`.
pub const PaneInfo = struct {
    id: PaneId,
    title: ?[]const u8 = null,
    pid: ?u32 = null,
    cwd: ?[]const u8 = null,
    cols: ?u16 = null,
    rows: ?u16 = null,
    focused: ?bool = null,
    exited: ?bool = null,

    pub fn writeJson(self: PaneInfo, w: *std.Io.Writer) WriteError!void {
        var o = try Obj.init(w);
        // The draft protocol used `id` here and `pane_id` everywhere else; the
        // implementation standardizes on `pane_id` (see protocol.md 4.1).
        try o.paneId("pane_id", self.id);
        try o.optString("title", self.title);
        try o.optUint("pid", if (self.pid) |v| v else null);
        try o.optString("cwd", self.cwd);
        try o.optUint("cols", if (self.cols) |v| v else null);
        try o.optUint("rows", if (self.rows) |v| v else null);
        try o.optBool("focused", self.focused);
        try o.optBool("exited", self.exited);
        try o.close('}');
    }
};

/// One `pane.search` match. `row` is relative to the top of the scan region
/// (0 is the oldest retained row), `col` is zero-based within that row.
pub const SearchMatch = struct {
    row: i64,
    col: u32,
    len: u32,
    text: []const u8,

    pub fn writeJson(self: SearchMatch, w: *std.Io.Writer) WriteError!void {
        var o = try Obj.init(w);
        try o.int("row", self.row);
        try o.uint("col", self.col);
        try o.uint("len", self.len);
        try o.string("text", self.text);
        try o.close('}');
    }
};

/// Result of `pane.write`.
pub const WriteResult = struct {
    written: usize,

    pub fn writeJson(self: WriteResult, w: *std.Io.Writer) WriteError!void {
        var o = try Obj.init(w);
        try o.uint("written", self.written);
        try o.close('}');
    }
};

/// Render a list of panes as a JSON array. Uses one reusable scratch buffer so
/// arbitrarily long titles or paths cannot overflow a fixed stack buffer.
pub fn writePaneListJson(
    gpa: Allocator,
    panes: []const PaneInfo,
    w: *std.Io.Writer,
) protocol.EncodeError!void {
    var arr = try Arr.init(w);
    var scratch: std.Io.Writer.Allocating = .init(gpa);
    defer scratch.deinit();
    for (panes) |p| {
        scratch.clearRetainingCapacity();
        try p.writeJson(&scratch.writer);
        try arr.raw(scratch.written());
    }
    try arr.close(']');
}

/// The app-runtime interface required by the IPC surface.
pub const Host = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Create a pane. The runtime performs the real split action; when the
        /// runtime cannot report the resulting surface, this returns
        /// `error.Internal` rather than inventing an id.
        create: *const fn (ctx: *anyopaque, arena: Allocator, req: CreateRequest) HostError!PaneHandle,
        /// Close a pane.
        close: *const fn (ctx: *anyopaque, id: PaneId) HostError!void,
        /// Focus a pane.
        focus: *const fn (ctx: *anyopaque, id: PaneId) HostError!void,
        /// List panes. May be null when the runtime cannot enumerate its
        /// surfaces; the manager then falls back to its own registry.
        list: ?*const fn (
            ctx: *anyopaque,
            arena: Allocator,
            out: *std.ArrayListUnmanaged(PaneInfo),
        ) HostError!void = null,
        /// Inject VT bytes into the terminal parser. Returns bytes accepted.
        write: *const fn (ctx: *anyopaque, id: PaneId, data: []const u8) HostError!usize,
        /// Fill a state snapshot for one pane.
        snapshot: *const fn (
            ctx: *anyopaque,
            arena: Allocator,
            id: PaneId,
            out: *state.Snapshot,
        ) HostError!void,
        /// Search a pane's scrollback.
        search: *const fn (
            ctx: *anyopaque,
            arena: Allocator,
            id: PaneId,
            query: []const u8,
            limit: usize,
            out: *std.ArrayListUnmanaged(SearchMatch),
        ) HostError!void,
        /// Resize a split by `amount` cells in `dir`.
        resize: *const fn (ctx: *anyopaque, id: PaneId, dir: protocol.Direction, amount: u16) HostError!void,
        /// Equalize all splits in the pane's window.
        equalize: *const fn (ctx: *anyopaque) HostError!void,
        /// Toggle zoom for a pane.
        zoom: *const fn (ctx: *anyopaque, id: PaneId) HostError!void,
    };

    pub fn create(self: Host, arena: Allocator, req: CreateRequest) HostError!PaneHandle {
        return self.vtable.create(self.ctx, arena, req);
    }

    pub fn close(self: Host, id: PaneId) HostError!void {
        return self.vtable.close(self.ctx, id);
    }

    pub fn focus(self: Host, id: PaneId) HostError!void {
        return self.vtable.focus(self.ctx, id);
    }

    pub fn list(self: Host, arena: Allocator, out: *std.ArrayListUnmanaged(PaneInfo)) HostError!void {
        const f = self.vtable.list orelse return error.Unsupported;
        return f(self.ctx, arena, out);
    }

    pub fn write(self: Host, id: PaneId, data: []const u8) HostError!usize {
        return self.vtable.write(self.ctx, id, data);
    }

    pub fn snapshot(self: Host, arena: Allocator, id: PaneId, out: *state.Snapshot) HostError!void {
        return self.vtable.snapshot(self.ctx, arena, id, out);
    }

    pub fn search(
        self: Host,
        arena: Allocator,
        id: PaneId,
        query: []const u8,
        limit: usize,
        out: *std.ArrayListUnmanaged(SearchMatch),
    ) HostError!void {
        return self.vtable.search(self.ctx, arena, id, query, limit, out);
    }

    pub fn resize(self: Host, id: PaneId, dir: protocol.Direction, amount: u16) HostError!void {
        return self.vtable.resize(self.ctx, id, dir, amount);
    }

    pub fn equalize(self: Host) HostError!void {
        return self.vtable.equalize(self.ctx);
    }

    pub fn zoom(self: Host, id: PaneId) HostError!void {
        return self.vtable.zoom(self.ctx, id);
    }
};

/// Pane registry and host facade.
pub const Manager = struct {
    gpa: Allocator,
    host: Host,
    mutex: std.Io.Mutex = .init,
    max_panes: usize = default_max_panes,
    /// Pane ids this manager has seen. Used as the `pane.list` fallback for
    /// runtimes that cannot enumerate their own surfaces.
    known: std.ArrayListUnmanaged(PaneId) = .empty,
    /// Optional event sink. When set, pane lifecycle changes are published.
    broker: ?*events.Broker = null,

    pub const Error = HostError;

    pub fn init(gpa: Allocator, host: Host) Manager {
        return .{ .gpa = gpa, .host = host };
    }

    pub fn deinit(self: *Manager, io: std.Io) void {
        self.mutex.lockUncancelable(io);
        self.known.deinit(self.gpa);
        self.mutex.unlock(io);
    }

    pub fn setEventBroker(self: *Manager, broker: ?*events.Broker) void {
        self.broker = broker;
    }

    /// Create a pane. Publishes `pane_created` on success and rolls the pane
    /// back if registration fails, so the registry and the runtime cannot
    /// diverge.
    pub fn create(
        self: *Manager,
        arena: Allocator,
        io: std.Io,
        req: CreateRequest,
    ) Error!PaneHandle {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);

        if (self.known.items.len >= self.max_panes) return error.TooManyPanes;

        const handle = try self.host.create(arena, req);
        errdefer self.host.close(handle.id) catch {};

        try self.known.append(self.gpa, handle.id);

        if (self.broker) |broker| {
            _ = broker.publish(io, events.Event.paneCreated(handle.id, handle.title orelse ""));
        }
        return handle;
    }

    /// Close a pane and forget it. Closing an unknown pane is `PaneNotFound`.
    pub fn close(self: *Manager, io: std.Io, id: PaneId) Error!void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);

        try self.host.close(id);
        self.forget(id);

        if (self.broker) |broker| {
            _ = broker.publish(io, events.Event.paneClosed(id, .requested));
        }
    }

    /// Focus a pane.
    pub fn focus(self: *Manager, io: std.Io, id: PaneId) Error!void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        try self.host.focus(id);
    }

    /// Inject VT bytes into a pane's terminal parser.
    ///
    /// This goes through the same parser path as the child process's pty
    /// output, so escape sequences, modes, and the grid are all updated exactly
    /// as if the program had written them. It does *not* type into the child
    /// process; see `protocol.md` (non-goals).
    ///
    /// The host is authoritative about existence: panes created by the user
    /// (or by a non-IPC path) are valid targets even though the registry has
    /// never seen them.
    pub fn write(self: *Manager, io: std.Io, id: PaneId, data: []const u8) Error!usize {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        return self.host.write(id, data);
    }

    /// Read a pane's machine-readable terminal state.
    pub fn snapshot(
        self: *Manager,
        arena: Allocator,
        io: std.Io,
        id: PaneId,
    ) Error!state.Snapshot {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);

        // A pane the host no longer has is reported as closed rather than
        // missing, because the registry proved it existed at some point.
        var snap: state.Snapshot = undefined;
        self.host.snapshot(arena, id, &snap) catch |err| switch (err) {
            error.PaneNotFound => return if (self.findKnown(id) != null)
                error.PaneClosed
            else
                error.PaneNotFound,
            else => return err,
        };
        return snap;
    }

    /// List panes. Prefers the host's list; falls back to the registry with
    /// unknown fields left null when the host cannot enumerate.
    pub fn list(
        self: *Manager,
        arena: Allocator,
        io: std.Io,
        out: *std.ArrayListUnmanaged(PaneInfo),
    ) Error!void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);

        if (self.host.vtable.list != null) {
            self.host.list(arena, out) catch |err| switch (err) {
                error.Unsupported => return self.listFromRegistry(out),
                else => return err,
            };
            return;
        }
        return self.listFromRegistry(out);
    }

    fn listFromRegistry(
        self: *Manager,
        out: *std.ArrayListUnmanaged(PaneInfo),
    ) Error!void {
        for (self.known.items) |id| {
            try out.append(self.gpa, .{ .id = id });
        }
    }

    /// Whether this manager has seen the pane.
    pub fn isKnown(self: *Manager, io: std.Io, id: PaneId) bool {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        return self.findKnown(id) != null;
    }

    /// Caller must hold the mutex.
    fn findKnown(self: *Manager, id: PaneId) ?usize {
        for (self.known.items, 0..) |known, i| {
            if (known.raw == id.raw) return i;
        }
        return null;
    }

    /// Caller must hold the mutex.
    fn forget(self: *Manager, id: PaneId) void {
        if (self.findKnown(id)) |i| _ = self.known.swapRemove(i);
    }
};

// ─────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────

const testing = std.testing;
const FakeHost = @import("fake_host.zig").FakeHost;

fn testIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

test "create: registers the pane and reports the handle" {
    var fake = FakeHost.init(testing.allocator);
    defer fake.deinit();
    var manager = Manager.init(testing.allocator, fake.host());
    defer manager.deinit(testIo());
    const io = testIo();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const handle = try manager.create(arena.allocator(), io, .{
        .dir = .right,
        .cwd = "/tmp",
        .title = "build",
        .focus = true,
    });

    try testing.expectEqual(@as(u64, 1), handle.id.raw);
    try testing.expectEqualStrings("build", handle.title.?);
    try testing.expectEqual(@as(?u16, 80), handle.cols);
    try testing.expectEqual(@as(?bool, true), handle.focused);
    try testing.expect(manager.isKnown(io, handle.id));
    try testing.expectEqual(@as(usize, 1), fake.create_calls);
}

test "create: publishes pane_created when a broker is attached" {
    var fake = FakeHost.init(testing.allocator);
    defer fake.deinit();
    var broker = events.Broker.init(testing.allocator);
    defer broker.deinit(testIo());

    var manager = Manager.init(testing.allocator, fake.host());
    defer manager.deinit(testIo());
    manager.setEventBroker(&broker);

    const io = testIo();
    const sub = try broker.subscribe(io, protocol.EventKind.maskAll());

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    _ = try manager.create(arena.allocator(), io, .{ .title = "zsh" });

    var out: [4]events.Event = undefined;
    const drained = broker.drain(io, sub, &out).?;
    try testing.expectEqual(@as(usize, 1), drained.events);
    try testing.expectEqual(protocol.EventKind.pane_created, out[0].kind);
    try testing.expectEqual(@as(u64, 1), out[0].pane_id.?.raw);
    try testing.expectEqualStrings("zsh", out[0].payload.pane_created.title.slice());
}

test "create: host refusal surfaces as Unsupported and creates nothing" {
    var fake = FakeHost.init(testing.allocator);
    defer fake.deinit();
    fake.refuse_create = true;

    var manager = Manager.init(testing.allocator, fake.host());
    defer manager.deinit(testIo());

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectError(
        error.Unsupported,
        manager.create(arena.allocator(), testIo(), .{}),
    );
    try testing.expectEqual(@as(usize, 0), manager.known.items.len);
}

test "create: respects the manager pane ceiling" {
    var fake = FakeHost.init(testing.allocator);
    defer fake.deinit();

    var manager = Manager.init(testing.allocator, fake.host());
    defer manager.deinit(testIo());
    manager.max_panes = 2;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = testIo();

    _ = try manager.create(a, io, .{});
    _ = try manager.create(a, io, .{});
    try testing.expectError(error.TooManyPanes, manager.create(a, io, .{}));
    try testing.expectEqual(@as(usize, 2), fake.panes.items.len);
}

test "create: host-level pane ceiling is reported, not swallowed" {
    var fake = FakeHost.init(testing.allocator);
    defer fake.deinit();
    fake.max_panes = 1;

    var manager = Manager.init(testing.allocator, fake.host());
    defer manager.deinit(testIo());

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = testIo();

    _ = try manager.create(a, io, .{});
    try testing.expectError(error.TooManyPanes, manager.create(a, io, .{}));
    try testing.expectEqual(@as(usize, 1), manager.known.items.len);
}

test "close: removes from the registry and publishes pane_closed" {
    var fake = FakeHost.init(testing.allocator);
    defer fake.deinit();
    var broker = events.Broker.init(testing.allocator);
    defer broker.deinit(testIo());

    var manager = Manager.init(testing.allocator, fake.host());
    defer manager.deinit(testIo());
    manager.setEventBroker(&broker);

    const io = testIo();
    const sub = try broker.subscribe(io, protocol.EventKind.maskAll());

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const handle = try manager.create(arena.allocator(), io, .{});

    try manager.close(io, handle.id);
    try testing.expect(!manager.isKnown(io, handle.id));
    try testing.expectEqual(@as(usize, 1), fake.close_calls);

    var out: [4]events.Event = undefined;
    const drained = broker.drain(io, sub, &out).?;
    try testing.expectEqual(@as(usize, 2), drained.events);
    try testing.expectEqual(protocol.EventKind.pane_closed, out[1].kind);
    try testing.expectEqual(events.CloseReason.requested, out[1].payload.pane_closed.reason);
}

test "close: unknown pane is PaneNotFound" {
    var fake = FakeHost.init(testing.allocator);
    defer fake.deinit();
    var manager = Manager.init(testing.allocator, fake.host());
    defer manager.deinit(testIo());
    try testing.expectError(error.PaneNotFound, manager.close(testIo(), PaneId.init(99)));
}

test "create failure rolls the pane back out of the runtime" {
    // The rollback path is exercised by making registration fail: the manager's
    // `known` list is left at its ceiling so create fails *before* the host is
    // touched, and the host must not have grown.
    var fake = FakeHost.init(testing.allocator);
    defer fake.deinit();
    var manager = Manager.init(testing.allocator, fake.host());
    defer manager.deinit(testIo());
    manager.max_panes = 1;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = testIo();

    const first = try manager.create(a, io, .{});
    try testing.expectError(error.TooManyPanes, manager.create(a, io, .{}));
    try testing.expectEqual(@as(usize, 1), fake.panes.items.len);
    try testing.expect(fake.find(first.id) != null);
}

test "focus: delegates to the host and keeps a single focused pane" {
    var fake = FakeHost.init(testing.allocator);
    defer fake.deinit();
    var manager = Manager.init(testing.allocator, fake.host());
    defer manager.deinit(testIo());

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = testIo();

    const one = try manager.create(a, io, .{ .focus = true });
    const two = try manager.create(a, io, .{ .focus = true });
    try manager.focus(io, one.id);

    try testing.expect(fake.find(one.id).?.focused);
    try testing.expect(!fake.find(two.id).?.focused);
    try testing.expectError(error.PaneNotFound, manager.focus(io, PaneId.init(1234)));
}

test "list: uses the host when it can enumerate" {
    var fake = FakeHost.init(testing.allocator);
    defer fake.deinit();
    var manager = Manager.init(testing.allocator, fake.host());
    defer manager.deinit(testIo());

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = testIo();

    _ = try manager.create(a, io, .{ .title = "one", .cwd = "/tmp" });
    _ = try manager.create(a, io, .{ .title = "two" });

    var out: std.ArrayListUnmanaged(PaneInfo) = .empty;
    defer out.deinit(testing.allocator);
    try manager.list(a, io, &out);

    try testing.expectEqual(@as(usize, 2), out.items.len);
    try testing.expectEqualStrings("one", out.items[0].title.?);
    try testing.expectEqualStrings("/tmp", out.items[0].cwd.?);
    try testing.expectEqualStrings("two", out.items[1].title.?);
    try testing.expectEqual(@as(?[]const u8, null), out.items[1].cwd);
}

test "list: falls back to the registry with nulls when the host cannot list" {
    var fake = FakeHost.init(testing.allocator);
    defer fake.deinit();
    var host = fake.host();
    host.vtable = &.{
        .create = host.vtable.create,
        .close = host.vtable.close,
        .focus = host.vtable.focus,
        .list = null,
        .write = host.vtable.write,
        .snapshot = host.vtable.snapshot,
        .search = host.vtable.search,
        .resize = host.vtable.resize,
        .equalize = host.vtable.equalize,
        .zoom = host.vtable.zoom,
    };

    var manager = Manager.init(testing.allocator, host);
    defer manager.deinit(testIo());

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = testIo();

    const created = try manager.create(a, io, .{});
    var out: std.ArrayListUnmanaged(PaneInfo) = .empty;
    defer out.deinit(testing.allocator);
    try manager.list(a, io, &out);

    try testing.expectEqual(@as(usize, 1), out.items.len);
    try testing.expectEqual(created.id, out.items[0].id);
    try testing.expectEqual(@as(?[]const u8, null), out.items[0].title);
    try testing.expectEqual(@as(?u16, null), out.items[0].cols);
}

test "json: pane handle payload" {
    const handle: PaneHandle = .{
        .id = PaneId.init(3),
        .pid = 4711,
        .title = "zsh",
        .cols = 120,
        .rows = 40,
        .focused = true,
    };
    var buf: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try handle.writeJson(&w);
    try testing.expectEqualStrings(
        "{\"pane_id\":\"p-3\",\"pid\":4711,\"title\":\"zsh\",\"cols\":120,\"rows\":40,\"focused\":true}",
        w.buffered(),
    );
}

test "json: pane handle with unknown fields is null" {
    const handle: PaneHandle = .{ .id = PaneId.init(1) };
    var buf: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try handle.writeJson(&w);
    try testing.expectEqualStrings(
        "{\"pane_id\":\"p-1\",\"pid\":null,\"title\":null,\"cols\":null,\"rows\":null,\"focused\":null}",
        w.buffered(),
    );
}

test "json: pane list payload" {
    const panes = [_]PaneInfo{
        .{ .id = PaneId.init(3), .title = "bash", .pid = 12345, .focused = true, .exited = false },
        .{ .id = PaneId.init(7), .title = "vim", .pid = 12389, .focused = false, .exited = false },
    };
    var buf: [1024]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try writePaneListJson(testing.allocator, &panes, &w);
    try testing.expectEqualStrings(
        "[{\"pane_id\":\"p-3\",\"title\":\"bash\",\"pid\":12345,\"cwd\":null,\"cols\":null," ++
            "\"rows\":null,\"focused\":true,\"exited\":false}," ++
            "{\"pane_id\":\"p-7\",\"title\":\"vim\",\"pid\":12389,\"cwd\":null,\"cols\":null," ++
            "\"rows\":null,\"focused\":false,\"exited\":false}]",
        w.buffered(),
    );
}

test "json: search match payload" {
    const match: SearchMatch = .{ .row = -3, .col = 8, .len = 5, .text = "error" };
    var buf: [128]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try match.writeJson(&w);
    try testing.expectEqualStrings(
        "{\"row\":-3,\"col\":8,\"len\":5,\"text\":\"error\"}",
        w.buffered(),
    );
}

test "write: injects VT and updates cursor and size" {
    var fake = FakeHost.init(testing.allocator);
    defer fake.deinit();
    var manager = Manager.init(testing.allocator, fake.host());
    defer manager.deinit(testIo());
    const io = testIo();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const handle = try manager.create(a, io, .{});

    // Move to row 5, column 10 (1-based), then print two characters.
    const written = try manager.write(io, handle.id, "\x1b[5;10Hok");
    try testing.expectEqual(@as(usize, 9), written);

    const snap = try manager.snapshot(a, io, handle.id);
    try testing.expectEqual(@as(u32, 4), snap.cursor.row);
    try testing.expectEqual(@as(u32, 11), snap.cursor.col);
    try testing.expectEqual(@as(u16, 80), snap.size.cols);
    try testing.expectEqual(@as(u16, 24), snap.size.rows);
    try testing.expectEqual(@as(?u32, 24), snap.viewport_rows);
}

test "write: OSC 0 sets the queryable title" {
    var fake = FakeHost.init(testing.allocator);
    defer fake.deinit();
    var manager = Manager.init(testing.allocator, fake.host());
    defer manager.deinit(testIo());
    const io = testIo();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const handle = try manager.create(a, io, .{ .title = "zsh" });
    _ = try manager.write(io, handle.id, "\x1b]0;~/projects/khostty\x07");

    const snap = try manager.snapshot(a, io, handle.id);
    try testing.expectEqualStrings("~/projects/khostty", snap.title.?);
}

test "write: CR/LF and modes are parsed, not echoed" {
    var fake = FakeHost.init(testing.allocator);
    defer fake.deinit();
    var manager = Manager.init(testing.allocator, fake.host());
    defer manager.deinit(testIo());
    const io = testIo();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const handle = try manager.create(a, io, .{});
    _ = try manager.write(io, handle.id, "ab\r\ncd");
    var snap = try manager.snapshot(a, io, handle.id);
    try testing.expectEqual(@as(u32, 1), snap.cursor.row);
    try testing.expectEqual(@as(u32, 2), snap.cursor.col);

    _ = try manager.write(io, handle.id, "\x1b[?1049h");
    snap = try manager.snapshot(a, io, handle.id);
    try testing.expectEqual(@as(?bool, true), snap.alt_screen);

    _ = try manager.write(io, handle.id, "\x1b[?1049l");
    snap = try manager.snapshot(a, io, handle.id);
    try testing.expectEqual(@as(?bool, false), snap.alt_screen);
}

test "write: unknown pane is PaneNotFound" {
    var fake = FakeHost.init(testing.allocator);
    defer fake.deinit();
    var manager = Manager.init(testing.allocator, fake.host());
    defer manager.deinit(testIo());
    try testing.expectError(
        error.PaneNotFound,
        manager.write(testIo(), PaneId.init(404), "hello"),
    );
}

test "snapshot: a pane the host has lost is reported as closed, not missing" {
    var fake = FakeHost.init(testing.allocator);
    defer fake.deinit();
    var manager = Manager.init(testing.allocator, fake.host());
    defer manager.deinit(testIo());
    const io = testIo();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const handle = try manager.create(a, io, .{});

    // The child exits and the runtime drops the pane without IPC knowing.
    const p = fake.find(handle.id).?;
    p.exited = true;
    p.exit_code = 0;

    const snap = try manager.snapshot(a, io, handle.id);
    try testing.expectEqual(@as(?bool, true), snap.exited);
    try testing.expectEqual(@as(?i32, 0), snap.exit_code);

    fake.dropPane(handle.id);
    try testing.expectError(error.PaneClosed, manager.snapshot(a, io, handle.id));
}

test "snapshot: never-seen pane is PaneNotFound" {
    var fake = FakeHost.init(testing.allocator);
    defer fake.deinit();
    var manager = Manager.init(testing.allocator, fake.host());
    defer manager.deinit(testIo());

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(
        error.PaneNotFound,
        manager.snapshot(arena.allocator(), testIo(), PaneId.init(77)),
    );
}

test "json: write result payload" {
    const result: WriteResult = .{ .written = 9 };
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try result.writeJson(&w);
    try testing.expectEqualStrings("{\"written\":9}", w.buffered());
}
