//! Windows application lifecycle scaffold. Native initialization is unavailable.
const App = @This();
const CoreApp = @import("../../App.zig");

pub fn init(_: *App, _: *CoreApp, _: struct {}) !void {
    return error.Unimplemented;
}

/// Register the native window class in a later Windows runtime task.
pub fn registerWindowClass(_: *App) !void {
    return error.Unimplemented;
}

pub fn run(_: *App) !void {
    return error.Unimplemented;
}

/// No native resources can be acquired by this scaffold.
pub fn terminate(_: *App) void {}
