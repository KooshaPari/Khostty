/// This is the main entrypoint to the apprt for Ghostty. Ghostty will
/// initialize this in main to start the application..
const App = @This();

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const apprt = @import("../../apprt.zig");
const configpkg = @import("../../config.zig");
const Config = configpkg.Config;
const CoreApp = @import("../../App.zig");

const Application = @import("class/application.zig").Application;
const Surface = @import("Surface.zig");
const ipcNewWindow = @import("ipc/new_window.zig").newWindow;
const ipcNewTab = @import("ipc/new_tab.zig").newTab;
const ipcToggleQuickTerminal = @import("ipc/toggle_quick_terminal.zig").toggleQuickTerminal;
const AgentIpcRuntime = @import("../ipc/runtime.zig").Runtime;
const agentIpcEnabled = @import("../ipc/runtime.zig").enabled;

const log = std.log.scoped(.gtk);

/// GTK application ID
pub const application_id = @import("build/info.zig").application_id;

/// GTK object path
pub const object_path = @import("build/info.zig").object_path;

/// The GObject Application instance
app: *Application,

/// Experimental K-E02 agent-control server. Separate from inherited apprt.ipc.
agent_ipc: ?*AgentIpcRuntime = null,

pub fn init(
    self: *App,
    core_app: *CoreApp,

    // Required by the apprt interface but we don't use it.
    opts: struct {},
) !void {
    _ = opts;

    const app: *Application = try .new(self, core_app);
    errdefer app.unref();
    self.* = .{ .app = app };

    if (agentIpcEnabled()) {
        self.agent_ipc = AgentIpcRuntime.create(self) catch |err| ipc_err: {
            log.err("agent IPC requested but failed to start: {}", .{err});
            break :ipc_err null;
        };
        if (self.agent_ipc) |ipc| {
            log.info("agent IPC listening on {s}", .{ipc.socketPath()});
        }
    }
    return;
}

pub fn run(self: *App) !void {
    try self.app.run();
}

pub fn terminate(self: *App) void {
    if (self.agent_ipc) |ipc| {
        ipc.deinit();
        self.agent_ipc = null;
    }

    // We force deinitialize the app. We don't unref because other things
    // tend to have a reference at this point, so this just forces the
    // disposal now.
    self.app.deinit();
}

/// Called by CoreApp to wake up the event loop.
pub fn wakeup(self: *App) void {
    self.app.wakeup();
}

pub fn performAction(
    self: *App,
    target: apprt.Target,
    comptime action: apprt.Action.Key,
    value: apprt.Action.Value(action),
) !bool {
    return try self.app.performAction(target, action, value);
}

/// Send the given IPC to a running Ghostty. Returns `true` if the action was
/// able to be performed, `false` otherwise.
///
/// Note that this is a static function. Since this is called from a CLI app (or
/// some other process that is not Ghostty) there is no full-featured apprt App
/// to use.
pub fn performIpc(
    alloc: Allocator,
    target: apprt.ipc.Target,
    comptime action: apprt.ipc.Action.Key,
    value: apprt.ipc.Action.Value(action),
) !bool {
    switch (action) {
        .new_window => return try ipcNewWindow(alloc, target, value),
        .new_tab => return try ipcNewTab(alloc, target, value),
        .toggle_quick_terminal => return try ipcToggleQuickTerminal(alloc, target),
    }
}

/// Redraw the inspector for the given surface.
pub fn redrawInspector(_: *App, surface: *Surface) void {
    surface.redrawInspector();
}
