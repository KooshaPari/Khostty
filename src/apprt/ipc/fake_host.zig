//! A minimal in-memory terminal model used as the `pane.Host` implementation
//! by IPC unit and integration tests.
//!
//! It is deliberately small but not fake-in-the-sense-of-lying: it parses the
//! VT sequences the tests actually depend on (printing, CR/LF, tab, backspace,
//! CSI cursor movement/positioning and SGR, OSC 0/2 title) and clamps to the
//! pane's grid, so `pane.write` -> `pane.state` and `pane.search` tests
//! exercise real parsing rather than a stub that echoes its input back.
//!
//! Not part of the shipped server; imported only by tests.

const std = @import("std");
const Allocator = std.mem.Allocator;

const pane = @import("pane.zig");
const protocol = @import("protocol.zig");
const state = @import("state.zig");

const PaneId = protocol.PaneId;

/// Grid cell budget for the mini emulator, so a runaway write cannot exhaust
/// memory in a test.
pub const max_text_bytes = 256 * 1024;

pub const FakeHost = struct {
    gpa: Allocator,
    panes: std.ArrayListUnmanaged(*Pane) = .empty,
    next_id: u64 = 1,

    /// Counters that let tests assert the IPC layer called through to the host.
    create_calls: usize = 0,
    write_calls: usize = 0,
    close_calls: usize = 0,

    /// When true, every create fails with `error.Unsupported`, which is how the
    /// tests cover a runtime that cannot split.
    refuse_create: bool = false,
    /// Pane ceiling enforced by the host, on top of the manager's own.
    max_panes: usize = std.math.maxInt(usize),

    pub fn init(gpa: Allocator) FakeHost {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *FakeHost) void {
        for (self.panes.items) |p| {
            p.text.deinit(self.gpa);
            self.gpa.destroy(p);
        }
        self.panes.deinit(self.gpa);
    }

    pub fn host(self: *FakeHost) pane.Host {
        return .{ .ctx = self, .vtable = &vtable };
    }

    pub fn find(self: *FakeHost, id: PaneId) ?*Pane {
        for (self.panes.items) |p| {
            if (p.id == id.raw) return p;
        }
        return null;
    }

    /// Drop a pane the way the runtime would when the child exits, without
    /// telling the IPC layer.
    pub fn dropPane(self: *FakeHost, id: PaneId) void {
        for (self.panes.items, 0..) |p, i| {
            if (p.id != id.raw) continue;
            p.text.deinit(self.gpa);
            self.gpa.destroy(p);
            _ = self.panes.swapRemove(i);
            return;
        }
    }

    /// Add a pane directly, bypassing the IPC surface.
    pub fn addPane(self: *FakeHost) !*Pane {
        const p = try self.gpa.create(Pane);
        p.* = .{ .id = self.next_id, .pid = @intCast(4000 + self.next_id) };
        self.next_id += 1;
        try self.panes.append(self.gpa, p);
        return p;
    }

    // ── VTable implementation ──

    const vtable: pane.Host.VTable = .{
        .create = create,
        .close = close,
        .focus = focus,
        .list = list,
        .write = write,
        .snapshot = snapshot,
        .search = search,
        .resize = resize,
        .equalize = equalize,
        .zoom = zoom,
    };

    fn create(ctx: *anyopaque, arena: Allocator, req: pane.CreateRequest) pane.HostError!pane.PaneHandle {
        const self: *FakeHost = @ptrCast(@alignCast(ctx));
        self.create_calls += 1;
        if (self.refuse_create) return error.Unsupported;
        if (self.panes.items.len >= self.max_panes) return error.TooManyPanes;

        const created = try self.addPane();
        created.cols = 80;
        created.rows = 24;
        if (req.cwd) |cwd| created.setCwd(cwd);
        if (req.title) |title| created.setTitle(title);
        if (req.focus) {
            for (self.panes.items) |p| p.focused = false;
            created.focused = true;
        }

        return .{
            .id = PaneId.init(created.id),
            .pid = created.pid,
            .title = if (created.titleSlice().len > 0)
                try arena.dupe(u8, created.titleSlice())
            else
                null,
            .cols = created.cols,
            .rows = created.rows,
            .focused = created.focused,
        };
    }

    fn close(ctx: *anyopaque, id: PaneId) pane.HostError!void {
        const self: *FakeHost = @ptrCast(@alignCast(ctx));
        self.close_calls += 1;
        for (self.panes.items, 0..) |p, i| {
            if (p.id != id.raw) continue;
            p.text.deinit(self.gpa);
            self.gpa.destroy(p);
            _ = self.panes.swapRemove(i);
            return;
        }
        return error.PaneNotFound;
    }

    fn focus(ctx: *anyopaque, id: PaneId) pane.HostError!void {
        const self: *FakeHost = @ptrCast(@alignCast(ctx));
        const target = self.find(id) orelse return error.PaneNotFound;
        for (self.panes.items) |p| p.focused = false;
        target.focused = true;
    }

    fn list(
        ctx: *anyopaque,
        arena: Allocator,
        out: *std.ArrayListUnmanaged(pane.PaneInfo),
    ) pane.HostError!void {
        const self: *FakeHost = @ptrCast(@alignCast(ctx));
        for (self.panes.items) |p| {
            try out.append(self.gpa, .{
                .id = PaneId.init(p.id),
                .title = try arena.dupe(u8, p.titleSlice()),
                .pid = p.pid,
                .cwd = if (p.cwdSlice().len > 0) try arena.dupe(u8, p.cwdSlice()) else null,
                .cols = p.cols,
                .rows = p.rows,
                .focused = p.focused,
                .exited = p.exited,
            });
        }
    }

    fn write(ctx: *anyopaque, id: PaneId, data: []const u8) pane.HostError!usize {
        const self: *FakeHost = @ptrCast(@alignCast(ctx));
        self.write_calls += 1;
        const target = self.find(id) orelse return error.PaneNotFound;
        return target.feed(self.gpa, data) catch return error.Internal;
    }

    fn snapshot(ctx: *anyopaque, arena: Allocator, id: PaneId, out: *state.Snapshot) pane.HostError!void {
        const self: *FakeHost = @ptrCast(@alignCast(ctx));
        const p = self.find(id) orelse return error.PaneNotFound;
        out.* = .{
            .pane_id = PaneId.init(p.id),
            .title = try arena.dupe(u8, p.titleSlice()),
            .pid = p.pid,
            .cwd = if (p.cwdSlice().len > 0) try arena.dupe(u8, p.cwdSlice()) else null,
            .size = .{ .cols = p.cols, .rows = p.rows },
            .cursor = .{
                .row = p.cursor_row,
                .col = p.cursor_col,
                .visible = true,
                .style = .block,
                .blinking = p.cursor_blink,
            },
            .alt_screen = p.alt_screen,
            .focused = p.focused,
            .mouse_tracking = p.mouse_tracking,
            .bell_count = p.bell_count,
            .scrollback_rows = 0,
            .viewport_rows = p.rows,
            .exited = p.exited,
            .exit_code = p.exit_code,
        };
    }

    fn search(
        ctx: *anyopaque,
        arena: Allocator,
        id: PaneId,
        query: []const u8,
        limit: usize,
        out: *std.ArrayListUnmanaged(pane.SearchMatch),
    ) pane.HostError!void {
        const self: *FakeHost = @ptrCast(@alignCast(ctx));
        const p = self.find(id) orelse return error.PaneNotFound;
        if (query.len == 0) return;

        const text = p.text.items;
        var from: usize = 0;
        while (out.items.len < limit) {
            const idx = std.mem.indexOfPos(u8, text, from, query) orelse return;
            const line_start = if (std.mem.lastIndexOfScalar(u8, text[0..idx], '\n')) |nl| nl + 1 else 0;
            const row = std.mem.count(u8, text[0..line_start], "\n");
            try out.append(self.gpa, .{
                .row = @intCast(row),
                .col = @intCast(idx - line_start),
                .len = @intCast(query.len),
                .text = try arena.dupe(u8, text[idx .. idx + query.len]),
            });
            from = idx + query.len;
        }
    }

    fn resize(ctx: *anyopaque, id: PaneId, dir: protocol.Direction, amount: u16) pane.HostError!void {
        const self: *FakeHost = @ptrCast(@alignCast(ctx));
        const p = self.find(id) orelse return error.PaneNotFound;
        const delta = amount;
        switch (dir) {
            .left, .right => p.cols = if (dir == .left and p.cols > delta)
                p.cols - @as(u16, delta)
            else
                p.cols +| delta,
            .up, .down => p.rows = if (dir == .up and p.rows > delta)
                p.rows - @as(u16, delta)
            else
                p.rows +| delta,
        }
    }

    fn equalize(ctx: *anyopaque) pane.HostError!void {
        const self: *FakeHost = @ptrCast(@alignCast(ctx));
        var total: u32 = 0;
        for (self.panes.items) |p| total += p.cols;
        if (self.panes.items.len == 0) return;
        const each: u16 = @intCast(total / self.panes.items.len);
        for (self.panes.items) |p| p.cols = each;
    }

    fn zoom(ctx: *anyopaque, id: PaneId) pane.HostError!void {
        const self: *FakeHost = @ptrCast(@alignCast(ctx));
        const p = self.find(id) orelse return error.PaneNotFound;
        p.zoomed = !p.zoomed;
    }
};

/// One pane in the fake terminal.
pub const Pane = struct {
    id: u64,
    pid: ?u32 = null,
    cols: u16 = 80,
    rows: u16 = 24,
    cursor_row: u32 = 0,
    cursor_col: u32 = 0,
    cursor_blink: ?bool = true,
    focused: bool = false,
    exited: bool = false,
    exit_code: ?i32 = null,
    alt_screen: ?bool = false,
    mouse_tracking: ?bool = false,
    bell_count: ?u64 = 0,
    zoomed: bool = false,

    title_buf: [max_title_len]u8 = @splat(0),
    title_len: usize = 0,
    cwd_buf: [max_title_len]u8 = @splat(0),
    cwd_len: usize = 0,

    /// Printed text, with `\n` inserted at line breaks. Search scans this.
    text: std.ArrayListUnmanaged(u8) = .empty,

    const max_title_len = 255;

    pub fn titleSlice(self: *const Pane) []const u8 {
        return self.title_buf[0..self.title_len];
    }

    pub fn cwdSlice(self: *const Pane) []const u8 {
        return self.cwd_buf[0..self.cwd_len];
    }

    pub fn setTitle(self: *Pane, value: []const u8) void {
        const n = @min(value.len, max_title_len);
        @memcpy(self.title_buf[0..n], value[0..n]);
        self.title_len = n;
    }

    pub fn setCwd(self: *Pane, value: []const u8) void {
        const n = @min(value.len, max_title_len);
        @memcpy(self.cwd_buf[0..n], value[0..n]);
        self.cwd_len = n;
    }

    /// Feed VT bytes into the mini emulator.
    pub fn feed(self: *Pane, gpa: Allocator, bytes: []const u8) !usize {
        const Mode = enum { ground, esc, csi, osc, osc_esc };
        var mode: Mode = .ground;
        var param_buf: [32]u8 = undefined;
        var param_len: usize = 0;
        var osc_buf: [max_title_len]u8 = undefined;
        var osc_len: usize = 0;

        for (bytes) |b| switch (mode) {
            .ground => switch (b) {
                '\n' => {
                    try self.appendText(gpa, "\n");
                    self.cursor_row = @min(self.cursor_row + 1, self.rows - 1);
                    self.cursor_col = 0;
                },
                '\r' => self.cursor_col = 0,
                '\t' => self.cursor_col = @min(self.cursor_col + 8, self.cols - 1),
                0x08 => self.cursor_col -|= 1,
                0x07 => self.bell_count = (self.bell_count orelse 0) + 1,
                0x1b => mode = .esc,
                0x00...0x06, 0x0e...0x1a, 0x1c...0x1f, 0x7f => {},
                else => {
                    var buf: [4]u8 = undefined;
                    buf[0] = b;
                    try self.appendText(gpa, buf[0..1]);
                    self.cursor_col = @min(self.cursor_col + 1, self.cols - 1);
                    if (self.cursor_col == self.cols) self.cursor_col = self.cols - 1;
                },
            },
            .esc => switch (b) {
                '[' => {
                    param_len = 0;
                    mode = .csi;
                },
                ']' => {
                    osc_len = 0;
                    mode = .osc;
                },
                else => mode = .ground,
            },
            .csi => {
                if (b >= '0' and b <= '9' or b == ';' or b == '?') {
                    if (param_len < param_buf.len) {
                        param_buf[param_len] = b;
                        param_len += 1;
                    }
                    continue;
                }
                if (b < 0x40 or b > 0x7e) continue;
                self.applyCsi(param_buf[0..param_len], b);
                mode = .ground;
            },
            .osc => switch (b) {
                0x07 => {
                    self.applyOsc(osc_buf[0..osc_len]);
                    mode = .ground;
                },
                0x1b => mode = .osc_esc,
                else => {
                    if (osc_len < osc_buf.len) {
                        osc_buf[osc_len] = b;
                        osc_len += 1;
                    }
                },
            },
            .osc_esc => {
                self.applyOsc(osc_buf[0..osc_len]);
                mode = .ground;
            },
        };

        return bytes.len;
    }

    fn applyCsi(self: *Pane, params: []const u8, final: u8) void {
        var p0: u32 = 0;
        var p1: u32 = 0;
        var seen_sep = false;
        for (params) |c| {
            if (c == ';') {
                seen_sep = true;
                continue;
            }
            if (c < '0' or c > '9') continue;
            const digit: u32 = c - '0';
            if (seen_sep) {
                p1 = p1 *| 10 +| digit;
            } else {
                p0 = p0 *| 10 +| digit;
            }
        }

        switch (final) {
            'H', 'f' => {
                const row = if (p0 == 0) 0 else p0 - 1;
                const col = if (p1 == 0) 0 else p1 - 1;
                self.cursor_row = @min(row, self.rows - 1);
                self.cursor_col = @min(col, self.cols - 1);
            },
            'A' => self.cursor_row -|= @intCast(@min(p0, self.rows)),
            'B' => self.cursor_row = @min(self.cursor_row +| p0, self.rows - 1),
            'C' => self.cursor_col = @min(self.cursor_col +| p0, self.cols - 1),
            'D' => self.cursor_col -|= @intCast(@min(p0, self.cols)),
            'G' => self.cursor_col = @min(if (p0 == 0) 0 else p0 - 1, self.cols - 1),
            'd' => self.cursor_row = @min(if (p0 == 0) 0 else p0 - 1, self.rows - 1),
            'h' => if (std.mem.indexOf(u8, params, "?1049") != null) {
                self.alt_screen = true;
            } else if (std.mem.indexOf(u8, params, "?1000") != null or
                std.mem.indexOf(u8, params, "?1006") != null)
            {
                self.mouse_tracking = true;
            },
            'l' => if (std.mem.indexOf(u8, params, "?1049") != null) {
                self.alt_screen = false;
            },
            else => {},
        }
    }

    fn applyOsc(self: *Pane, payload: []const u8) void {
        if (payload.len < 2) return;
        const is_title = std.mem.startsWith(u8, payload, "0;") or
            std.mem.startsWith(u8, payload, "2;");
        if (!is_title) return;
        self.setTitle(payload[2..]);
    }

    fn appendText(self: *Pane, gpa: Allocator, bytes: []const u8) !void {
        if (self.text.items.len + bytes.len > max_text_bytes) return;
        try self.text.appendSlice(gpa, bytes);
    }
};
