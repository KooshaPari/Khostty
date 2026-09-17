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

/// Event-loop delivery is unavailable until the native message pump exists.
pub fn wakeup(_: *App) void {}

pub fn performAction(
    _: *App,
    _: @import("../../apprt.zig").Target,
    comptime action: @import("../../apprt.zig").Action.Key,
    _: @import("../../apprt.zig").Action.Value(action),
) error{Unimplemented}!bool {
    return error.Unimplemented;
}

pub fn performIpc(
    _: @import("std").mem.Allocator,
    _: @import("../../apprt.zig").ipc.Target,
    comptime action: @import("../../apprt.zig").ipc.Action.Key,
    _: @import("../../apprt.zig").ipc.Action.Value(action),
) error{Unimplemented}!bool {
    return error.Unimplemented;
}

/// Inspector UI is unavailable in the scaffold.
pub fn redrawInspector(_: *App, _: *@import("surface.zig")) void {}
