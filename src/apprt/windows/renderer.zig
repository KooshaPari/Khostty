//! Software Direct2D/DirectWrite adapter. Consumes parsed VT state, not raw
//! escape sequences. The renderer must stay at a stable address after writeVT.
const std = @import("std");
const builtin = @import("builtin");
const Window = @import("Window.zig");
const api = @import("win32api.zig");
const Terminal = @import("../../terminal/Terminal.zig");
const Stream = @TypeOf(@as(*Terminal, undefined).vtStream());
const Native = opaque {};
extern fn khostty_text_new(Window.Hwnd, *?*Native) i32;
extern fn khostty_text_free(*Native) void;
extern fn khostty_text_resize(*Native, u32, u32) i32;
extern fn khostty_text_draw(*Native, [*]const u16, u32) i32;
extern fn khostty_text_glyph_probe(*Native, [*]const u16, u32, *u32, *u32) i32;

pub const Renderer = struct {
    alloc: std.mem.Allocator,
    hwnd: Window.Hwnd,
    native: *Native,
    terminal: Terminal,
    stream: ?Stream = null,
    hook: api.WindowHook = undefined,

    // HWND values are opaque handle IDs, not aligned pointers to SDK structs.
    fn nativeWindow(self: *const Renderer) api.c.HWND {
        return @ptrFromInt(@intFromPtr(self.hwnd));
    }

    pub fn attach(self: *Renderer) !void {
        self.hook = .{ .context = self, .callback = handleMessage };
        try api.bindHook(self.nativeWindow(), &self.hook);
        try self.invalidate();
    }

    fn handleMessage(context: *anyopaque, msg: api.c.UINT, wp: api.c.WPARAM, lp: api.c.LPARAM) ?api.c.LRESULT {
        const self: *Renderer = @ptrCast(@alignCast(context));
        switch (msg) {
            api.c.WM_PAINT => {
                self.renderFrame() catch |err| std.log.err("Windows paint failed: {s}", .{@errorName(err)});
                return 0;
            },
            api.c.WM_ERASEBKGND => return 1,
            api.c.WM_SIZE => {
                if (wp != api.c.SIZE_MINIMIZED) {
                    const packed_size: usize = @bitCast(lp);
                    self.resize(@as(u16, @truncate(packed_size)), @as(u16, @truncate(packed_size >> 16))) catch |err|
                        std.log.err("Windows resize failed: {s}", .{@errorName(err)});
                }
                return 0;
            },
            else => return null,
        }
    }

    pub fn init(alloc: std.mem.Allocator, hwnd: Window.Hwnd) !Renderer {
        var native: ?*Native = null;
        try check(khostty_text_new(hwnd, &native));
        const owned = native orelse return error.RendererInitializationFailed;
        errdefer khostty_text_free(owned);
        return .{
            .alloc = alloc,
            .hwnd = hwnd,
            .native = owned,
            .terminal = try Terminal.init(std.Io.Threaded.global_single_threaded.io(), alloc, .{ .cols = 80, .rows = 24 }),
        };
    }

    pub fn deinit(self: *Renderer) void {
        if (api.c.IsWindow(self.nativeWindow()) != 0) api.bindHook(self.nativeWindow(), null) catch {};
        if (self.stream) |*stream| stream.deinit();
        self.terminal.deinit(self.alloc);
        khostty_text_free(self.native);
    }

    /// Stateful parser preserves UTF-8 and escape sequences across PTY reads.
    pub fn writeVT(self: *Renderer, bytes: []const u8) !void {
        if (self.stream == null) self.stream = self.terminal.vtStream();
        self.stream.?.nextSlice(bytes);
        try self.invalidate();
    }

    pub fn snapshot(self: *Renderer) ![]const u8 {
        return self.terminal.screens.active.dumpStringAlloc(self.alloc, .{ .viewport = .{} });
    }

    pub fn renderFrame(self: *Renderer) !void {
        var paint: api.c.PAINTSTRUCT = undefined;
        _ = api.c.BeginPaint(self.nativeWindow(), &paint) orelse return error.BeginPaintFailed;
        defer _ = api.c.EndPaint(self.nativeWindow(), &paint);
        const text = try self.snapshot();
        defer self.alloc.free(text);
        const wide = try std.unicode.utf8ToUtf16LeAlloc(self.alloc, text);
        defer self.alloc.free(wide);
        try check(khostty_text_draw(self.native, wide.ptr, @intCast(wide.len)));
    }

    pub fn invalidate(self: *Renderer) !void {
        if (api.c.InvalidateRect(self.nativeWindow(), null, 0) == 0) return error.InvalidateFailed;
    }

    pub fn resize(self: *Renderer, width: u32, height: u32) !void {
        if (width == 0 or height == 0) return;
        const dpi = try api.dpi(self.nativeWindow());
        // Match the 16-DIP font's approximate fixed-cell geometry. Precise
        // per-font cell metrics and SGR styling are follow-up work.
        const cell_w = @max(1, 10 * dpi / 96);
        const cell_h = @max(1, 20 * dpi / 96);
        try self.terminal.resize(self.alloc, .{
            .cols = @intCast(@min(65535, @max(1, width / cell_w))),
            .rows = @intCast(@min(65535, @max(1, height / cell_h))),
        });
        try check(khostty_text_resize(self.native, width, height));
        try self.invalidate();
    }
};

fn check(hr: i32) !void {
    if (hr < 0) {
        std.log.err("DirectWrite/Direct2D HRESULT=0x{x}", .{@as(u32, @bitCast(hr))});
        return error.NativeRendererFailed;
    }
}

test "native renderer parses split VT and draws Unicode with software backend" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    try api.registerClass(api.windowProc);
    const hwnd = (try api.createWindow()).?;
    defer {
        _ = api.c.DestroyWindow(hwnd);
        var message: api.c.MSG = undefined;
        while (api.c.PeekMessageW(&message, null, 0, 0, api.c.PM_REMOVE) != 0) {}
    }
    var renderer = try Renderer.init(std.testing.allocator, @ptrCast(hwnd));
    defer renderer.deinit();
    try renderer.writeVT("\x1b[3");
    try renderer.writeVT("1mA界😀\x1b[0m\r\nB");
    const text = try renderer.snapshot();
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "A界😀") != null);
    try std.testing.expect(std.mem.indexOfScalar(u8, text, 0x1b) == null);
    try renderer.renderFrame();
    try renderer.resize(480, 300);
    try renderer.renderFrame();
    try renderer.resize(0, 0);
    const shell = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = &.{ "cmd.exe", "/d", "/c", "echo S3-shell-output" },
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
    });
    defer std.testing.allocator.free(shell.stdout);
    defer std.testing.allocator.free(shell.stderr);
    try std.testing.expect(shell.term == .exited and shell.term.exited == 0);
    try renderer.writeVT(shell.stdout);
    try renderer.renderFrame();
    const shell_text = try renderer.snapshot();
    defer std.testing.allocator.free(shell_text);
    try std.testing.expect(std.mem.indexOf(u8, shell_text, "S3-shell-output") != null);
    const probe_text = std.unicode.utf8ToUtf16LeStringLiteral("A界😀");
    var missing: u32 = 0;
    var runs: u32 = 0;
    try check(khostty_text_glyph_probe(renderer.native, probe_text, probe_text.len, &missing, &runs));
    try std.testing.expect(runs > 0);
    try std.testing.expectEqual(@as(u32, 0), missing);
    const absent = std.unicode.utf8ToUtf16LeStringLiteral("\u{10FFFF}");
    try check(khostty_text_glyph_probe(renderer.native, absent, absent.len, &missing, &runs));
    try std.testing.expect(missing > 0);
}
