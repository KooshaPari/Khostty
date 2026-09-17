//! Windows application lifecycle scaffold. Native initialization is unavailable.
const App = @This();
const CoreApp = @import("../../App.zig");
const ipc = @import("../../apprt.zig").ipc;

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

/// Errors that a runtime able to build an executable may return from
/// `performIpc`.
///
/// `src/cli/new_window.zig`, `src/cli/new_tab.zig` and
/// `src/cli/toggle_quick_terminal.zig` all `switch` on the caught error and
/// name `error.IPCFailed`, so a runtime that produces the `ghostty` executable
/// must declare that member. `src/apprt/embedded.zig` does the same by naming
/// `apprt.ipc.Errors` in its return type. Narrowing this set to only the errors
/// this scaffold actually returns breaks every one of those call sites.
pub const PerformIpcError = ipc.Errors || error{
    /// No Win32 transport exists yet, so no IPC can be attempted.
    Unimplemented,
};

pub fn performIpc(
    _: @import("std").mem.Allocator,
    _: ipc.Target,
    comptime action: ipc.Action.Key,
    _: ipc.Action.Value(action),
) PerformIpcError!bool {
    return error.Unimplemented;
}

/// Inspector UI is unavailable in the scaffold.
pub fn redrawInspector(_: *App, _: *@import("surface.zig")) void {}
