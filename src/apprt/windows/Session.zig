//! A UI-thread terminal session: encoder -> ConPTY -> VT parser -> renderer.
const Session = @This();
const std = @import("std");
const api = @import("win32api.zig");
const Window = @import("Window.zig");
const Renderer = @import("renderer.zig").Renderer;
const Bridge = @import("input_bridge.zig").Bridge;
const pty = @import("conpty.zig");
const paste = @import("../../input/paste.zig");
const Size = @import("../../renderer/size.zig").Size;

renderer: Renderer,
child: *pty.Pty,
bridge: Bridge = .{},
hook: api.WindowHook = undefined,
timer: bool = false,
suppress_paste_char: bool = false,

pub fn init(alloc: std.mem.Allocator, window_handle: Window.Hwnd) !Session {
    var renderer = try Renderer.init(alloc, window_handle);
    errdefer renderer.deinit();
    renderer.terminal.flags.resize_pull_scrollback = false;
    return .{ .renderer = renderer, .child = try pty.create(80, 24, null) };
}
fn hwnd(self: *Session) api.c.HWND {
    return @ptrFromInt(@intFromPtr(self.renderer.hwnd));
}
pub fn attach(self: *Session) !void {
    self.hook = .{ .context = self, .callback = dispatch };
    try api.bindHook(self.hwnd(), &self.hook);
    errdefer api.bindHook(self.hwnd(), null) catch {};
    const geometry = try self.size();
    try self.renderer.resize(geometry.screen.width, geometry.screen.height);
    try pty.resize(self.child, @intCast(@min(32767, self.renderer.terminal.cols)), @intCast(@min(32767, self.renderer.terminal.rows)));
    if (api.c.SetTimer(self.hwnd(), 1, 16, null) == 0) return error.TimerFailed;
    self.timer = true;
    try self.renderer.invalidate();
}
pub fn deinit(self: *Session) void {
    if (api.c.IsWindow(self.hwnd()) != 0) {
        if (self.timer) _ = api.c.KillTimer(self.hwnd(), 1);
        api.bindHook(self.hwnd(), null) catch |err| std.log.err("Window detach: {s}", .{@errorName(err)});
    }
    pty.close(self.child) catch |err| std.log.err("ConPTY cleanup: {s}", .{@errorName(err)});
    self.renderer.deinit();
}
fn size(self: *Session) !Size {
    var rect: api.c.RECT = undefined;
    if (api.c.GetClientRect(self.hwnd(), &rect) == 0) return error.WindowSizeFailed;
    const dpi = try api.dpi(self.hwnd());
    return .{
        .screen = .{ .width = @intCast(@max(0, rect.right)), .height = @intCast(@max(0, rect.bottom)) },
        .cell = .{ .width = @max(1, 10 * dpi / 96), .height = @max(1, 20 * dpi / 96) },
        .padding = .{},
    };
}
fn drain(self: *Session) !void {
    // Bounded work per UI tick; the native reader continues draining the OS pipe.
    for (0..16) |_| {
        var bytes: [4096]u8 = undefined;
        const len = try pty.read(self.child, &bytes);
        if (len == 0) break;
        try self.renderer.writeVT(bytes[0..len]);
    }
    if (!pty.alive(self.child)) try api.post(self.hwnd(), api.c.WM_CLOSE);
}
fn down(key: c_int) bool {
    return api.c.GetKeyState(key) < 0;
}
fn syncModifiers(self: *Session) void {
    const mods = &self.bridge.router.mods;
    mods.ctrl_left = down(api.c.VK_LCONTROL);
    mods.ctrl_right = down(api.c.VK_RCONTROL);
    mods.alt_left = down(api.c.VK_LMENU);
    mods.alt_right = down(api.c.VK_RMENU);
    mods.shift_left = down(api.c.VK_LSHIFT);
    mods.shift_right = down(api.c.VK_RSHIFT);
    mods.win_left = down(api.c.VK_LWIN);
    mods.win_right = down(api.c.VK_RWIN);
    mods.caps_lock = (api.c.GetKeyState(api.c.VK_CAPITAL) & 1) != 0;
    mods.num_lock = (api.c.GetKeyState(api.c.VK_NUMLOCK) & 1) != 0;
}
pub fn pasteBytes(self: *Session, data: []u8) !void {
    const slices = paste.encode(data, .fromTerminal(&self.renderer.terminal));
    var out: std.Io.Writer.Allocating = .init(self.renderer.alloc);
    defer out.deinit();
    for (slices) |slice| try out.writer.writeAll(slice);
    // Queue the complete frame atomically so failure cannot strand a prefix.
    try pty.write(self.child, out.written());
}
fn pasteClipboard(self: *Session) !void {
    const wide = try api.clipboardText(self.renderer.alloc, self.hwnd());
    defer self.renderer.alloc.free(wide);
    if (wide.len > 1024 * 1024) return error.PasteTooLarge;
    const utf8 = try std.unicode.utf16LeToUtf8Alloc(self.renderer.alloc, wide);
    defer self.renderer.alloc.free(utf8);
    try self.pasteBytes(utf8);
}
fn dispatch(context: *anyopaque, msg: api.c.UINT, wp: api.c.WPARAM, lp: api.c.LPARAM) ?api.c.LRESULT {
    const self: *Session = @ptrCast(@alignCast(context));
    return self.message(msg, wp, lp) catch |err| {
        std.log.err("Windows session message 0x{x}: {s}", .{ msg, @errorName(err) });
        api.post(self.hwnd(), api.c.WM_CLOSE) catch {};
        return 0;
    };
}
fn message(self: *Session, msg: api.c.UINT, wp: api.c.WPARAM, lp: api.c.LPARAM) !?api.c.LRESULT {
    if (msg == api.c.WM_TIMER and wp == 1) {
        try self.drain();
        return 0;
    }
    if (msg == api.c.WM_UNICHAR and wp == 0xffff) return 1;
    if (msg == api.c.WM_KILLFOCUS) {
        self.bridge.router.reset();
        self.bridge.router.mods = .{};
        return null;
    }
    if (msg == api.c.WM_SYSKEYDOWN and wp == api.c.VK_F4 and down(api.c.VK_MENU)) return null;
    if (msg == api.c.WM_CHAR and wp == 0x16 and self.suppress_paste_char) {
        self.suppress_paste_char = false;
        return 0;
    }
    if (msg == api.c.WM_KEYUP and wp == 'V') self.suppress_paste_char = false;
    const key_message = msg >= api.c.WM_KEYDOWN and msg <= api.c.WM_UNICHAR;
    const mouse_message = msg >= api.c.WM_MOUSEMOVE and msg <= api.c.WM_MOUSEHWHEEL;
    if (key_message or mouse_message) {
        self.syncModifiers();
        const paste_hotkey = msg == api.c.WM_KEYDOWN and
            ((wp == 'V' and down(api.c.VK_CONTROL) and down(api.c.VK_SHIFT)) or (wp == api.c.VK_INSERT and down(api.c.VK_SHIFT)));
        if (paste_hotkey) {
            self.suppress_paste_char = wp == 'V';
            self.pasteClipboard() catch |err| std.log.warn("Clipboard paste: {s}", .{@errorName(err)});
            return 0;
        }
        if (msg == api.c.WM_LBUTTONDOWN or msg == api.c.WM_MBUTTONDOWN or msg == api.c.WM_RBUTTONDOWN or msg == api.c.WM_XBUTTONDOWN) {
            _ = api.c.SetCapture(self.hwnd());
            if (api.c.GetCapture() != self.hwnd()) return error.MouseCaptureFailed;
        }
        if ((msg == api.c.WM_LBUTTONUP or msg == api.c.WM_MBUTTONUP or msg == api.c.WM_RBUTTONUP or msg == api.c.WM_XBUTTONUP) and
            (wp & 0x73) == 0 and api.c.GetCapture() == self.hwnd())
            _ = api.c.ReleaseCapture();
        if (msg == api.c.WM_MOUSEWHEEL or msg == api.c.WM_MOUSEHWHEEL) {
            const bits: usize = @bitCast(lp);
            var point: api.c.POINT = .{ .x = @as(i16, @bitCast(@as(u16, @truncate(bits)))), .y = @as(i16, @bitCast(@as(u16, @truncate(bits >> 16)))) };
            if (api.c.ScreenToClient(self.hwnd(), &point) == 0) return error.MousePositionFailed;
            self.bridge.pos = .{ .x = @floatFromInt(point.x), .y = @floatFromInt(point.y) };
        }
        const bytes = try self.bridge.message(self.renderer.alloc, &self.renderer.terminal, self.renderer.hwnd, try self.size(), msg, wp, lp);
        defer self.renderer.alloc.free(bytes);
        if (bytes.len > 0) try pty.write(self.child, bytes);
        return 0;
    }
    const result = Renderer.handleMessage(&self.renderer, msg, wp, lp);
    if (msg == api.c.WM_SIZE and wp != api.c.SIZE_MINIMIZED) {
        try pty.resize(self.child, @intCast(@min(32767, self.renderer.terminal.cols)), @intCast(@min(32767, self.renderer.terminal.rows)));
    }
    return result;
}
