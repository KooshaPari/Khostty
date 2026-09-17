//! Agent IPC protocol v1: wire types and JSON codec.
//!
//! This file is the executable half of `protocol.md` in this directory. It owns:
//!
//!   * the wire constants (`version`, frame limits),
//!   * the request/response envelopes and the command table,
//!   * the JSON reader for requests (tolerant of unknown fields, strict about
//!     the types of known fields),
//!   * small JSON writing helpers (`Obj`, `Arr`, `writeString`) shared by
//!     `pane.zig`, `state.zig`, and `events.zig`.
//!
//! Nothing here depends on the application runtime, so this module is unit
//! testable on its own:
//!
//!     zig test src/apprt/ipc/protocol.zig

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;

/// Protocol version spoken by this server. See `protocol.md` section 6.
pub const version: u32 = 1;

/// Maximum size of a single request frame, in bytes. Frames larger than this
/// are rejected with `bad_request` and the connection is closed.
pub const max_frame_bytes: usize = 1024 * 1024;

/// Error set of every JSON writer used by this protocol. `std.Io.Writer`
/// collapses allocation failure into `error.WriteFailed` for buffered writers
/// (`std.Io.Writer.Allocating.drain`), so writers only ever see this set.
pub const WriteError = std.Io.Writer.Error;

/// Error set of helper functions that both render and allocate (for example
/// `state.Snapshot.toJsonAlloc`, which must also surface allocation failure
/// from `toOwnedSlice`).
pub const EncodeError = Allocator.Error || WriteError;

// ─────────────────────────────────────────────────────────────────────────
// Error codes
// ─────────────────────────────────────────────────────────────────────────

/// Machine-readable error code carried in every failed response.
pub const ErrorCode = enum {
    /// Malformed JSON, missing `cmd`, bad field type, oversized frame.
    bad_request,
    /// `cmd` is not in the command table.
    unknown_command,
    /// Missing or incorrect auth token.
    unauthorized,
    /// `v` is not supported by this server.
    version_unsupported,
    /// `pane_id` does not address a live pane.
    pane_not_found,
    /// The pane exited between lookup and the operation.
    pane_not_found_after_close,
    /// The host runtime cannot service this command.
    host_unsupported,
    /// The configured pane ceiling was reached.
    too_many_panes,
    /// `events.unsubscribe` with no active subscription.
    not_subscribed,
    /// Unexpected host failure.
    internal,

    /// Wire name (snake_case, matches `protocol.md`).
    pub fn name(self: ErrorCode) []const u8 {
        return @tagName(self);
    }

    /// Parse a wire name. Used by tests and by external clients in-process.
    pub fn fromName(s: []const u8) ?ErrorCode {
        return std.meta.stringToEnum(ErrorCode, s);
    }
};

// ─────────────────────────────────────────────────────────────────────────
// Command table
// ─────────────────────────────────────────────────────────────────────────

/// Commands an agent may send. Wire names are dotted; enum tags cannot be.
pub const Command = enum {
    ping,
    pane_create,
    pane_close,
    pane_focus,
    pane_list,
    pane_write,
    pane_state,
    pane_search,
    pane_resize_split,
    pane_equalize,
    pane_zoom,
    events_subscribe,
    events_unsubscribe,

    /// Wire name for a command.
    pub fn name(self: Command) []const u8 {
        return switch (self) {
            .ping => "ping",
            .pane_create => "pane.create",
            .pane_close => "pane.close",
            .pane_focus => "pane.focus",
            .pane_list => "pane.list",
            .pane_write => "pane.write",
            .pane_state => "pane.state",
            .pane_search => "pane.search",
            .pane_resize_split => "pane.resize_split",
            .pane_equalize => "pane.equalize",
            .pane_zoom => "pane.zoom",
            .events_subscribe => "events.subscribe",
            .events_unsubscribe => "events.unsubscribe",
        };
    }

    /// Parse a wire name.
    pub fn parse(s: []const u8) ?Command {
        inline for (@typeInfo(Command).@"enum".fields) |f| {
            const cmd: Command = @enumFromInt(f.value);
            if (std.mem.eql(u8, cmd.name(), s)) return cmd;
        }
        return null;
    }

    /// Whether an auth token is required. `ping` is intentionally open so an
    /// agent can probe liveness and version without holding a token.
    pub fn requiresAuth(self: Command) bool {
        return self != .ping;
    }

    /// Whether the command requires a `pane_id` argument.
    pub fn requiresPane(self: Command) bool {
        return switch (self) {
            .pane_close, .pane_focus, .pane_write, .pane_state, .pane_search, .pane_zoom => true,
            else => false,
        };
    }
};

// ─────────────────────────────────────────────────────────────────────────
// Small enums
// ─────────────────────────────────────────────────────────────────────────

/// Split direction, matching upstream `apprt.SplitDirection` tag names.
pub const Direction = enum {
    right,
    down,
    left,
    up,

    pub fn name(self: Direction) []const u8 {
        return @tagName(self);
    }

    pub fn parse(s: []const u8) ?Direction {
        return std.meta.stringToEnum(Direction, s);
    }
};

/// tmux-style split orientation from the draft protocol.
pub const SplitKind = enum {
    /// Side-by-side panes (splits to the `right`).
    vertical,
    /// Stacked panes (splits `down`).
    horizontal,

    pub fn parse(s: []const u8) ?SplitKind {
        return std.meta.stringToEnum(SplitKind, s);
    }

    pub fn direction(self: SplitKind) Direction {
        return switch (self) {
            .vertical => .right,
            .horizontal => .down,
        };
    }
};

/// Asynchronous event kinds. `events_dropped` is synthetic: it is emitted by
/// the broker itself when a subscriber's bounded queue overflows.
pub const EventKind = enum {
    title_change,
    child_exit,
    resize,
    bell,
    focus_change,
    pane_created,
    pane_closed,
    events_dropped,

    pub fn name(self: EventKind) []const u8 {
        return @tagName(self);
    }

    pub fn parse(s: []const u8) ?EventKind {
        return std.meta.stringToEnum(EventKind, s);
    }

    /// Kinds an agent may subscribe to explicitly.
    pub const subscribable = [_]EventKind{
        .title_change,
        .child_exit,
        .resize,
        .bell,
        .focus_change,
        .pane_created,
        .pane_closed,
    };

    /// Every kind, including synthetic ones.
    pub const all = [_]EventKind{
        .title_change,
        .child_exit,
        .resize,
        .bell,
        .focus_change,
        .pane_created,
        .pane_closed,
        .events_dropped,
    };

    pub fn maskAll() EventMask {
        var m: EventMask = .initEmpty();
        for (all) |k| m.insert(k);
        return m;
    }

    pub fn maskSubscribable() EventMask {
        var m: EventMask = .initEmpty();
        for (subscribable) |k| m.insert(k);
        return m;
    }
};

/// Bit set of event kinds.
pub const EventMask = std.EnumSet(EventKind);

// ─────────────────────────────────────────────────────────────────────────
// Pane handles
// ─────────────────────────────────────────────────────────────────────────

/// A pane handle. Backed by the core surface id (`src/Surface.zig: id: u64`)
/// and rendered as `"p-<id>"` per the draft protocol. Both `"p-3"` and `"3"`
/// are accepted on input, and a bare integer is accepted too.
pub const PaneId = struct {
    raw: u64,

    pub const prefix = "p-";

    pub fn init(raw: u64) PaneId {
        return .{ .raw = raw };
    }

    /// Parse `"p-3"`, `"3"`, or a bare integer value.
    pub fn parseString(s: []const u8) ?PaneId {
        const digits = if (std.mem.startsWith(u8, s, prefix)) s[prefix.len..] else s;
        if (digits.len == 0) return null;
        const raw = std.fmt.parseInt(u64, digits, 10) catch return null;
        return .{ .raw = raw };
    }

    pub fn eql(a: PaneId, b: PaneId) bool {
        return a.raw == b.raw;
    }

    /// Write `"p-3"` (with JSON quoting).
    pub fn writeJson(self: PaneId, w: *std.Io.Writer) WriteError!void {
        try w.print("\"{s}{d}\"", .{ prefix, self.raw });
    }
};

// ─────────────────────────────────────────────────────────────────────────
// Requests
// ─────────────────────────────────────────────────────────────────────────

/// Parsed request. All slices point into the arena owned by `Parsed`.
pub const Request = struct {
    v: u32 = version,
    id: ?u64 = null,
    auth: ?[]const u8 = null,
    cmd: Command,
    pane_id: ?PaneId = null,
    data: ?[]const u8 = null,
    query: ?[]const u8 = null,
    opts: Options = .{},

    /// The pane this request targets, taking `opts.pane_id` into account for
    /// the commands that accept either location.
    pub fn targetPane(self: Request) ?PaneId {
        return self.pane_id orelse self.opts.pane_id;
    }

    /// Serialize. Used by the client helper in `server.zig` and by tests.
    pub fn write(self: Request, w: *std.Io.Writer) WriteError!void {
        var o = try Obj.init(w);
        try o.uint("v", self.v);
        if (self.id) |id| try o.uint("id", id);
        if (self.auth) |a| try o.string("auth", a);
        try o.string("cmd", self.cmd.name());
        if (self.pane_id) |p| try o.paneId("pane_id", p);
        if (self.data) |d| try o.string("data", d);
        if (self.query) |q| try o.string("query", q);

        if (!self.opts.isDefault()) {
            var opts = try o.openIn("opts", '{');
            if (self.opts.pane_id) |p| try opts.paneId("pane_id", p);
            if (self.opts.split) |s| try opts.string("split", @tagName(s));
            if (self.opts.dir) |d| try opts.string("dir", d.name());
            if (self.opts.cwd) |c| try opts.string("cwd", c);
            if (self.opts.title) |t| try opts.string("title", t);
            if (self.opts.command) |c| try opts.string("command", c);
            if (self.opts.focus) |f| try opts.boolean("focus", f);
            if (self.opts.limit) |l| try opts.uint("limit", l);
            if (self.opts.amount) |a| try opts.uint("amount", a);
            if (self.opts.events.len > 0) {
                var arr = try opts.openIn("events", '[');
                for (self.opts.events, 0..) |kind, i| {
                    if (i > 0) try opts.w.writeByte(',');
                    try writeString(opts.w, kind.name());
                }
                try arr.close(']');
            }
            try opts.close('}');
        }

        try o.close('}');
    }
};

/// Command options. Unknown option names are ignored on input.
pub const Options = struct {
    /// Pane to act relative to (`pane.create`; elsewhere use `pane_id`).
    pane_id: ?PaneId = null,
    /// tmux-style split orientation.
    split: ?SplitKind = null,
    /// Explicit split/resize direction; overrides `split`.
    dir: ?Direction = null,
    /// Working directory for a new pane.
    cwd: ?[]const u8 = null,
    /// Requested title for a new pane.
    title: ?[]const u8 = null,
    /// Reserved for v2; upstream `new_split` takes no arguments today.
    command: ?[]const u8 = null,
    /// Focus the new pane (`pane.create`).
    focus: ?bool = null,
    /// Result cap (`pane.search`).
    limit: ?usize = null,
    /// Resize amount in cells (`pane.resize_split`).
    amount: ?u16 = null,
    /// Requested event kinds (`events.subscribe`); empty means all.
    events: []const EventKind = &.{},

    pub fn isDefault(self: Options) bool {
        return self.pane_id == null and
            self.split == null and
            self.dir == null and
            self.cwd == null and
            self.title == null and
            self.command == null and
            self.focus == null and
            self.limit == null and
            self.amount == null and
            self.events.len == 0;
    }

    /// Split direction to use, applying tmux-style defaults.
    pub fn effectiveDirection(self: Options) Direction {
        if (self.dir) |d| return d;
        if (self.split) |split| return split.direction();
        return SplitKind.vertical.direction();
    }
};

/// A parse failure: an error code plus a human-readable message.
pub const ParseFailure = struct {
    code: ErrorCode,
    message: []const u8,
};

/// Result of parsing one frame.
pub const ParseResult = union(enum) {
    ok: Request,
    err: ParseFailure,
};

/// Owns the memory backing a parsed request.
pub const Parsed = struct {
    arena: std.heap.ArenaAllocator,
    result: ParseResult,

    pub fn deinit(self: *Parsed) void {
        self.arena.deinit();
    }

    /// The request, if parsing succeeded.
    pub fn request(self: *const Parsed) ?*const Request {
        return switch (self.result) {
            .ok => |*r| r,
            .err => null,
        };
    }

    /// The failure, if parsing failed.
    pub fn failure(self: *const Parsed) ?ParseFailure {
        return switch (self.result) {
            .ok => null,
            .err => |e| e,
        };
    }
};

/// Parse one newline-delimited frame. Only allocation failure is returned as
/// an error; malformed input is reported as `ParseResult.err` so the caller
/// can answer with a structured JSON error.
pub fn parse(gpa: Allocator, bytes: []const u8) Allocator.Error!Parsed {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();

    var ctx: Ctx = .{ .arena = a };
    const result: ParseResult = blk: {
        if (bytes.len > max_frame_bytes) {
            break :blk .{ .err = .{
                .code = .bad_request,
                .message = try std.fmt.allocPrint(
                    a,
                    "frame of {d} bytes exceeds the {d} byte limit",
                    .{ bytes.len, max_frame_bytes },
                ),
            } };
        }

        const tree = json.parseFromSlice(json.Value, a, bytes, .{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => break :blk .{ .err = .{
                .code = .bad_request,
                .message = "malformed JSON",
            } },
        };

        switch (tree.value) {
            .object => |obj| {
                const req = parseRequest(&ctx, obj) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.Failed => break :blk .{ .err = .{
                        .code = ctx.fail_code,
                        .message = ctx.fail_msg,
                    } },
                };
                break :blk .{ .ok = req };
            },
            else => break :blk .{ .err = .{
                .code = .bad_request,
                .message = "request must be a JSON object",
            } },
        }
    };

    return .{ .arena = arena, .result = result };
}

const Ctx = struct {
    arena: Allocator,
    fail_code: ErrorCode = .bad_request,
    fail_msg: []const u8 = "",

    fn fail(self: *Ctx, code: ErrorCode, comptime fmt: []const u8, args: anytype) error{Failed} {
        self.fail_code = code;
        self.fail_msg = std.fmt.allocPrint(self.arena, fmt, args) catch "out of memory";
        return error.Failed;
    }
};

const FieldError = error{ Failed, OutOfMemory };

fn parseRequest(ctx: *Ctx, obj: json.ObjectMap) FieldError!Request {
    var req: Request = .{ .cmd = undefined };

    if (try optionalUintField(ctx, obj, "v")) |v| {
        if (v > std.math.maxInt(u32)) {
            return ctx.fail(.version_unsupported, "version {d} is not supported", .{v});
        }
        req.v = @intCast(v);
    }
    if (req.v != version) {
        return ctx.fail(
            .version_unsupported,
            "version {d} is not supported by this server (expects {d})",
            .{ req.v, version },
        );
    }

    if (try optionalUintField(ctx, obj, "id")) |id| req.id = id;

    req.auth = try optionalStringField(ctx, obj, "auth");

    const cmd_name = (try optionalStringField(ctx, obj, "cmd")) orelse
        return ctx.fail(.bad_request, "missing \"cmd\"", .{});
    req.cmd = Command.parse(cmd_name) orelse
        return ctx.fail(.unknown_command, "unknown command \"{s}\"", .{cmd_name});

    req.pane_id = try optionalPaneIdField(ctx, obj, "pane_id");
    req.data = try optionalStringField(ctx, obj, "data");
    req.query = try optionalStringField(ctx, obj, "query");

    if (obj.get("opts")) |opts_value| switch (opts_value) {
        .object => |opts_obj| req.opts = try parseOptions(ctx, opts_obj),
        .null => {},
        else => return ctx.fail(.bad_request, "\"opts\" must be an object", .{}),
    };

    return req;
}

fn parseOptions(ctx: *Ctx, obj: json.ObjectMap) FieldError!Options {
    var opts: Options = .{};

    opts.pane_id = try optionalPaneIdField(ctx, obj, "pane_id");
    if (try optionalStringField(ctx, obj, "split")) |s| {
        opts.split = SplitKind.parse(s) orelse
            return ctx.fail(
                .bad_request,
                "\"split\" must be \"vertical\" or \"horizontal\", got \"{s}\"",
                .{s},
            );
    }
    if (try optionalStringField(ctx, obj, "dir")) |d| {
        opts.dir = Direction.parse(d) orelse
            return ctx.fail(.bad_request, "\"dir\" must be right|down|left|up, got \"{s}\"", .{d});
    }
    opts.cwd = try optionalStringField(ctx, obj, "cwd");
    opts.title = try optionalStringField(ctx, obj, "title");
    opts.command = try optionalStringField(ctx, obj, "command");
    opts.focus = try optionalBoolField(ctx, obj, "focus");
    if (try optionalUintField(ctx, obj, "limit")) |limit| {
        opts.limit = std.math.cast(usize, limit) orelse
            return ctx.fail(.bad_request, "\"limit\" is out of range", .{});
    }
    if (try optionalUintField(ctx, obj, "amount")) |amount| {
        opts.amount = std.math.cast(u16, amount) orelse
            return ctx.fail(.bad_request, "\"amount\" must fit in 0..65535", .{});
    }

    if (obj.get("events")) |events_value| switch (events_value) {
        .array => |items| {
            var list = try ctx.arena.alloc(EventKind, items.items.len);
            for (items.items, 0..) |item, i| {
                const s = switch (item) {
                    .string => |s| s,
                    else => return ctx.fail(
                        .bad_request,
                        "\"opts.events\" entries must be strings",
                        .{},
                    ),
                };
                list[i] = EventKind.parse(s) orelse
                    return ctx.fail(.bad_request, "unknown event kind \"{s}\"", .{s});
            }
            opts.events = list;
        },
        .null => {},
        else => return ctx.fail(.bad_request, "\"opts.events\" must be an array", .{}),
    };

    return opts;
}

fn optionalStringField(ctx: *Ctx, obj: json.ObjectMap, key: []const u8) FieldError!?[]const u8 {
    const v = obj.get(key) orelse return null;
    switch (v) {
        .string => |s| return s,
        .null => return null,
        else => return ctx.fail(.bad_request, "\"{s}\" must be a string", .{key}),
    }
}

fn optionalBoolField(ctx: *Ctx, obj: json.ObjectMap, key: []const u8) FieldError!?bool {
    const v = obj.get(key) orelse return null;
    switch (v) {
        .bool => |b| return b,
        .null => return null,
        else => return ctx.fail(.bad_request, "\"{s}\" must be a boolean", .{key}),
    }
}

fn optionalUintField(ctx: *Ctx, obj: json.ObjectMap, key: []const u8) FieldError!?u64 {
    const v = obj.get(key) orelse return null;
    switch (v) {
        .integer => |i| {
            if (i < 0) return ctx.fail(.bad_request, "\"{s}\" must not be negative", .{key});
            return @intCast(i);
        },
        .null => return null,
        else => return ctx.fail(.bad_request, "\"{s}\" must be an integer", .{key}),
    }
}

fn optionalPaneIdField(ctx: *Ctx, obj: json.ObjectMap, key: []const u8) FieldError!?PaneId {
    const v = obj.get(key) orelse return null;
    switch (v) {
        .integer => |i| {
            if (i < 0) return ctx.fail(.bad_request, "\"{s}\" must not be negative", .{key});
            return PaneId.init(@intCast(i));
        },
        .string => |s| return PaneId.parseString(s) orelse
            ctx.fail(.bad_request, "\"{s}\" is not a pane id: \"{s}\"", .{ key, s }),
        .null => return null,
        else => return ctx.fail(.bad_request, "\"{s}\" must be a pane id", .{key}),
    }
}

// ─────────────────────────────────────────────────────────────────────────
// Responses
// ─────────────────────────────────────────────────────────────────────────

pub const ErrorInfo = struct {
    code: ErrorCode,
    message: []const u8,
};

/// Response envelope. `json` is a pre-rendered JSON fragment (object or array)
/// produced by the module that owns the payload.
pub const Response = struct {
    id: ?u64 = null,
    ok: bool = true,
    json: ?[]const u8 = null,
    err: ?ErrorInfo = null,

    pub fn okJson(id: ?u64, data_json: ?[]const u8) Response {
        return .{ .id = id, .ok = true, .json = data_json };
    }

    pub fn failure(id: ?u64, code: ErrorCode, message: []const u8) Response {
        return .{ .id = id, .ok = false, .err = .{ .code = code, .message = message } };
    }

    /// Write the response envelope. Does not append a newline.
    pub fn write(self: Response, w: *std.Io.Writer) WriteError!void {
        var o = try Obj.init(w);
        try o.uint("v", version);
        if (self.id) |id| try o.uint("id", id);
        try o.boolean("ok", self.ok);
        if (self.ok) {
            if (self.json) |j| {
                try o.raw("data", j);
            } else {
                try o.nullField("data");
            }
        } else if (self.err) |e| {
            var err_obj = try o.openIn("error", '{');
            try err_obj.string("code", e.code.name());
            try err_obj.string("message", e.message);
            try err_obj.close('}');
        } else {
            try o.nullField("error");
        }
        try o.close('}');
    }

    /// Write the response as a framed line.
    pub fn writeLine(self: Response, w: *std.Io.Writer) WriteError!void {
        try self.write(w);
        try w.writeByte('\n');
    }
};

// ─────────────────────────────────────────────────────────────────────────
// JSON writing helpers
// ─────────────────────────────────────────────────────────────────────────

/// Write a JSON string with correct escaping.
pub fn writeString(w: *std.Io.Writer, s: []const u8) WriteError!void {
    try json.Stringify.value(s, .{}, w);
}

/// Incremental JSON object writer. `init` writes `{`; `close('}')` finishes it.
pub const Obj = struct {
    w: *std.Io.Writer,
    empty: bool = true,

    pub fn init(w: *std.Io.Writer) WriteError!Obj {
        try w.writeByte('{');
        return .{ .w = w };
    }

    pub fn close(self: *Obj, bracket: u8) WriteError!void {
        try self.w.writeByte(bracket);
    }

    /// Write a key, and open a nested value with `bracket` (`{` or `[`).
    pub fn openIn(self: *Obj, key: []const u8, bracket: u8) WriteError!Obj {
        try self.name(key);
        try self.w.writeByte(bracket);
        return .{ .w = self.w };
    }

    /// Write a key and open a nested JSON array.
    pub fn openArr(self: *Obj, key: []const u8) WriteError!Arr {
        try self.name(key);
        try self.w.writeByte('[');
        return .{ .w = self.w };
    }

    pub fn name(self: *Obj, key: []const u8) WriteError!void {
        if (!self.empty) try self.w.writeByte(',');
        self.empty = false;
        try writeString(self.w, key);
        try self.w.writeByte(':');
    }

    /// Write a raw, already-valid JSON fragment under `key`.
    pub fn raw(self: *Obj, key: []const u8, fragment: []const u8) WriteError!void {
        try self.name(key);
        try self.w.writeAll(fragment);
    }

    pub fn string(self: *Obj, key: []const u8, value: []const u8) WriteError!void {
        try self.name(key);
        try writeString(self.w, value);
    }

    pub fn optString(self: *Obj, key: []const u8, value: ?[]const u8) WriteError!void {
        try self.name(key);
        if (value) |v| try writeString(self.w, v) else try self.w.writeAll("null");
    }

    pub fn uint(self: *Obj, key: []const u8, value: u64) WriteError!void {
        try self.name(key);
        try self.w.print("{d}", .{value});
    }

    pub fn int(self: *Obj, key: []const u8, value: i64) WriteError!void {
        try self.name(key);
        try self.w.print("{d}", .{value});
    }

    pub fn optUint(self: *Obj, key: []const u8, value: ?u64) WriteError!void {
        try self.name(key);
        if (value) |v| try self.w.print("{d}", .{v}) else try self.w.writeAll("null");
    }

    pub fn optInt(self: *Obj, key: []const u8, value: ?i64) WriteError!void {
        try self.name(key);
        if (value) |v| try self.w.print("{d}", .{v}) else try self.w.writeAll("null");
    }

    pub fn boolean(self: *Obj, key: []const u8, value: bool) WriteError!void {
        try self.name(key);
        try self.w.writeAll(if (value) "true" else "false");
    }

    pub fn optBool(self: *Obj, key: []const u8, value: ?bool) WriteError!void {
        try self.name(key);
        if (value) |v| {
            try self.w.writeAll(if (v) "true" else "false");
        } else {
            try self.w.writeAll("null");
        }
    }

    pub fn nullField(self: *Obj, key: []const u8) WriteError!void {
        try self.name(key);
        try self.w.writeAll("null");
    }

    pub fn paneId(self: *Obj, key: []const u8, value: PaneId) WriteError!void {
        try self.name(key);
        try value.writeJson(self.w);
    }

    pub fn optPaneId(self: *Obj, key: []const u8, value: ?PaneId) WriteError!void {
        try self.name(key);
        if (value) |v| try v.writeJson(self.w) else try self.w.writeAll("null");
    }
};

/// Incremental JSON array writer. `init` writes `[`; `close(']')` finishes it.
pub const Arr = struct {
    w: *std.Io.Writer,
    first: bool = true,

    pub fn init(w: *std.Io.Writer) WriteError!Arr {
        try w.writeByte('[');
        return .{ .w = w };
    }

    pub fn close(self: *Arr, bracket: u8) WriteError!void {
        try self.w.writeByte(bracket);
    }

    fn next(self: *Arr) WriteError!void {
        if (!self.first) try self.w.writeByte(',');
        self.first = false;
    }

    pub fn item(self: *Arr, value: []const u8) WriteError!void {
        try self.next();
        try writeString(self.w, value);
    }

    pub fn raw(self: *Arr, fragment: []const u8) WriteError!void {
        try self.next();
        try self.w.writeAll(fragment);
    }

    pub fn uint(self: *Arr, value: u64) WriteError!void {
        try self.next();
        try self.w.print("{d}", .{value});
    }

    pub fn paneId(self: *Arr, value: PaneId) WriteError!void {
        try self.next();
        try value.writeJson(self.w);
    }
};

// ─────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────

const testing = std.testing;

fn parseExpectingOk(bytes: []const u8) !Parsed {
    var parsed = try parse(testing.allocator, bytes);
    errdefer parsed.deinit();
    if (parsed.failure()) |f| {
        std.debug.print("unexpected parse failure: {s} ({s})\n", .{ f.code.name(), f.message });
        return error.TestUnexpectedResult;
    }
    try testing.expect(parsed.request() != null);
    return parsed;
}

test "parse: pane.create with tmux-style split" {
    var parsed = try parseExpectingOk(
        \\{"id":7,"auth":"tok","cmd":"pane.create","opts":{"split":"vertical","cwd":"/tmp"}}
    );
    defer parsed.deinit();
    const req = parsed.request().?;
    try testing.expectEqual(@as(?u64, 7), req.id);
    try testing.expectEqualStrings("tok", req.auth.?);
    try testing.expectEqual(Command.pane_create, req.cmd);
    try testing.expectEqual(SplitKind.vertical, req.opts.split.?);
    try testing.expectEqualStrings("/tmp", req.opts.cwd.?);
    try testing.expectEqual(Direction.right, req.opts.effectiveDirection());
}

test "parse: horizontal split maps to down" {
    var parsed = try parseExpectingOk("{\"cmd\":\"pane.create\",\"opts\":{\"split\":\"horizontal\"}}");
    defer parsed.deinit();
    try testing.expectEqual(Direction.down, parsed.request().?.opts.effectiveDirection());
}

test "parse: explicit dir overrides split" {
    var parsed = try parseExpectingOk(
        \\{"cmd":"pane.create","opts":{"split":"vertical","dir":"up"}}
    );
    defer parsed.deinit();
    try testing.expectEqual(Direction.up, parsed.request().?.opts.effectiveDirection());
}

test "parse: pane ids accept p-3, 3, and 3" {
    const cases = [_]struct { json: []const u8, raw: u64 }{
        .{ .json = "{\"cmd\":\"pane.write\",\"pane_id\":\"p-3\",\"data\":\"x\"}", .raw = 3 },
        .{ .json = "{\"cmd\":\"pane.write\",\"pane_id\":\"3\",\"data\":\"x\"}", .raw = 3 },
        .{ .json = "{\"cmd\":\"pane.write\",\"pane_id\":3,\"data\":\"x\"}", .raw = 3 },
        .{ .json = "{\"cmd\":\"pane.write\",\"opts\":{\"pane_id\":\"p-9\"},\"data\":\"x\"}", .raw = 9 },
    };
    for (cases) |case| {
        var parsed = try parseExpectingOk(case.json);
        defer parsed.deinit();
        try testing.expectEqual(case.raw, parsed.request().?.targetPane().?.raw);
    }
}

test "parse: bad pane id is a bad_request with the offending value" {
    var parsed = try parse(testing.allocator, "{\"cmd\":\"pane.write\",\"pane_id\":\"nope\"}");
    defer parsed.deinit();
    const f = parsed.failure().?;
    try testing.expectEqual(ErrorCode.bad_request, f.code);
    try testing.expect(std.mem.indexOf(u8, f.message, "nope") != null);
}

test "parse: unknown command is reported by name" {
    var parsed = try parse(testing.allocator, "{\"cmd\":\"pane.explode\"}");
    defer parsed.deinit();
    const f = parsed.failure().?;
    try testing.expectEqual(ErrorCode.unknown_command, f.code);
    try testing.expect(std.mem.indexOf(u8, f.message, "pane.explode") != null);
}

test "parse: every documented command name round-trips" {
    inline for (@typeInfo(Command).@"enum".fields) |f| {
        const cmd: Command = @enumFromInt(f.value);
        const name = cmd.name();
        try testing.expectEqual(cmd, Command.parse(name).?);
        try testing.expect(std.mem.indexOfScalar(u8, name, '.') != null or cmd == .ping);
    }
}

test "parse: missing cmd" {
    var parsed = try parse(testing.allocator, "{\"id\":1}");
    defer parsed.deinit();
    try testing.expectEqual(ErrorCode.bad_request, parsed.failure().?.code);
}

test "parse: malformed json" {
    var parsed = try parse(testing.allocator, "{\"cmd\":");
    defer parsed.deinit();
    try testing.expectEqual(ErrorCode.bad_request, parsed.failure().?.code);
}

test "parse: non-object frame" {
    var parsed = try parse(testing.allocator, "[1,2,3]");
    defer parsed.deinit();
    try testing.expectEqual(ErrorCode.bad_request, parsed.failure().?.code);
}

test "parse: version mismatch" {
    var parsed = try parse(testing.allocator, "{\"v\":99,\"cmd\":\"ping\"}");
    defer parsed.deinit();
    try testing.expectEqual(ErrorCode.version_unsupported, parsed.failure().?.code);
}

test "parse: absent version means current version" {
    var parsed = try parseExpectingOk("{\"cmd\":\"ping\"}");
    defer parsed.deinit();
    try testing.expectEqual(version, parsed.request().?.v);
}

test "parse: unknown top-level and opts fields are ignored" {
    var parsed = try parseExpectingOk(
        \\{"cmd":"pane.create","future":true,"opts":{"split":"vertical","nope":1}}
    );
    defer parsed.deinit();
    try testing.expectEqual(SplitKind.vertical, parsed.request().?.opts.split.?);
}

test "parse: wrong field type is rejected" {
    var parsed = try parse(testing.allocator, "{\"cmd\":\"pane.write\",\"data\":5}");
    defer parsed.deinit();
    const f = parsed.failure().?;
    try testing.expectEqual(ErrorCode.bad_request, f.code);
    try testing.expect(std.mem.indexOf(u8, f.message, "data") != null);
}

test "parse: events subscribe list" {
    var parsed = try parseExpectingOk(
        \\{"cmd":"events.subscribe","opts":{"events":["title_change","bell"]}}
    );
    defer parsed.deinit();
    const events = parsed.request().?.opts.events;
    try testing.expectEqual(@as(usize, 2), events.len);
    try testing.expectEqual(EventKind.title_change, events[0]);
    try testing.expectEqual(EventKind.bell, events[1]);
}

test "parse: unknown event kind is rejected" {
    var parsed = try parse(
        testing.allocator,
        "{\"cmd\":\"events.subscribe\",\"opts\":{\"events\":[\"explode\"]}}",
    );
    defer parsed.deinit();
    try testing.expectEqual(ErrorCode.bad_request, parsed.failure().?.code);
}

test "parse: search options" {
    var parsed = try parseExpectingOk(
        \\{"cmd":"pane.search","pane_id":"p-3","query":"error","opts":{"limit":5}}
    );
    defer parsed.deinit();
    const req = parsed.request().?;
    try testing.expectEqual(@as(?usize, 5), req.opts.limit);
    try testing.expectEqualStrings("error", req.query.?);
}

test "parse: resize_split options" {
    var parsed = try parseExpectingOk(
        \\{"cmd":"pane.resize_split","pane_id":"p-3","opts":{"dir":"left","amount":5}}
    );
    defer parsed.deinit();
    const req = parsed.request().?;
    try testing.expectEqual(Direction.left, req.opts.dir.?);
    try testing.expectEqual(@as(?u16, 5), req.opts.amount);
}

test "parse: frame over the limit" {
    const big = try testing.allocator.alloc(u8, max_frame_bytes + 1);
    defer testing.allocator.free(big);
    @memset(big, 'x');
    var parsed = try parse(testing.allocator, big);
    defer parsed.deinit();
    try testing.expectEqual(ErrorCode.bad_request, parsed.failure().?.code);
}

test "parse: data carries escaped VT bytes" {
    var parsed = try parseExpectingOk(
        \\{"cmd":"pane.write","pane_id":"p-1","data":"\u001b[31mred\u001b[0m\n"}
    );
    defer parsed.deinit();
    try testing.expectEqualStrings("\x1b[31mred\x1b[0m\n", parsed.request().?.data.?);
}

test "request: write then parse round-trips" {
    const original: Request = .{
        .id = 12,
        .auth = "secret",
        .cmd = .pane_create,
        .opts = .{ .split = .horizontal, .cwd = "/tmp", .focus = false, .title = "build" },
    };

    var buf: [1024]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try original.write(&w);

    var parsed = try parseExpectingOk(w.buffered());
    defer parsed.deinit();
    const req = parsed.request().?;
    try testing.expectEqual(original.id, req.id);
    try testing.expectEqualStrings("secret", req.auth.?);
    try testing.expectEqual(Command.pane_create, req.cmd);
    try testing.expectEqual(SplitKind.horizontal, req.opts.split.?);
    try testing.expectEqualStrings("/tmp", req.opts.cwd.?);
    try testing.expectEqual(@as(?bool, false), req.opts.focus);
    try testing.expectEqualStrings("build", req.opts.title.?);
}

test "request: pane_id and events round-trip" {
    const original: Request = .{
        .id = 2,
        .cmd = .events_subscribe,
        .opts = .{ .events = &.{ .title_change, .child_exit } },
    };

    var buf: [1024]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try original.write(&w);

    var parsed = try parseExpectingOk(w.buffered());
    defer parsed.deinit();
    try testing.expectEqual(@as(usize, 2), parsed.request().?.opts.events.len);
    try testing.expectEqual(EventKind.child_exit, parsed.request().?.opts.events[1]);
}

test "response: success shape" {
    var buf: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try (Response.okJson(7, "{\"pane_id\":\"p-3\"}")).writeLine(&w);
    try testing.expectEqualStrings(
        "{\"v\":1,\"id\":7,\"ok\":true,\"data\":{\"pane_id\":\"p-3\"}}\n",
        w.buffered(),
    );
}

test "response: failure shape" {
    var buf: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try (Response.failure(3, .pane_not_found, "no pane with id p-9")).write(&w);
    try testing.expectEqualStrings(
        "{\"v\":1,\"id\":3,\"ok\":false,\"error\":{\"code\":\"pane_not_found\",\"message\":\"no pane with id p-9\"}}",
        w.buffered(),
    );
}

test "response: version is echoed" {
    var buf: [128]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try (Response.okJson(null, null)).write(&w);
    try testing.expect(std.mem.startsWith(u8, w.buffered(), "{\"v\":1,\"ok\":true"));
}

test "json helpers: escaping" {
    var buf: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    var o = try Obj.init(&w);
    try o.string("title", "quote\" backslash\\ tab\t");
    try o.close('}');
    try testing.expectEqualStrings(
        "{\"title\":\"quote\\\" backslash\\\\ tab\\t\"}",
        w.buffered(),
    );
}

test "json helpers: null for unknown values, never a guess" {
    var buf: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    var o = try Obj.init(&w);
    try o.optString("title", null);
    try o.optUint("pid", null);
    try o.optBool("focused", null);
    try o.optPaneId("pane_id", null);
    try o.close('}');
    try testing.expectEqualStrings(
        "{\"title\":null,\"pid\":null,\"focused\":null,\"pane_id\":null}",
        w.buffered(),
    );
}

test "json helpers: nested object and array" {
    var buf: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    var o = try Obj.init(&w);
    var nested = try o.openIn("cursor", '{');
    try nested.uint("row", 12);
    try nested.uint("col", 45);
    try nested.close('}');
    var arr = try o.openArr("kinds");
    try arr.paneId(PaneId.init(3));
    try arr.paneId(PaneId.init(7));
    try arr.close(']');
    try o.close('}');
    try testing.expectEqualStrings(
        "{\"cursor\":{\"row\":12,\"col\":45},\"kinds\":[\"p-3\",\"p-7\"]}",
        w.buffered(),
    );
}

test "error codes: names are stable and parseable" {
    inline for (@typeInfo(ErrorCode).@"enum".fields) |f| {
        const code: ErrorCode = @enumFromInt(f.value);
        try testing.expectEqual(code, ErrorCode.fromName(code.name()).?);
    }
}

test "event kinds: subscribable is a subset of all" {
    for (EventKind.subscribable) |k| {
        try testing.expect(EventKind.maskAll().contains(k));
    }
    try testing.expect(!EventKind.maskSubscribable().contains(.events_dropped));
}
