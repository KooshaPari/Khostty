//! HWND to borrowed Ghostty surface association. No native calls are made.
//!
//! The future window procedure looks up this wrapper by HWND and calls
//! handleMessage on the UI thread. WM_SIZE records client pixels, excluding
//! minimization. Terminal-grid resize notification is not implemented yet.
//! WM_PAINT returns null until BeginPaint/EndPaint and rendering exist, so
//! the caller MUST use DefWindowProcW to validate the update region.
//! WM_ERASEBKGND also returns null: never claim a background was erased
//! while rendering is unavailable. Close/destroy/input remain caller-owned.
//! GTK's analogous association is gtk/Surface.zig, not a native message pump.
const Surface = @This();
const std = @import("std");
const Window = @import("Window.zig");

pub const WM_SIZE: u32 = 0x0005;
pub const WM_PAINT: u32 = 0x000f;
pub const WM_ERASEBKGND: u32 = 0x0014;
pub const SIZE_MINIMIZED: usize = 1;

window: Window = .{},
/// Borrowed core Surface identity only. Never dereferenced or freed here.
/// A typed core bridge will be supplied when the Windows runtime is wired.
core_surface: ?*anyopaque = null,
width: u16 = 0,
height: u16 = 0,

/// Native window/core construction remains unavailable.
pub fn init() error{Unimplemented}!Surface {
    return error.Unimplemented;
}

/// Associate existing objects without creating native resources. The caller
/// keeps both objects alive and must clear the association before destruction.
pub fn attach(self: *Surface, hwnd: Window.Hwnd, core_surface: *anyopaque) void {
    self.window = .{ .hwnd = hwnd };
    self.core_surface = core_surface;
}

pub fn deinit(self: *Surface) void {
    self.* = .{};
}

pub fn nativeWindow(self: *const Surface) ?Window.Hwnd {
    return self.window.handle();
}

pub fn coreForWindow(self: *const Surface, hwnd: Window.Hwnd) ?*anyopaque {
    if (self.nativeWindow() != hwnd) return null;
    return self.core_surface;
}

/// null means unhandled, otherwise return the supplied LRESULT.
/// LPARAM is pointer-sized signed storage; decode its low 32 bits unsigned.
pub fn handleMessage(self: *Surface, msg: u32, wparam: usize, lparam: isize) ?isize {
    if (self.nativeWindow() == null) return null;
    switch (msg) {
        WM_SIZE => {
            if (wparam != SIZE_MINIMIZED) {
                const packed_size: usize = @bitCast(lparam);
                self.width = @truncate(packed_size);
                self.height = @truncate(packed_size >> 16);
            }
            return 0;
        },
        WM_PAINT => return if (self.paint()) 0 else null,
        WM_ERASEBKGND => return if (self.eraseBackground()) 1 else null,
        else => return null,
    }
}

/// GDI/Direct2D painting and invalidation are deliberately unavailable.
pub fn paint(_: *Surface) bool {
    return false;
}

pub fn eraseBackground(_: *Surface) bool {
    return false;
}

pub fn requestRender(_: *Surface) bool {
    return false;
}

test "Windows surface association and message routing" {
    const t = std.testing;
    var native: u8 = 0;
    var other: u8 = 0;
    var core_identity: u8 = 0;
    const hwnd: Window.Hwnd = @ptrCast(&native);
    var surface: Surface = .{};
    try t.expectError(error.Unimplemented, init());
    try t.expectEqual(null, surface.handleMessage(WM_SIZE, 0, 1));
    surface.attach(hwnd, &core_identity);
    try t.expectEqual(hwnd, surface.nativeWindow().?);
    try t.expectEqual(@as(*anyopaque, &core_identity), surface.coreForWindow(hwnd).?);
    try t.expectEqual(null, surface.coreForWindow(@ptrCast(&other)));
    try t.expectEqual(@as(?isize, 0), surface.handleMessage(WM_SIZE, 0, (600 << 16) | 800));
    try t.expectEqual(@as(u16, 800), surface.width);
    try t.expectEqual(@as(u16, 600), surface.height);
    _ = surface.handleMessage(WM_SIZE, SIZE_MINIMIZED, 0);
    try t.expectEqual(@as(u16, 800), surface.width);
    _ = surface.handleMessage(WM_SIZE, 0, -1);
    try t.expectEqual(@as(u16, 65535), surface.height);
    _ = surface.handleMessage(WM_SIZE, 0, 0);
    try t.expectEqual(@as(u16, 0), surface.width);
    for ([_]u32{ WM_PAINT, WM_ERASEBKGND, 0x0010, 0xffffffff }) |msg|
        try t.expectEqual(null, surface.handleMessage(msg, 0, 0));
    try t.expect(!surface.requestRender());
    surface.deinit();
    try t.expectEqual(null, surface.nativeWindow());
    try t.expectEqual(null, surface.coreForWindow(hwnd));
}
