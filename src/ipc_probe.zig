//! Runtime probe for the agent IPC surface.
//!
//! FORK: KooshaPari/Khostty#48 (Phase B1 verification).
//!
//! Exists because "the server compiles" and "the server answers" are different
//! claims. This connects to a *running* app over the real socket and asserts
//! the handshake a client actually performs. CI launches the GTK app headless
//! and runs this against it.
//!
//! Usage: KHOSTTY_IPC_SOCKET=/path/to.sock ipc-probe
//! Exits 0 on success; prints the failure and exits non-zero otherwise.
//!
//! MUST be built with `-lc`. `authpkg.Env.process()` resolves to a getter that
//! returns nothing at all when libc is not linked, so a libc-free build reports
//! every variable as unset - which reads like a missing env var, not a build
//! configuration error.

const std = @import("std");
const ipc = @import("apprt/ipc/server.zig");
const authpkg = @import("apprt/ipc/auth.zig");

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var threaded: std.Io.Threaded = .init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const socket_path = authpkg.Env.process().get(authpkg.socket_env) orelse {
        std.debug.print("probe: {s} is not set\n", .{authpkg.socket_env});
        return error.MissingSocketEnv;
    };

    var client = try ipc.Client.connect(gpa, io, socket_path);
    defer client.deinit();
    std.debug.print("probe: connected to {s}\n", .{socket_path});

    // ── ping ──
    // Proves the accept loop is live, the frame parser works, and auth admits
    // the caller. This is the whole point: a bound socket that never answers
    // is indistinguishable from no socket at all.
    try client.send(.{ .id = 1, .cmd = .ping });
    var ping = try client.readResponse(gpa);
    defer ping.deinit();

    const obj = ping.value.object;
    if (obj.get("ok") == null or !obj.get("ok").?.bool) {
        const code = if (obj.get("error")) |e|
            (e.object.get("code") orelse e).string
        else
            "unknown";
        std.debug.print("probe: ping was not ok ({s})\n", .{code});
        return error.PingFailed;
    }
    const data = obj.get("data") orelse return error.MalformedResponse;
    const server_name = data.object.get("server") orelse return error.MalformedResponse;
    if (!std.mem.eql(u8, server_name.string, "khostty")) {
        std.debug.print("probe: unexpected server name '{s}'\n", .{server_name.string});
        return error.UnexpectedServer;
    }
    std.debug.print("probe: ping ok (server={s})\n", .{server_name.string});

    // `ping` is intentionally open, every other command needs the token, so
    // this is also the first real exercise of the auth path rather than just
    // of liveness.
    const token = authpkg.Env.process().get(authpkg.token_env);

    // ── pane.list ──
    // Proves the windowed vtable is reachable and can enumerate the app's live
    // surfaces. An `Unsupported` the whole way down would still pass `ping`,
    // so this is what separates "socket alive" from "agent surface usable".
    try client.send(.{ .id = 2, .cmd = .pane_list, .auth = token });
    var list = try client.readResponse(gpa);
    defer list.deinit();

    const lobj = list.value.object;
    if (lobj.get("ok") == null or !lobj.get("ok").?.bool) {
        const err_str = if (lobj.get("error")) |e|
            (e.object.get("code") orelse e).string
        else
            "unknown";
        std.debug.print("probe: pane.list failed: {s}\n", .{err_str});
        return error.PaneListFailed;
    }

    const panes = (lobj.get("data") orelse return error.MalformedResponse)
        .object.get("panes") orelse return error.MalformedResponse;
    std.debug.print("probe: pane.list ok ({d} pane(s))\n", .{panes.array.items.len});

    std.debug.print("probe: PASS\n", .{});
}
