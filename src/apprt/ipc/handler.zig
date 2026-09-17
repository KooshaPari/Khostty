//! Command dispatch for the agent IPC surface.
//!
//! One `Handler` per connection. It turns a parsed `protocol.Request` into a
//! `protocol.Response`, and it is the only place that knows the mapping from
//! wire commands onto `pane.Manager` / `events.Broker` / `auth.Auth` calls.
//!
//! Two rules keep the surface trustworthy:
//!
//!   * Authorization happens before any host call. Only `ping` is open, and a
//!     missing or wrong token is `unauthorized` — never a silent downgrade.
//!   * Protocol-level problems (missing `pane_id`, missing `data`, empty search
//!     query, a runtime that cannot split) come back as structured errors with
//!     the codes in `protocol.md`; nothing is swallowed and nothing panics.
//!
//! `dispatch` always produces a response, including when rendering fails, so a
//! connection loop can write something to the client on every frame.
//!
//!     zig test src/apprt/ipc/handler.zig

const std = @import("std");
const Allocator = std.mem.Allocator;

const protocol = @import("protocol.zig");
const events = @import("events.zig");
const pane = @import("pane.zig");
const state = @import("state.zig");
const auth = @import("auth.zig");

const Command = protocol.Command;
const ErrorCode = protocol.ErrorCode;
const PaneId = protocol.PaneId;
const Response = protocol.Response;
const EventKind = protocol.EventKind;

/// Per-connection command handler.
pub const Handler = struct {
    gpa: Allocator,
    manager: *pane.Manager,
    broker: *events.Broker,
    authenticator: *const auth.Auth,
    /// Advertised by `ping`; null when the host cannot determine it.
    server_pid: ?u32 = null,
    /// Active event subscription for this connection, at most one.
    subscription: ?u64 = null,

    pub fn init(
        gpa: Allocator,
        manager: *pane.Manager,
        broker: *events.Broker,
        authenticator: *const auth.Auth,
    ) Handler {
        return .{
            .gpa = gpa,
            .manager = manager,
            .broker = broker,
            .authenticator = authenticator,
        };
    }

    /// Release per-connection state (drops any event subscription).
    pub fn deinit(self: *Handler, io: std.Io) void {
        if (self.subscription) |id| _ = self.broker.unsubscribe(io, id);
        self.subscription = null;
    }

    /// Dispatch one request. Never fails: rendering problems become `internal`
    /// responses so the caller always has something to write.
    pub fn dispatch(
        self: *Handler,
        arena: Allocator,
        io: std.Io,
        req: protocol.Request,
    ) Response {
        return self.handle(arena, io, req) catch |err| switch (err) {
            error.OutOfMemory => Response.failure(req.id, .internal, "out of memory"),
            error.WriteFailed => Response.failure(
                req.id,
                .internal,
                "failed to render the response payload",
            ),
        };
    }

    fn handle(
        self: *Handler,
        arena: Allocator,
        io: std.Io,
        req: protocol.Request,
    ) protocol.EncodeError!Response {
        if (req.cmd != .ping and !self.authenticator.verify(req.auth)) {
            return Response.failure(req.id, .unauthorized, "missing or invalid auth token");
        }

        if (req.cmd.requiresPane() and req.targetPane() == null) {
            return Response.failure(req.id, .bad_request, "missing \"pane_id\"");
        }

        return switch (req.cmd) {
            .ping => self.ping(arena, req),
            .pane_create => self.paneCreate(arena, io, req),
            .pane_close => self.paneClose(arena, io, req),
            .pane_focus => self.paneFocus(arena, io, req),
            .pane_list => self.paneList(arena, io, req),
            .pane_write => self.paneWrite(arena, io, req),
            .pane_state => self.paneState(arena, io, req),
            .pane_search => self.paneSearch(arena, io, req),
            .pane_resize_split => self.paneResizeSplit(arena, io, req),
            .pane_equalize => self.paneEqualize(arena, io, req),
            .pane_zoom => self.paneZoom(arena, io, req),
            .events_subscribe => self.eventsSubscribe(arena, io, req),
            .events_unsubscribe => self.eventsUnsubscribe(arena, io, req),
        };
    }

    // ── Commands ──

    fn ping(
        self: *Handler,
        arena: Allocator,
        req: protocol.Request,
    ) protocol.EncodeError!Response {
        var buf: std.Io.Writer.Allocating = .init(arena);
        var o = try protocol.Obj.init(&buf.writer);
        try o.string("server", "khostty");
        try o.uint("version", protocol.version);
        try o.optUint("pid", if (self.server_pid) |pid| pid else null);
        try o.close('}');
        return Response.okJson(req.id, try buf.toOwnedSlice());
    }

    fn paneCreate(
        self: *Handler,
        arena: Allocator,
        io: std.Io,
        req: protocol.Request,
    ) protocol.EncodeError!Response {
        const create: pane.CreateRequest = .{
            .dir = req.opts.effectiveDirection(),
            .parent = req.targetPane(),
            .cwd = req.opts.cwd,
            .title = req.opts.title,
            .focus = req.opts.focus orelse true,
            .command = req.opts.command,
        };

        const created = self.manager.create(arena, io, create) catch |err|
            return hostFailure(req.id, err);

        var buf: std.Io.Writer.Allocating = .init(arena);
        try created.writeJson(&buf.writer);
        return Response.okJson(req.id, try buf.toOwnedSlice());
    }

    fn paneClose(
        self: *Handler,
        arena: Allocator,
        io: std.Io,
        req: protocol.Request,
    ) protocol.EncodeError!Response {
        const id = req.targetPane().?;
        self.manager.close(io, id) catch |err| return hostFailure(req.id, err);

        var buf: std.Io.Writer.Allocating = .init(arena);
        var o = try protocol.Obj.init(&buf.writer);
        try o.boolean("closed", true);
        try o.paneId("pane_id", id);
        try o.close('}');
        return Response.okJson(req.id, try buf.toOwnedSlice());
    }

    fn paneFocus(
        self: *Handler,
        arena: Allocator,
        io: std.Io,
        req: protocol.Request,
    ) protocol.EncodeError!Response {
        const id = req.targetPane().?;
        self.manager.focus(io, id) catch |err| return hostFailure(req.id, err);

        var buf: std.Io.Writer.Allocating = .init(arena);
        var o = try protocol.Obj.init(&buf.writer);
        try o.boolean("focused", true);
        try o.paneId("pane_id", id);
        try o.close('}');
        return Response.okJson(req.id, try buf.toOwnedSlice());
    }

    fn paneList(
        self: *Handler,
        arena: Allocator,
        io: std.Io,
        req: protocol.Request,
    ) protocol.EncodeError!Response {
        // Arena-owned: the response buffer and the list share the request
        // arena, so nothing here needs an explicit deinit.
        var list: std.ArrayListUnmanaged(pane.PaneInfo) = .empty;
        self.manager.list(arena, io, &list) catch |err| return hostFailure(req.id, err);

        var buf: std.Io.Writer.Allocating = .init(arena);
        try pane.writePaneListJson(self.gpa, list.items, &buf.writer);
        return Response.okJson(req.id, try buf.toOwnedSlice());
    }

    fn paneWrite(
        self: *Handler,
        arena: Allocator,
        io: std.Io,
        req: protocol.Request,
    ) protocol.EncodeError!Response {
        const data = req.data orelse
            return Response.failure(req.id, .bad_request, "missing \"data\"");
        const id = req.targetPane().?;

        const written = self.manager.write(io, id, data) catch |err|
            return hostFailure(req.id, err);

        var buf: std.Io.Writer.Allocating = .init(arena);
        try (pane.WriteResult{ .written = written }).writeJson(&buf.writer);
        return Response.okJson(req.id, try buf.toOwnedSlice());
    }

    fn paneState(
        self: *Handler,
        arena: Allocator,
        io: std.Io,
        req: protocol.Request,
    ) protocol.EncodeError!Response {
        const id = req.targetPane().?;
        const snapshot = self.manager.snapshot(arena, io, id) catch |err|
            return hostFailure(req.id, err);

        var buf: std.Io.Writer.Allocating = .init(arena);
        try snapshot.writeJson(&buf.writer);
        return Response.okJson(req.id, try buf.toOwnedSlice());
    }

    fn paneSearch(
        self: *Handler,
        arena: Allocator,
        io: std.Io,
        req: protocol.Request,
    ) protocol.EncodeError!Response {
        const query = req.query orelse
            return Response.failure(req.id, .bad_request, "missing \"query\"");
        if (query.len == 0) {
            return Response.failure(req.id, .bad_request, "\"query\" must not be empty");
        }
        const id = req.targetPane().?;

        var matches: std.ArrayListUnmanaged(pane.SearchMatch) = .empty;
        const result = self.manager.search(
            arena,
            io,
            id,
            query,
            req.opts.limit orelse pane.default_search_limit,
            &matches,
        ) catch |err| return hostFailure(req.id, err);

        var buf: std.Io.Writer.Allocating = .init(arena);
        try result.writeJson(self.gpa, &buf.writer);
        return Response.okJson(req.id, try buf.toOwnedSlice());
    }

    fn paneResizeSplit(
        self: *Handler,
        arena: Allocator,
        io: std.Io,
        req: protocol.Request,
    ) protocol.EncodeError!Response {
        const id = req.targetPane().?;
        const dir = req.opts.dir orelse req.opts.effectiveDirection();
        const amount = req.opts.amount orelse 1;

        self.manager.resizeSplit(io, id, dir, amount) catch |err|
            return hostFailure(req.id, err);

        var buf: std.Io.Writer.Allocating = .init(arena);
        var o = try protocol.Obj.init(&buf.writer);
        try o.boolean("resized", true);
        try o.close('}');
        return Response.okJson(req.id, try buf.toOwnedSlice());
    }

    fn paneEqualize(
        self: *Handler,
        arena: Allocator,
        io: std.Io,
        req: protocol.Request,
    ) protocol.EncodeError!Response {
        self.manager.equalize(io) catch |err| return hostFailure(req.id, err);

        var buf: std.Io.Writer.Allocating = .init(arena);
        var o = try protocol.Obj.init(&buf.writer);
        try o.boolean("equalized", true);
        try o.close('}');
        return Response.okJson(req.id, try buf.toOwnedSlice());
    }

    fn paneZoom(
        self: *Handler,
        arena: Allocator,
        io: std.Io,
        req: protocol.Request,
    ) protocol.EncodeError!Response {
        const id = req.targetPane().?;
        self.manager.zoom(io, id) catch |err| return hostFailure(req.id, err);

        var buf: std.Io.Writer.Allocating = .init(arena);
        var o = try protocol.Obj.init(&buf.writer);
        try o.boolean("zoomed", true);
        try o.close('}');
        return Response.okJson(req.id, try buf.toOwnedSlice());
    }

    fn eventsSubscribe(
        self: *Handler,
        arena: Allocator,
        io: std.Io,
        req: protocol.Request,
    ) protocol.EncodeError!Response {
        var mask: protocol.EventMask = .initEmpty();
        for (req.opts.events) |kind| mask.insert(kind);

        // At most one subscription per connection: re-subscribing replaces.
        if (self.subscription) |previous| _ = self.broker.unsubscribe(io, previous);

        const id = self.broker.subscribe(io, mask) catch
            return Response.failure(req.id, .internal, "failed to register the subscription");
        self.subscription = id;

        const effective = self.broker.maskOf(io, id) orelse mask;

        var buf: std.Io.Writer.Allocating = .init(arena);
        var o = try protocol.Obj.init(&buf.writer);
        try o.boolean("subscribed", true);
        var arr = try o.openArr("events");
        for (EventKind.all) |kind| {
            if (!effective.contains(kind)) continue;
            try arr.item(kind.name());
        }
        try arr.close(']');
        try o.close('}');
        return Response.okJson(req.id, try buf.toOwnedSlice());
    }

    fn eventsUnsubscribe(
        self: *Handler,
        arena: Allocator,
        io: std.Io,
        req: protocol.Request,
    ) protocol.EncodeError!Response {
        const id = self.subscription orelse
            return Response.failure(req.id, .not_subscribed, "no active event subscription");
        if (!self.broker.unsubscribe(io, id)) {
            self.subscription = null;
            return Response.failure(req.id, .not_subscribed, "no active event subscription");
        }
        self.subscription = null;

        var buf: std.Io.Writer.Allocating = .init(arena);
        var o = try protocol.Obj.init(&buf.writer);
        try o.boolean("unsubscribed", true);
        try o.close('}');
        return Response.okJson(req.id, try buf.toOwnedSlice());
    }

    /// Collect pending events for this connection into `out`, oldest first.
    /// Reports dropped events before the surviving ones. Returns the number of
    /// events written; 0 means there was nothing to send.
    pub fn pollEvents(self: *Handler, io: std.Io, out: []events.Event) usize {
        if (out.len == 0) return 0;
        const id = self.subscription orelse return 0;

        const dropped = self.broker.takeDropped(io, id) orelse {
            // The broker no longer knows us (it was reset or we were removed).
            self.subscription = null;
            return 0;
        };

        var count: usize = 0;
        if (dropped > 0) {
            out[0] = events.Event.eventsDropped(dropped);
            count = 1;
        }

        const drained = self.broker.drain(io, id, out[count..]) orelse {
            self.subscription = null;
            return count;
        };
        return count + drained.events;
    }
};

/// Map a host failure onto the protocol error table.
fn hostFailure(id: ?u64, err: pane.HostError) Response {
    return switch (err) {
        error.PaneNotFound => Response.failure(id, .pane_not_found, "no live pane with that id"),
        error.PaneClosed => Response.failure(
            id,
            .pane_not_found_after_close,
            "the pane exited before the operation completed",
        ),
        error.TooManyPanes => Response.failure(
            id,
            .too_many_panes,
            "the pane ceiling for this instance has been reached",
        ),
        error.Unsupported => Response.failure(
            id,
            .host_unsupported,
            "the app runtime cannot service this command",
        ),
        error.OutOfMemory => Response.failure(id, .internal, "out of memory"),
        error.Internal => Response.failure(id, .internal, "the app runtime reported an error"),
    };
}

// ─────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────

const testing = std.testing;
const FakeHost = @import("fake_host.zig").FakeHost;

const token = "test-token";

/// One manager/broker/auth/handler set plus the per-request arena that the
/// server would own. `reset` frees previous per-request allocations the way a
/// connection loop does between frames; responses are only valid until then.
const Fixture = struct {
    fake: FakeHost,
    broker: events.Broker,
    authenticator: auth.Auth,
    manager: pane.Manager,
    handler: Handler,
    arena: std.heap.ArenaAllocator,

    fn init() !*Fixture {
        const self = try testing.allocator.create(Fixture);
        errdefer testing.allocator.destroy(self);

        self.fake = FakeHost.init(testing.allocator);
        self.broker = events.Broker.init(testing.allocator);
        self.authenticator = try auth.Auth.init(testing.allocator, token);
        self.manager = pane.Manager.init(testing.allocator, self.fake.host());
        self.manager.setEventBroker(&self.broker);
        self.handler = Handler.init(
            testing.allocator,
            &self.manager,
            &self.broker,
            &self.authenticator,
        );
        self.arena = std.heap.ArenaAllocator.init(testing.allocator);
        return self;
    }

    fn deinit(self: *Fixture) void {
        const io = testIo();
        self.handler.deinit(io);
        self.arena.deinit();
        self.manager.deinit(io);
        self.broker.deinit(io);
        self.authenticator.deinit();
        self.fake.deinit();
        testing.allocator.destroy(self);
    }

    /// Free the previous dispatch's allocations.
    fn reset(self: *Fixture) void {
        _ = self.arena.reset(.retain_capacity);
    }

    fn call(self: *Fixture, request_text: []const u8) !Response {
        var parsed = try protocol.parse(testing.allocator, request_text);
        defer parsed.deinit();
        switch (parsed.result) {
            .ok => |req| return self.handler.dispatch(self.arena.allocator(), testIo(), req),
            .err => |f| {
                std.debug.print(
                    "unexpected parse failure: {s} ({s})\n",
                    .{ f.code.name(), f.message },
                );
                return error.TestUnexpectedResult;
            },
        }
    }

    /// Dispatch a command with a valid token and correlation id.
    fn authed(self: *Fixture, cmd: []const u8, suffix: []const u8) !Response {
        const request_text = try std.fmt.allocPrint(
            testing.allocator,
            "{{\"id\":1,\"auth\":\"{s}\",\"cmd\":\"{s}\"{s}}}",
            .{ token, cmd, suffix },
        );
        defer testing.allocator.free(request_text);
        return self.call(request_text);
    }

    /// Assert success and parse the `data` payload. The caller owns the
    /// returned tree and must `deinit` it before calling `reset`.
    fn data(self: *Fixture, resp: Response) !std.json.Parsed(std.json.Value) {
        if (!resp.ok) {
            std.debug.print(
                "expected ok, got error {s}: {s}\n",
                .{ resp.err.?.code.name(), resp.err.?.message },
            );
            return error.TestUnexpectedResult;
        }
        _ = self;
        return std.json.parseFromSlice(
            std.json.Value,
            testing.allocator,
            resp.json orelse return error.TestUnexpectedResult,
            .{},
        );
    }

    fn expectCode(self: *Fixture, resp: Response, expected: ErrorCode) !void {
        _ = self;
        if (resp.ok) {
            std.debug.print("expected {s}, got ok\n", .{expected.name()});
            return error.TestUnexpectedResult;
        }
        try testing.expectEqual(expected, resp.err.?.code);
    }
};

fn testIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

test "ping: works without a token and reports null pid when unknown" {
    var f = try Fixture.init();
    defer f.deinit();

    const resp = try f.call("{\"id\":1,\"cmd\":\"ping\"}");
    try testing.expectEqual(@as(?u64, 1), resp.id);
    const payload = try f.data(resp);
    defer payload.deinit();

    try testing.expectEqualStrings("khostty", payload.value.object.get("server").?.string);
    try testing.expectEqual(@as(i64, 1), payload.value.object.get("version").?.integer);
    try testing.expectEqual(std.json.Value.null, payload.value.object.get("pid").?);
}

test "ping: reports the pid when the host knows it" {
    var f = try Fixture.init();
    defer f.deinit();
    f.handler.server_pid = 4711;

    const payload = try f.data(try f.call("{\"cmd\":\"ping\"}"));
    defer payload.deinit();
    try testing.expectEqual(@as(i64, 4711), payload.value.object.get("pid").?.integer);
}

test "auth: every non-ping command rejects a missing and a wrong token" {
    var f = try Fixture.init();
    defer f.deinit();

    const commands = [_]struct { cmd: []const u8, suffix: []const u8 }{
        .{ .cmd = "pane.create", .suffix = "" },
        .{ .cmd = "pane.list", .suffix = "" },
        .{ .cmd = "pane.close", .suffix = ",\"pane_id\":\"p-1\"" },
        .{ .cmd = "pane.focus", .suffix = ",\"pane_id\":\"p-1\"" },
        .{ .cmd = "pane.write", .suffix = ",\"pane_id\":\"p-1\",\"data\":\"x\"" },
        .{ .cmd = "pane.state", .suffix = ",\"pane_id\":\"p-1\"" },
        .{ .cmd = "pane.search", .suffix = ",\"pane_id\":\"p-1\",\"query\":\"x\"" },
        .{ .cmd = "pane.resize_split", .suffix = ",\"pane_id\":\"p-1\"" },
        .{ .cmd = "pane.equalize", .suffix = "" },
        .{ .cmd = "pane.zoom", .suffix = ",\"pane_id\":\"p-1\"" },
        .{ .cmd = "events.subscribe", .suffix = "" },
        .{ .cmd = "events.unsubscribe", .suffix = "" },
    };

    for (commands) |case| {
        // No auth field at all.
        const anonymous = try std.fmt.allocPrint(
            testing.allocator,
            "{{\"cmd\":\"{s}\"{s}}}",
            .{ case.cmd, case.suffix },
        );
        defer testing.allocator.free(anonymous);
        try f.expectCode(try f.call(anonymous), .unauthorized);
        f.reset();

        // Wrong token.
        const wrong = try std.fmt.allocPrint(
            testing.allocator,
            "{{\"auth\":\"nope\",\"cmd\":\"{s}\"{s}}}",
            .{ case.cmd, case.suffix },
        );
        defer testing.allocator.free(wrong);
        try f.expectCode(try f.call(wrong), .unauthorized);
        f.reset();
    }

    // Nothing above reached the host.
    try testing.expectEqual(@as(usize, 0), f.fake.create_calls);
    try testing.expectEqual(@as(usize, 0), f.broker.subscriberCount(testIo()));
}

test "pane.create: returns a handle and creates the pane" {
    var f = try Fixture.init();
    defer f.deinit();

    const payload = try f.data(try f.authed(
        "pane.create",
        ",\"opts\":{\"split\":\"vertical\",\"cwd\":\"/tmp\",\"title\":\"build\"}",
    ));
    defer payload.deinit();

    const obj = payload.value.object;
    try testing.expectEqualStrings("p-1", obj.get("pane_id").?.string);
    try testing.expectEqualStrings("build", obj.get("title").?.string);
    try testing.expectEqual(@as(i64, 80), obj.get("cols").?.integer);
    try testing.expectEqual(@as(i64, 24), obj.get("rows").?.integer);
    try testing.expectEqual(true, obj.get("focused").?.bool);
    try testing.expectEqual(@as(usize, 1), f.fake.create_calls);
}

test "pane.create: a runtime without split support is host_unsupported" {
    var f = try Fixture.init();
    defer f.deinit();
    f.fake.refuse_create = true;
    try f.expectCode(try f.authed("pane.create", ""), .host_unsupported);
}

test "pane.create: the pane ceiling is too_many_panes" {
    var f = try Fixture.init();
    defer f.deinit();
    f.manager.max_panes = 1;

    _ = try f.authed("pane.create", "");
    f.reset();
    try f.expectCode(try f.authed("pane.create", ""), .too_many_panes);
}

test "pane.list: returns every pane in creation order" {
    var f = try Fixture.init();
    defer f.deinit();

    _ = try f.authed("pane.create", ",\"opts\":{\"title\":\"one\"}");
    f.reset();
    _ = try f.authed("pane.create", ",\"opts\":{\"title\":\"two\"}");
    f.reset();

    const payload = try f.data(try f.authed("pane.list", ""));
    defer payload.deinit();

    const items = payload.value.array.items;
    try testing.expectEqual(@as(usize, 2), items.len);
    try testing.expectEqualStrings("p-1", items[0].object.get("pane_id").?.string);
    try testing.expectEqualStrings("one", items[0].object.get("title").?.string);
    try testing.expectEqualStrings("p-2", items[1].object.get("pane_id").?.string);
    try testing.expectEqualStrings("two", items[1].object.get("title").?.string);
}

test "pane.write then pane.state: injected VT is observable in the state" {
    var f = try Fixture.init();
    defer f.deinit();

    _ = try f.authed("pane.create", "");
    f.reset();

    const written = try f.data(try f.authed(
        "pane.write",
        ",\"pane_id\":\"p-1\",\"data\":\"\\u001b[3;5Hhi\\r\\n\\u001b]0;builder\\u0007\"",
    ));
    try testing.expect(written.value.object.get("written").?.integer > 0);
    written.deinit();
    f.reset();

    const payload = try f.data(try f.authed("pane.state", ",\"pane_id\":\"p-1\""));
    defer payload.deinit();

    const obj = payload.value.object;
    try testing.expectEqualStrings("builder", obj.get("title").?.string);
    // "hi" was printed on row 3 (1-based), then CR/LF moved to column 0 of the
    // next row: 0-based row 3, column 0.
    try testing.expectEqual(@as(i64, 3), obj.get("cursor").?.object.get("row").?.integer);
    try testing.expectEqual(@as(i64, 0), obj.get("cursor").?.object.get("col").?.integer);
    try testing.expectEqual(@as(i64, 80), obj.get("size").?.object.get("cols").?.integer);
    try testing.expectEqual(@as(i64, 24), obj.get("size").?.object.get("rows").?.integer);
    // Unknowable values stay null rather than being guessed.
    try testing.expectEqual(std.json.Value.null, obj.get("exit_code").?);
    try testing.expectEqual(std.json.Value.null, obj.get("scrollback_rows").?);
}

test "pane.write: missing data or missing pane_id is bad_request" {
    var f = try Fixture.init();
    defer f.deinit();

    _ = try f.authed("pane.create", "");
    f.reset();

    try f.expectCode(try f.authed("pane.write", ",\"pane_id\":\"p-1\""), .bad_request);
    f.reset();
    try f.expectCode(try f.authed("pane.write", ",\"data\":\"x\""), .bad_request);
}

test "pane.state: never-seen pane is pane_not_found, self-exited pane is after_close" {
    var f = try Fixture.init();
    defer f.deinit();

    _ = try f.authed("pane.create", "");
    f.reset();
    try f.expectCode(try f.authed("pane.state", ",\"pane_id\":\"p-99\""), .pane_not_found);
    f.reset();

    // The child exits and the runtime drops the surface without IPC being told.
    // The registry still remembers the pane, so the agent is told the pane
    // closed rather than that it never existed.
    f.fake.dropPane(PaneId.init(1));
    try f.expectCode(
        try f.authed("pane.state", ",\"pane_id\":\"p-1\""),
        .pane_not_found_after_close,
    );
}

test "pane.close: a pane closed over IPC is simply gone" {
    var f = try Fixture.init();
    defer f.deinit();

    _ = try f.authed("pane.create", "");
    f.reset();
    _ = try f.authed("pane.close", ",\"pane_id\":\"p-1\"");
    f.reset();

    // The agent closed it, so there is nothing to distinguish from "no such
    // pane": after_close is reserved for panes that vanished on their own.
    try f.expectCode(try f.authed("pane.state", ",\"pane_id\":\"p-1\""), .pane_not_found);
}

test "pane.close and pane.focus: payloads and effects" {
    var f = try Fixture.init();
    defer f.deinit();

    _ = try f.authed("pane.create", "");
    f.reset();

    const focused = try f.data(try f.authed("pane.focus", ",\"pane_id\":\"p-1\""));
    try testing.expectEqual(true, focused.value.object.get("focused").?.bool);
    try testing.expectEqualStrings("p-1", focused.value.object.get("pane_id").?.string);
    focused.deinit();
    f.reset();

    const closed = try f.data(try f.authed("pane.close", ",\"pane_id\":\"p-1\""));
    try testing.expectEqual(true, closed.value.object.get("closed").?.bool);
    closed.deinit();
    f.reset();

    try f.expectCode(try f.authed("pane.close", ",\"pane_id\":\"p-1\""), .pane_not_found);
}

test "pane.search: matches, positions, and true truncation" {
    var f = try Fixture.init();
    defer f.deinit();

    _ = try f.authed("pane.create", "");
    f.reset();
    _ = try f.authed(
        "pane.write",
        ",\"pane_id\":\"p-1\",\"data\":\"err\\r\\nok\\r\\nerr\\r\\nerr\"",
    );
    f.reset();

    const all = try f.data(try f.authed(
        "pane.search",
        ",\"pane_id\":\"p-1\",\"query\":\"err\"",
    ));
    defer all.deinit();
    const all_matches = all.value.object.get("matches").?.array.items;
    try testing.expectEqual(@as(usize, 3), all_matches.len);
    try testing.expectEqual(false, all.value.object.get("truncated").?.bool);
    try testing.expectEqual(@as(i64, 0), all_matches[0].object.get("row").?.integer);
    try testing.expectEqual(@as(i64, 2), all_matches[1].object.get("row").?.integer);
    try testing.expectEqualStrings("err", all_matches[0].object.get("text").?.string);
    f.reset();

    const limited = try f.data(try f.authed(
        "pane.search",
        ",\"pane_id\":\"p-1\",\"query\":\"err\",\"opts\":{\"limit\":1}",
    ));
    defer limited.deinit();
    try testing.expectEqual(@as(i64, 1), limited.value.object.get("total").?.integer);
    try testing.expectEqual(true, limited.value.object.get("truncated").?.bool);
}

test "pane.search: missing or empty query is bad_request" {
    var f = try Fixture.init();
    defer f.deinit();
    _ = try f.authed("pane.create", "");
    f.reset();

    try f.expectCode(try f.authed("pane.search", ",\"pane_id\":\"p-1\""), .bad_request);
    f.reset();
    try f.expectCode(
        try f.authed("pane.search", ",\"pane_id\":\"p-1\",\"query\":\"\""),
        .bad_request,
    );
}

test "pane.resize_split, pane.equalize, pane.zoom: payloads and effects" {
    var f = try Fixture.init();
    defer f.deinit();

    _ = try f.authed("pane.create", "");
    f.reset();

    const resized = try f.data(try f.authed(
        "pane.resize_split",
        ",\"pane_id\":\"p-1\",\"opts\":{\"dir\":\"left\",\"amount\":5}",
    ));
    try testing.expectEqual(true, resized.value.object.get("resized").?.bool);
    resized.deinit();
    try testing.expectEqual(@as(u16, 75), f.fake.find(PaneId.init(1)).?.cols);
    f.reset();

    const equalized = try f.data(try f.authed("pane.equalize", ""));
    try testing.expectEqual(true, equalized.value.object.get("equalized").?.bool);
    equalized.deinit();
    f.reset();

    const zoomed = try f.data(try f.authed("pane.zoom", ",\"pane_id\":\"p-1\""));
    try testing.expectEqual(true, zoomed.value.object.get("zoomed").?.bool);
    zoomed.deinit();
    try testing.expect(f.fake.find(PaneId.init(1)).?.zoomed);
    f.reset();

    try f.expectCode(try f.authed("pane.zoom", ""), .bad_request);
}

test "pane.resize_split: an unknown pane is pane_not_found" {
    var f = try Fixture.init();
    defer f.deinit();
    try f.expectCode(
        try f.authed("pane.resize_split", ",\"pane_id\":\"p-42\""),
        .pane_not_found,
    );
}

test "events.subscribe then unsubscribe" {
    var f = try Fixture.init();
    defer f.deinit();

    const sub = try f.data(try f.authed(
        "events.subscribe",
        ",\"opts\":{\"events\":[\"title_change\",\"bell\"]}",
    ));
    try testing.expectEqual(true, sub.value.object.get("subscribed").?.bool);
    const kinds = sub.value.object.get("events").?.array.items;
    try testing.expectEqual(@as(usize, 2), kinds.len);
    try testing.expectEqualStrings("title_change", kinds[0].string);
    try testing.expectEqualStrings("bell", kinds[1].string);
    sub.deinit();
    try testing.expectEqual(@as(usize, 1), f.broker.subscriberCount(testIo()));
    f.reset();

    const unsub = try f.data(try f.authed("events.unsubscribe", ""));
    try testing.expectEqual(true, unsub.value.object.get("unsubscribed").?.bool);
    unsub.deinit();
    try testing.expectEqual(@as(usize, 0), f.broker.subscriberCount(testIo()));
    f.reset();

    try f.expectCode(try f.authed("events.unsubscribe", ""), .not_subscribed);
}

test "events.subscribe: an empty list means every subscribable kind" {
    var f = try Fixture.init();
    defer f.deinit();

    const sub = try f.data(try f.authed("events.subscribe", ""));
    defer sub.deinit();
    try testing.expectEqual(
        @as(usize, EventKind.subscribable.len),
        sub.value.object.get("events").?.array.items.len,
    );
}

test "events.subscribe twice replaces the previous subscription" {
    var f = try Fixture.init();
    defer f.deinit();

    _ = try f.authed("events.subscribe", ",\"opts\":{\"events\":[\"bell\"]}");
    f.reset();
    _ = try f.authed("events.subscribe", ",\"opts\":{\"events\":[\"resize\"]}");
    f.reset();

    try testing.expectEqual(@as(usize, 1), f.broker.subscriberCount(testIo()));
    const mask = f.broker.maskOf(testIo(), f.handler.subscription.?).?;
    try testing.expect(mask.contains(.resize));
    try testing.expect(!mask.contains(.bell));
}

test "pollEvents: receives events published by other commands" {
    var f = try Fixture.init();
    defer f.deinit();

    _ = try f.authed("events.subscribe", "");
    f.reset();
    _ = try f.authed("pane.create", ",\"opts\":{\"title\":\"zsh\"}");
    f.reset();

    var out: [8]events.Event = undefined;
    const count = f.handler.pollEvents(testIo(), &out);
    try testing.expectEqual(@as(usize, 1), count);
    try testing.expectEqual(EventKind.pane_created, out[0].kind);
    try testing.expectEqual(@as(u64, 1), out[0].pane_id.?.raw);
    try testing.expectEqualStrings("zsh", out[0].payload.pane_created.title.slice());

    // Drained: nothing left.
    try testing.expectEqual(@as(usize, 0), f.handler.pollEvents(testIo(), &out));
}

test "pollEvents: loss is reported ahead of the surviving events" {
    var f = try Fixture.init();
    defer f.deinit();
    f.broker.capacity = 2;

    _ = try f.authed("events.subscribe", "");
    f.reset();
    for (0..5) |_| {
        _ = f.broker.publish(testIo(), events.Event.bell(PaneId.init(1)));
    }

    var out: [8]events.Event = undefined;
    const count = f.handler.pollEvents(testIo(), &out);
    try testing.expectEqual(@as(usize, 3), count);
    try testing.expectEqual(EventKind.events_dropped, out[0].kind);
    try testing.expectEqual(@as(u64, 3), out[0].payload.events_dropped.dropped);
    try testing.expectEqual(EventKind.bell, out[1].kind);
    try testing.expectEqual(EventKind.bell, out[2].kind);
}

test "pollEvents: no subscription means no events" {
    var f = try Fixture.init();
    defer f.deinit();

    _ = f.broker.publish(testIo(), events.Event.bell(PaneId.init(1)));
    var out: [4]events.Event = undefined;
    try testing.expectEqual(@as(usize, 0), f.handler.pollEvents(testIo(), &out));
}

test "pollEvents: a vanished subscription is forgotten, not spun on" {
    var f = try Fixture.init();
    defer f.deinit();

    _ = try f.authed("events.subscribe", "");
    f.reset();
    _ = f.broker.unsubscribe(testIo(), f.handler.subscription.?);

    var out: [4]events.Event = undefined;
    try testing.expectEqual(@as(usize, 0), f.handler.pollEvents(testIo(), &out));
    try testing.expectEqual(@as(?u64, null), f.handler.subscription);
}

test "handler.deinit drops the subscription" {
    var f = try Fixture.init();
    defer f.deinit();

    _ = try f.authed("events.subscribe", "");
    f.reset();
    try testing.expectEqual(@as(usize, 1), f.broker.subscriberCount(testIo()));

    f.handler.deinit(testIo());
    try testing.expectEqual(@as(usize, 0), f.broker.subscriberCount(testIo()));
    try testing.expectEqual(@as(?u64, null), f.handler.subscription);
}

test "host failure mapping covers the whole HostError set" {
    try testing.expectEqual(
        ErrorCode.pane_not_found,
        hostFailure(1, error.PaneNotFound).err.?.code,
    );
    try testing.expectEqual(
        ErrorCode.pane_not_found_after_close,
        hostFailure(1, error.PaneClosed).err.?.code,
    );
    try testing.expectEqual(
        ErrorCode.too_many_panes,
        hostFailure(1, error.TooManyPanes).err.?.code,
    );
    try testing.expectEqual(
        ErrorCode.host_unsupported,
        hostFailure(1, error.Unsupported).err.?.code,
    );
    try testing.expectEqual(ErrorCode.internal, hostFailure(1, error.Internal).err.?.code);
    try testing.expectEqual(ErrorCode.internal, hostFailure(1, error.OutOfMemory).err.?.code);
}

test "responses always carry the request id when one was sent" {
    var f = try Fixture.init();
    defer f.deinit();

    const with_id = try f.call("{\"id\":42,\"cmd\":\"ping\"}");
    try testing.expectEqual(@as(?u64, 42), with_id.id);
    f.reset();

    const without_id = try f.call("{\"cmd\":\"ping\"}");
    try testing.expectEqual(@as(?u64, null), without_id.id);
    try testing.expect(without_id.ok);
}
