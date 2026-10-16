//! Native Windows application lifecycle. Terminal Surface integration is pending.
const App = @This();
const std = @import("std");
const api = @import("win32api.zig");
const CoreApp = @import("../../App.zig");
const ipc = @import("../../apprt.zig").ipc;
const Renderer = @import("renderer.zig").Renderer;

hwnd: api.c.HWND = null,
previous_dpi: api.c.DPI_AWARENESS_CONTEXT = null,
renderer: ?Renderer = null,
const wake_message = api.c.WM_APP + 1;

pub fn init(self: *App, core: *CoreApp, _: struct {}) !void {
    self.* = .{};
    self.previous_dpi = try api.enablePerMonitorDpi();
    errdefer {
        _ = api.c.SetThreadDpiAwarenessContext(self.previous_dpi);
        self.previous_dpi = null;
    }
    try self.registerWindowClass();
    self.hwnd = try api.createWindow();
    errdefer {
        _ = api.c.DestroyWindow(self.hwnd);
        self.hwnd = null;
    }
    self.renderer = try Renderer.init(core.alloc, @ptrCast(self.hwnd.?));
    errdefer {
        self.renderer.?.deinit();
        self.renderer = null;
    }
    try self.renderer.?.attach();
}

pub fn registerWindowClass(_: *App) !void {
    try api.registerClass(api.windowProc);
}

pub fn run(self: *App) !void {
    const hwnd = self.hwnd orelse return error.WindowNotInitialized;
    _ = api.c.ShowWindow(hwnd, api.c.SW_SHOW);
    // UpdateWindow returns zero when no update region exists, not just on error.
    _ = api.c.UpdateWindow(hwnd);
    var msg: api.c.MSG = undefined;
    while (try api.nextMessage(&msg)) {
        _ = api.c.TranslateMessage(&msg);
        _ = api.c.DispatchMessageW(&msg);
    }
    if (api.c.IsWindow(hwnd) == 0) self.hwnd = null;
}

pub fn terminate(self: *App) void {
    if (self.renderer) |*renderer| {
        renderer.deinit();
        self.renderer = null;
    }
    if (self.hwnd) |hwnd| {
        if (api.c.IsWindow(hwnd) != 0 and api.c.DestroyWindow(hwnd) == 0)
            std.log.err("DestroyWindow failed: {d}", .{api.c.GetLastError()});
    }
    self.hwnd = null;
    if (self.previous_dpi) |previous| {
        _ = api.c.SetThreadDpiAwarenessContext(previous);
        self.previous_dpi = null;
    }
}

pub fn wakeup(self: *App) void {
    if (self.hwnd) |hwnd| api.post(hwnd, wake_message) catch |err|
        std.log.err("Windows wakeup failed: {s}", .{@errorName(err)});
}
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
