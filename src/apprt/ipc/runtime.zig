//! Experimental native lifecycle owner for the JSON agent IPC server.
//!
//! K-E02 deliberately keeps this opt-in. The server is not part of the inherited
//! Ghostty apprt.ipc module; it owns a separate authenticated Unix socket and must
//! be started/stopped with the real GTK application lifetime.

const std = @import("std");
const Allocator = std.mem.Allocator;

const apprt = @import("../../apprt.zig");
const global = @import("../../global.zig");
const authpkg = @import("auth.zig");
const events = @import("events.zig");
const pane = @import("pane.zig");
const serverpkg = @import("server.zig");
const apphostpkg = @import("app_host.zig");

pub const enable_env = "KHOSTTY_AGENT_IPC";

pub fn enabled() bool {
    const value = authpkg.Env.process().get(enable_env) orelse return false;
    return std.ascii.eqlIgnoreCase(value, "1") or
        std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "yes");
}

/// Heap allocated because Manager/Server hold pointers into sibling fields.
pub const Runtime = struct {
    gpa: Allocator,
    io: std.Io,
    host: apphostpkg.AppHost,
    broker: events.Broker,
    manager: pane.Manager,
    auth_setup: authpkg.Setup,
    server: serverpkg.Server,

    pub fn create(app: *apprt.App) !*Runtime {
        const gpa = global.alloc();
        const io = global.io();
        const self = try gpa.create(Runtime);
        errdefer gpa.destroy(self);

        self.gpa = gpa;
        self.io = io;
        self.host = apphostpkg.AppHost.init(gpa, io, app);
        self.broker = events.Broker.init(gpa);
        errdefer self.broker.deinit(io);

        self.manager = pane.Manager.init(gpa, self.host.host());
        errdefer self.manager.deinit(io);

        self.host.setEventBroker(&self.broker);
        self.manager.setEventBroker(&self.broker);

        self.auth_setup = try authpkg.setup(gpa, io, authpkg.Env.process());
        errdefer self.auth_setup.deinit();

        self.server = try serverpkg.Server.bind(
            gpa,
            io,
            .{ .socket_path = self.auth_setup.paths.socket },
            .{
                .manager = &self.manager,
                .broker = &self.broker,
                .authenticator = &self.auth_setup.auth,
            },
        );
        errdefer self.server.deinit();

        try self.server.start();
        return self;
    }

    pub fn deinit(self: *Runtime) void {
        self.server.deinit();
        self.manager.setEventBroker(null);
        self.host.setEventBroker(null);
        self.manager.deinit(self.io);
        self.broker.deinit(self.io);
        self.auth_setup.deinit();
        const gpa = self.gpa;
        self.* = undefined;
        gpa.destroy(self);
    }

    pub fn socketPath(self: *const Runtime) []const u8 {
        return self.auth_setup.paths.socket;
    }

    pub fn token(self: *const Runtime) ?[]const u8 {
        return self.auth_setup.auth.token();
    }
};

test "agent IPC runtime is opt-in" {
    // Unit tests do not mutate process environment. The real lifecycle test
    // runs the GTK binary with KHOSTTY_AGENT_IPC=1.
    try std.testing.expect(!enabled() or authpkg.Env.process().get(enable_env) != null);
}
