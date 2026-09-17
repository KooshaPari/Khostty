//! Window ownership placeholder. Never manufactures a native handle.
const Window = @This();

/// Opaque until the Win32 declarations are introduced.
pub const Hwnd = *opaque {};
hwnd: ?Hwnd = null,

pub fn init() !Window {
    return error.Unimplemented;
}

pub fn handle(self: *const Window) ?Hwnd {
    return self.hwnd;
}

/// No native resources can be acquired by this scaffold.
pub fn deinit(_: *Window) void {}

test "Windows scaffold has no native window" {
    const std = @import("std");
    const window: Window = .{};
    try std.testing.expectEqual(null, window.handle());
    try std.testing.expectError(error.Unimplemented, Window.init());
}
