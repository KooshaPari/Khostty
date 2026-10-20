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

// FORK: agent IPC. Only this runtime (`.exe` + `.gtk`) has `windowed == true`
// in src/apprt/ipc/app_host.zig, so this is the only place the IPC server can
// actually be bound. Tracking issue: KooshaPari/Khostty#48, Phase B1.
const ipc = @import("../ipc/mod.zig");
const ipc_app_host = @import("../ipc/app_host.zig");
const ipc_auth = @import("../ipc/auth.zig");
const ipc_events = @import("../ipc/events.zig");
const ipc_pane = @import("../ipc/pane.zig");
const ipc_server = @import("../ipc/server.zig");
const ipcNewTab = @import("ipc/new_tab.zig").newTab;
const ipcToggleQuickTerminal = @import("ipc/toggle_quick_terminal.zig").toggleQuickTerminal;

const log = std.log.scoped(.gtk);

/// GTK application ID
pub const application_id = @import("build/info.zig").application_id;

/// GTK object path
pub const object_path = @import("build/info.zig").object_path;

/// The GObject Application instance
app: *Application,

/// FORK: the agent-IPC server for this process, if it was started.
/// Heap-allocated so the Manager/Broker addresses the server holds stay
/// stable for the life of the app.
///
/// FORK: KooshaPari/Khostty#48 (Phase B1 - bind the server from a runtime).
ipc_runtime: ?*IpcRuntime = null,

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

    // FORK: bind the agent IPC server now that the runtime exists.
    //
    // Failure here must NOT prevent the terminal from starting: the fork's
    // promise is still "a usable terminal". A missing token, an unbindable
    // socket path, or a lost race with an existing instance degrades the agent
    // surface, not the app.
    self.ipc_runtime = startIpc(core_app) catch |err| blk: {
        log.warn("agent IPC not started: {s}", .{@errorName(err)});
        break :blk null;
    };
    return;
}

pub fn run(self: *App) !void {
    try self.app.run();
}

pub fn terminate(self: *App) void {
    // FORK: stop the agent IPC server before the runtime goes away, so no
    // connection thread outlives the surfaces it can address.
    if (self.ipc_runtime) |rt| {
        rt.deinit();
        self.ipc_runtime = null;
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

/// FORK: everything the agent-IPC server needs, owned for the app's lifetime.
///
/// Heap-allocated (not a plain field) because `ipc_server.Server` holds
/// pointers to `manager`, `broker` and `authenticator`; those addresses must
/// never move. Tracking issue: KooshaPari/Khostty#48 (Phase B1).
const IpcRuntime = struct {
    gpa: Allocator,
    io: std.Io,
    paths: ipc_auth.Paths,
    app_host: ipc_app_host.AppHost,
    manager: ipc_pane.Manager,
    broker: ipc_events.Broker,
    authenticator: ipc_auth.Auth,
    server: ipc_server.Server,

    fn deinit(self: *IpcRuntime) void {
        const gpa = self.gpa;
        self.server.stop();
        self.server.deinit();
        self.manager.deinit(self.io);
        self.broker.deinit(self.io);
        self.paths.deinit();
        self.authenticator.deinit();
        gpa.destroy(self);
    }
};

/// FORK: construct and start the agent-IPC server for this process.
///
/// The pieces are exactly what the test harness builds in
/// `ipc/server.zig`, except the pane host is the real runtime
/// (`AppHost`) rather than `fake_host.zig`.
fn startIpc(core_app: *CoreApp) !*IpcRuntime {
    const gpa = std.heap.c_allocator;
    const io = @import("../../global.zig").io();

    const self = try gpa.create(IpcRuntime);
    errdefer gpa.destroy(self);

    self.gpa = gpa;
    self.io = io;
    self.paths = try ipc_auth.resolvePaths(gpa, ipc_auth.Env.process());
    errdefer self.paths.deinit();

    self.broker = ipc_events.Broker.init(gpa);
    errdefer self.broker.deinit(io);

    // Token: env, else the token file beside the socket, else null. A null
    // token is the documented "not configured" state - every command except
    // `ping` is refused, which is the fail-closed default. It is NOT an
    // unauthenticated server.
    self.authenticator = try ipc_auth.Auth.init(gpa, try loadIpcToken(gpa, &self.paths));
    errdefer self.authenticator.deinit();

    // The real pane host: the same windowed vtable the tests exercise, backed
    // by this app's CoreApp instead of the fake surface list.
    self.app_host = ipc_app_host.AppHost.init(gpa, io, core_app);

    self.manager = ipc_pane.Manager.init(gpa, self.app_host.host());
    self.manager.setEventBroker(&self.broker);

    self.server = try ipc_server.Server.bind(gpa, io, .{
        .socket_path = self.paths.socket,
        // A stale socket from a previous run is normal; the bind replaces it.
        .replace_existing = true,
    }, .{
        .manager = &self.manager,
        .broker = &self.broker,
        .authenticator = &self.authenticator,
        // Unknown here; `ping` advertises null rather than a wrong pid.
        .server_pid = null,
    });
    errdefer self.server.deinit();

    try self.server.start();

    log.info("agent IPC listening on {s}", .{self.paths.socket});
    if (self.authenticator.token_buf == null) {
        log.warn(
            "agent IPC has no token configured (set {s} or write {s}); " ++
                "only `ping` will be accepted",
            .{ ipc_auth.token_env, self.paths.token_file },
        );
    }
    return self;
}

/// FORK: resolve the IPC token for this process: `KHOSTTY_IPC_TOKEN`, else the
/// token file, else null.
///
/// Ownership: the returned slice is owned by the caller (freed via
/// `Auth.deinit`, which copies it).
fn loadIpcToken(gpa: Allocator, paths: *const ipc_auth.Paths) !?[]const u8 {
    if (ipc_auth.Env.process().get(ipc_auth.token_env)) |t| return try gpa.dupe(u8, t);

    const file = std.fs.cwd().openFile(paths.token_file, .{}) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied, error.NotDir => return null,
        else => return err,
    };
    defer file.close();
    const buf = try file.readToEndAlloc(gpa, ipc_auth.max_token_file_bytes);
    return std.mem.trimEnd(u8, buf, &std.ascii.whitespace);
}
