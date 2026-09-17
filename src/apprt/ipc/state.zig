//! Machine-readable terminal state snapshot (`pane.state`).
//!
//! This is the "read the terminal" half of the agent IPC surface. It is a plain
//! data description with a JSON writer; the app adapter that fills it in from a
//! live surface lives in `app_host.zig`.
//!
//! The governing rule is that unknown state is written as `null`, never as a
//! plausible default. An agent that sees `null` knows to ask the host for more
//! information (or to assume nothing); an agent that sees `0` would wrongly
//! conclude the terminal is 0 rows tall.
//!
//!     zig test src/apprt/ipc/state.zig

const std = @import("std");
const protocol = @import("protocol.zig");

const PaneId = protocol.PaneId;
const Obj = protocol.Obj;
const WriteError = protocol.WriteError;

/// Cursor shape as reported by the terminal.
pub const CursorStyle = enum {
    block,
    bar,
    underline,
    block_hollow,

    pub fn parse(s: []const u8) ?CursorStyle {
        return std.meta.stringToEnum(CursorStyle, s);
    }

    pub fn name(self: CursorStyle) []const u8 {
        return @tagName(self);
    }
};

/// Cursor position and shape. `row`/`col` are viewport-relative and zero-based.
pub const Cursor = struct {
    row: u32,
    col: u32,
    /// Whether the cursor is currently drawn.
    visible: ?bool = null,
    style: ?CursorStyle = null,
    blinking: ?bool = null,
};

/// Terminal grid size in cells, plus pixel dimensions when the host knows them.
pub const Size = struct {
    cols: u16,
    rows: u16,
    pixel_width: ?u32 = null,
    pixel_height: ?u32 = null,
};

/// A complete state snapshot for one pane.
pub const Snapshot = struct {
    pane_id: PaneId,
    title: ?[]const u8 = null,
    pid: ?u32 = null,
    cwd: ?[]const u8 = null,
    size: Size,
    cursor: Cursor,
    /// Whether the alternate screen is active.
    alt_screen: ?bool = null,
    /// Whether this pane holds focus.
    focused: ?bool = null,
    /// Whether the child requested mouse tracking.
    mouse_tracking: ?bool = null,
    /// Number of bells rung in this pane since it was created.
    bell_count: ?u64 = null,
    /// Total scrollback rows retained (excluding the viewport).
    scrollback_rows: ?u64 = null,
    /// Height of the viewport in rows (usually `size.rows`).
    viewport_rows: ?u32 = null,
    /// Whether the child process has exited.
    exited: ?bool = null,
    /// Exit code, if the child exited with one. `null` when still running or
    /// when the code is unknown (for example, exit by signal).
    exit_code: ?i32 = null,
    /// Terminating signal, if the child was killed by one.
    exit_signal: ?u8 = null,
    /// Command line of the child, when the host tracks it.
    command: ?[]const u8 = null,
    /// Timestamp of the last grid activity, in milliseconds since the Unix
    /// epoch. Used by agents to detect a quiescent pane.
    last_activity_ms: ?i64 = null,

    /// Write the snapshot as a JSON object.
    pub fn writeJson(self: Snapshot, w: *std.Io.Writer) WriteError!void {
        var o = try Obj.init(w);
        try o.paneId("pane_id", self.pane_id);
        try o.optString("title", self.title);
        try o.optUint("pid", if (self.pid) |v| v else null);
        try o.optString("cwd", self.cwd);
        try o.optString("command", self.command);

        var size = try o.openIn("size", '{');
        try size.uint("cols", self.size.cols);
        try size.uint("rows", self.size.rows);
        try size.optUint("pixel_width", if (self.size.pixel_width) |v| v else null);
        try size.optUint("pixel_height", if (self.size.pixel_height) |v| v else null);
        try size.close('}');

        var cursor = try o.openIn("cursor", '{');
        try cursor.uint("row", self.cursor.row);
        try cursor.uint("col", self.cursor.col);
        try cursor.optBool("visible", self.cursor.visible);
        if (self.cursor.style) |style| {
            try cursor.string("style", style.name());
        } else {
            try cursor.nullField("style");
        }
        try cursor.optBool("blinking", self.cursor.blinking);
        try cursor.close('}');

        try o.optBool("alt_screen", self.alt_screen);
        try o.optBool("focused", self.focused);
        try o.optBool("mouse_tracking", self.mouse_tracking);
        try o.optUint("bell_count", self.bell_count);
        try o.optUint("scrollback_rows", self.scrollback_rows);
        try o.optUint("viewport_rows", if (self.viewport_rows) |v| v else null);
        try o.optBool("exited", self.exited);
        try o.optInt("exit_code", if (self.exit_code) |v| v else null);
        try o.optUint("exit_signal", if (self.exit_signal) |v| v else null);
        try o.optInt("last_activity_ms", self.last_activity_ms);

        try o.close('}');
    }

    /// Render to an owned string. Caller frees.
    pub fn toJsonAlloc(self: Snapshot, alloc: std.mem.Allocator) protocol.EncodeError![]u8 {
        var buf: std.Io.Writer.Allocating = .init(alloc);
        errdefer buf.deinit();
        try self.writeJson(&buf.writer);
        return buf.toOwnedSlice();
    }
};

// ─────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "snapshot: fully populated write" {
    const snap: Snapshot = .{
        .pane_id = PaneId.init(3),
        .title = "bash",
        .pid = 12345,
        .cwd = "/Users/me/project",
        .command = "/bin/zsh -l",
        .size = .{ .cols = 120, .rows = 40, .pixel_width = 1440, .pixel_height = 960 },
        .cursor = .{ .row = 12, .col = 45, .visible = true, .style = .block, .blinking = false },
        .alt_screen = false,
        .focused = true,
        .mouse_tracking = true,
        .bell_count = 0,
        .scrollback_rows = 1024,
        .viewport_rows = 40,
        .exited = false,
        .last_activity_ms = 1_700_000_000_000,
    };

    const json = try snap.toJsonAlloc(testing.allocator);
    defer testing.allocator.free(json);

    try testing.expectEqualStrings(
        "{\"pane_id\":\"p-3\",\"title\":\"bash\",\"pid\":12345," ++
            "\"cwd\":\"/Users/me/project\",\"command\":\"/bin/zsh -l\"," ++
            "\"size\":{\"cols\":120,\"rows\":40,\"pixel_width\":1440,\"pixel_height\":960}," ++
            "\"cursor\":{\"row\":12,\"col\":45,\"visible\":true,\"style\":\"block\",\"blinking\":false}," ++
            "\"alt_screen\":false,\"focused\":true,\"mouse_tracking\":true,\"bell_count\":0," ++
            "\"scrollback_rows\":1024,\"viewport_rows\":40,\"exited\":false,\"exit_code\":null," ++
            "\"exit_signal\":null,\"last_activity_ms\":1700000000000}",
        json,
    );
}

test "snapshot: unknown fields are null, not plausible defaults" {
    const snap: Snapshot = .{
        .pane_id = PaneId.init(1),
        .size = .{ .cols = 80, .rows = 24 },
        .cursor = .{ .row = 0, .col = 0 },
    };

    const json = try snap.toJsonAlloc(testing.allocator);
    defer testing.allocator.free(json);

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, json, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;

    try testing.expectEqual(std.json.Value.null, obj.get("title").?);
    try testing.expectEqual(std.json.Value.null, obj.get("pid").?);
    try testing.expectEqual(std.json.Value.null, obj.get("exited").?);
    try testing.expectEqual(std.json.Value.null, obj.get("exit_code").?);
    try testing.expectEqual(@as(i64, 80), obj.get("size").?.object.get("cols").?.integer);
    try testing.expectEqual(std.json.Value.null, obj.get("size").?.object.get("pixel_width").?);
    try testing.expectEqual(std.json.Value.null, obj.get("cursor").?.object.get("visible").?);
    try testing.expectEqual(std.json.Value.null, obj.get("cursor").?.object.get("style").?);
}

test "snapshot: exited child with no exit code is distinguishable from alive" {
    const snap: Snapshot = .{
        .pane_id = PaneId.init(9),
        .size = .{ .cols = 10, .rows = 2 },
        .cursor = .{ .row = 0, .col = 0 },
        .exited = true,
        .exit_signal = 9,
    };

    const json = try snap.toJsonAlloc(testing.allocator);
    defer testing.allocator.free(json);

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, json, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;
    try testing.expectEqual(true, obj.get("exited").?.bool);
    try testing.expectEqual(std.json.Value.null, obj.get("exit_code").?);
    try testing.expectEqual(@as(i64, 9), obj.get("exit_signal").?.integer);
}

test "snapshot: json is valid and re-parsable" {
    const snap: Snapshot = .{
        .pane_id = PaneId.init(42),
        .title = "quote\" and \\ backslash",
        .size = .{ .cols = 1, .rows = 1 },
        .cursor = .{ .row = 0, .col = 1, .style = .block_hollow },
    };
    const json = try snap.toJsonAlloc(testing.allocator);
    defer testing.allocator.free(json);

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, json, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;
    try testing.expectEqualStrings("quote\" and \\ backslash", obj.get("title").?.string);
    try testing.expectEqualStrings(
        "block_hollow",
        obj.get("cursor").?.object.get("style").?.string,
    );
}

test "cursor style names round-trip" {
    inline for (@typeInfo(CursorStyle).@"enum".fields) |f| {
        const style: CursorStyle = @enumFromInt(f.value);
        try testing.expectEqual(style, CursorStyle.parse(style.name()).?);
    }
}
