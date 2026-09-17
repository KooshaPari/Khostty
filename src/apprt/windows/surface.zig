//! Windows rendering surface scaffold. Rendering and input are not implemented.
const Surface = @This();
const Window = @import("Window.zig");

window: Window = .{},

pub fn init() !Surface {
    return error.Unimplemented;
}

/// No native resources can be acquired by this scaffold.
pub fn deinit(_: *Surface) void {}

pub fn nativeWindow(self: *const Surface) ?Window.Hwnd {
    return self.window.handle();
}
