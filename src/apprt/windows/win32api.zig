//! Checked Win32 operations for the native application runtime.
const std = @import("std");
pub const c = @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cInclude("windows.h");
});
pub const HWND = c.HWND;
pub const Error = error{ RegisterClassFailed, CreateWindowFailed, MessageLoopFailed, DpiFailed, PositionFailed, ClipboardBusy, ClipboardUnavailable, ClipboardLockFailed, ClipboardCloseFailed, InvalidClipboard, PostFailed };
pub const class_name = std.unicode.utf8ToUtf16LeStringLiteral("Khostty.Native.Window");
const title = std.unicode.utf8ToUtf16LeStringLiteral("Khostty");

/// Awareness is scoped to the UI thread and restored by the owner.
pub fn enablePerMonitorDpi() Error!c.DPI_AWARENESS_CONTEXT {
    return c.SetThreadDpiAwarenessContext(c.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) orelse error.DpiFailed;
}

pub fn registerClass(proc: c.WNDPROC) Error!void {
    const instance = c.GetModuleHandleW(null) orelse return error.RegisterClassFailed;
    var wc: c.WNDCLASSEXW = std.mem.zeroes(c.WNDCLASSEXW);
    wc.cbSize = @sizeOf(c.WNDCLASSEXW);
    wc.style = c.CS_HREDRAW | c.CS_VREDRAW;
    wc.lpfnWndProc = proc;
    wc.hInstance = instance;
    wc.lpszClassName = class_name;
    // A class is process-scoped; repeat registration must not silently adopt
    // a class with a different callback.
    if (c.RegisterClassExW(&wc) == 0) {
        if (c.GetLastError() != c.ERROR_CLASS_ALREADY_EXISTS) return error.RegisterClassFailed;
        var existing: c.WNDCLASSEXW = std.mem.zeroes(c.WNDCLASSEXW);
        existing.cbSize = @sizeOf(c.WNDCLASSEXW);
        if (c.GetClassInfoExW(instance, class_name, &existing) == 0 or existing.lpfnWndProc != proc)
            return error.RegisterClassFailed;
    }
}

pub fn createWindow() Error!c.HWND {
    const instance = c.GetModuleHandleW(null) orelse return error.CreateWindowFailed;
    return c.CreateWindowExW(0, class_name, title, c.WS_OVERLAPPEDWINDOW, c.CW_USEDEFAULT, c.CW_USEDEFAULT, 960, 640, null, null, instance, null) orelse error.CreateWindowFailed;
}

/// GetMessage has three outcomes: event, quit, and failure (-1).
pub fn nextMessage(msg: *c.MSG) Error!bool {
    const result = c.GetMessageW(msg, null, 0, 0);
    if (result == -1) return error.MessageLoopFailed;
    return result != 0;
}

pub fn dpi(hwnd: c.HWND) Error!u32 {
    const value = c.GetDpiForWindow(hwnd);
    if (value == 0) return error.DpiFailed;
    return value;
}

pub fn position(hwnd: c.HWND, rect: c.RECT) Error!void {
    if (c.SetWindowPos(hwnd, null, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top, c.SWP_NOZORDER | c.SWP_NOACTIVATE) == 0) return error.PositionFailed;
}

/// Copy clipboard text while the clipboard and movable-memory lock are held.
/// The returned UTF-16 is owned by the caller; no borrowed handle escapes.
pub fn clipboardText(alloc: std.mem.Allocator, hwnd: c.HWND) ![]u16 {
    if (c.OpenClipboard(hwnd) == 0) return error.ClipboardBusy;
    var opened = true;
    defer if (opened) {
        _ = c.CloseClipboard();
    };
    const handle = c.GetClipboardData(c.CF_UNICODETEXT) orelse return error.ClipboardUnavailable;
    const bytes = c.GlobalSize(handle);
    if (bytes < 2 or bytes % 2 != 0) return error.InvalidClipboard;
    const result = blk: {
        const raw = c.GlobalLock(handle) orelse return error.ClipboardLockFailed;
        defer _ = c.GlobalUnlock(handle);
        const data: [*]const u16 = @ptrCast(@alignCast(raw));
        const bounded = data[0 .. bytes / 2];
        const len = std.mem.indexOfScalar(u16, bounded, 0) orelse return error.InvalidClipboard;
        break :blk try alloc.dupe(u16, bounded[0..len]);
    };
    errdefer alloc.free(result);
    if (c.CloseClipboard() == 0) return error.ClipboardCloseFailed;
    opened = false;
    return result;
}

pub fn post(hwnd: c.HWND, message: c.UINT) Error!void {
    if (c.PostMessageW(hwnd, message, 0, 0) == 0) return error.PostFailed;
}

pub const WindowHook = struct {
    context: *anyopaque,
    callback: *const fn (*anyopaque, c.UINT, c.WPARAM, c.LPARAM) ?c.LRESULT,
};

pub fn bindHook(hwnd: c.HWND, hook: ?*WindowHook) !void {
    c.SetLastError(0);
    const value: c.LONG_PTR = if (hook) |ptr| @bitCast(@intFromPtr(ptr)) else 0;
    if (c.SetWindowLongPtrW(hwnd, c.GWLP_USERDATA, value) == 0 and c.GetLastError() != 0)
        return error.WindowHookFailed;
}

pub fn windowProc(hwnd: c.HWND, msg: c.UINT, wp: c.WPARAM, lp: c.LPARAM) callconv(.winapi) c.LRESULT {
    const stored = c.GetWindowLongPtrW(hwnd, c.GWLP_USERDATA);
    if (stored != 0) {
        const hook: *WindowHook = @ptrFromInt(@as(usize, @bitCast(stored)));
        if (hook.callback(hook.context, msg, wp, lp)) |result| return result;
    }
    switch (msg) {
        c.WM_CLOSE => {
            if (c.DestroyWindow(hwnd) == 0) return c.DefWindowProcW(hwnd, msg, wp, lp);
            return 0;
        },
        c.WM_DESTROY => {
            c.PostQuitMessage(0);
            return 0;
        },
        c.WM_DPICHANGED => {
            const rect: *const c.RECT = @ptrFromInt(@as(usize, @bitCast(lp)));
            position(hwnd, rect.*) catch |err| std.log.err("DPI resize failed: {s}", .{@errorName(err)});
            return 0;
        },
        else => return c.DefWindowProcW(hwnd, msg, wp, lp),
    }
}

test "native window class, DPI, positioning and close message loop" {
    const previous_dpi = try enablePerMonitorDpi();
    defer _ = c.SetThreadDpiAwarenessContext(previous_dpi);
    try registerClass(windowProc);
    try registerClass(windowProc);
    const hwnd = try createWindow();
    var destroyed = false;
    defer if (!destroyed) {
        _ = c.DestroyWindow(hwnd);
    };
    try std.testing.expect(try dpi(hwnd) > 0);
    try position(hwnd, .{ .left = 0, .top = 0, .right = 320, .bottom = 200 });
    try post(hwnd, c.WM_CLOSE);
    var msg: c.MSG = undefined;
    while (try nextMessage(&msg)) {
        _ = c.TranslateMessage(&msg);
        _ = c.DispatchMessageW(&msg);
    }
    destroyed = true;
    try std.testing.expect(c.IsWindow(hwnd) == 0);
    try std.testing.expectEqual(@as(usize, 0), msg.wParam);
    try std.testing.expectError(error.DpiFailed, dpi(null));
    try std.testing.expectError(error.PositionFailed, position(null, .{ .left = 0, .top = 0, .right = 1, .bottom = 1 }));
}

test "native clipboard read releases the clipboard without changing content" {
    // This reads no text into logs and never empties or writes the clipboard.
    if (clipboardText(std.testing.allocator, null)) |text| {
        defer std.testing.allocator.free(text);
        try std.testing.expect(std.mem.indexOfScalar(u16, text, 0) == null);
    } else |err| switch (err) {
        error.ClipboardUnavailable, error.ClipboardBusy => return error.SkipZigTest,
        else => return err,
    }
    try std.testing.expect(c.OpenClipboard(null) != 0);
    try std.testing.expect(c.CloseClipboard() != 0);
}
