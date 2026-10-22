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
const protocol = @import("apprt/ipc/protocol.zig");

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var threaded: std.Io.Threaded = .init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // Distinctive so a stale title from the running app cannot pass the check.
    const expected_title = "khostty-probe-title";

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

    // `pane.list` returns the pane array directly as `data`. Accept an object
    // with a `panes` key too so a change of envelope does not masquerade as a
    // failure - and check the tag before touching the union, because touching
    // the wrong arm panics rather than returning an error.
    const data_val = lobj.get("data") orelse return error.MalformedResponse;
    const panes_arr: []const std.json.Value = switch (data_val) {
        .array => |a| a.items,
        .object => |o| if (o.get("panes")) |p| switch (p) {
            .array => |a| a.items,
            else => return error.MalformedResponse,
        } else return error.MalformedResponse,
        else => return error.MalformedResponse,
    };
    std.debug.print("probe: pane.list ok ({d} pane(s))\n", .{panes_arr.len});

    // ── events: all four must actually arrive ──
    //
    // Everything above proves the command path. This proves the *event* path by
    // driving the surface through its own parser and waiting for the runtime to
    // publish the results back. Without it "events are wired" would be an
    // untested claim, which is the mistake this probe exists to stop.
    if (panes_arr.len > 0) {
        const pane_obj = panes_arr[0].object;
        const id_val = pane_obj.get("pane_id") orelse return error.MalformedResponse;
        const pane_id: protocol.PaneId = switch (id_val) {
            .integer => |n| protocol.PaneId.init(@intCast(n)),
            .string => |str| protocol.PaneId.parseString(str) orelse
                return error.MalformedResponse,
            else => return error.MalformedResponse,
        };

        try client.send(.{
            .id = 3,
            .cmd = .events_subscribe,
            .auth = token,
            .opts = .{ .events = &.{ .bell, .title_change, .resize, .child_exit } },
        });
        var sub = try client.readResponse(gpa);
        defer sub.deinit();
        if (sub.value.object.get("ok") == null or !sub.value.object.get("ok").?.bool) {
            std.debug.print("probe: events.subscribe failed\n", .{});
            return error.SubscribeFailed;
        }

        // One write carrying both triggers, through the surface's own parser -
        // the same bytes a program would write:
        //   BEL                 ring the bell
        //   ESC ] 0 ; <text> BEL set the window title (OSC 0)
        try client.send(.{
            .id = 4,
            .cmd = .pane_write,
            .auth = token,
            .pane_id = pane_id,
            .data = "\x07\x1b]0;" ++ expected_title ++ "\x07",
        });
        var wrote = try client.readResponse(gpa);
        defer wrote.deinit();
        if (wrote.value.object.get("ok") == null or !wrote.value.object.get("ok").?.bool) {
            std.debug.print("probe: pane.write failed\n", .{});
            return error.WriteFailed;
        }

        var saw_bell = false;
        var saw_title = false;
        while (!saw_bell or !saw_title) {
            const msg = try client.readMessage(gpa);
            defer msg.deinit();
            const obj2 = msg.value.object;
            const ev = obj2.get("event") orelse continue;
            if (!isPane(obj2, pane_id)) continue;

            if (std.mem.eql(u8, ev.string, "bell")) {
                std.debug.print("probe: bell event received for p-{d}\n", .{pane_id.raw});
                saw_bell = true;
                continue;
            }
            if (std.mem.eql(u8, ev.string, "title_change")) {
                const t = obj2.get("data") orelse continue;
                const title = t.object.get("title") orelse continue;
                if (!std.mem.eql(u8, title.string, expected_title)) {
                    std.debug.print(
                        "probe: title_change carried '{s}', expected '{s}'\n",
                        .{ title.string, expected_title },
                    );
                    return error.UnexpectedTitle;
                }
                std.debug.print("probe: title_change event received ('{s}')\n", .{title.string});
                saw_title = true;
            }
        }

        // ── resize: NOT driven here, deliberately ──
        //
        // The obvious trigger is a split (`pane.create`), but calling it aborts
        // the GTK runtime outright - it was never exercised before either. See
        // KooshaPari/Khostty#71. Driving a known crash inside a check that is
        // supposed to verify event delivery would confound the two, so resize
        // stays wired-but-unproven and the crash gets its own fix.
        std.debug.print(
            "probe: resize event NOT verified (pane.create aborts the app, #71)\n",
            .{},
        );

        // ── child_exit, by actually ending the child ──
        //
        // `exit` terminates the pane's shell, so the runtime sees a real child
        // exit rather than a synthetic one.
        try client.send(.{
            .id = 6,
            .cmd = .pane_write,
            .auth = token,
            .pane_id = pane_id,
            .data = "exit\n",
        });
        var exited_req = try client.readResponse(gpa);
        defer exited_req.deinit();

        while (true) {
            const msg = try client.readMessage(gpa);
            defer msg.deinit();
            const obj2 = msg.value.object;
            const ev = obj2.get("event") orelse continue;
            if (!std.mem.eql(u8, ev.string, "child_exit")) continue;
            const code = if (obj2.get("data")) |d|
                (d.object.get("exit_code") orelse d)
            else
                null;
            if (code != null and code.? == .integer) {
                std.debug.print(
                    "probe: child_exit event received (exit_code={d})\n",
                    .{code.?.integer},
                );
            } else {
                std.debug.print("probe: child_exit event received\n", .{});
            }
            break;
        }
    } else {
        std.debug.print("probe: no panes, skipping the event checks\n", .{});
    }

    std.debug.print("probe: PASS\n", .{});
}

/// True when the frame's `pane_id` addresses `want`. The id may arrive as
/// `"p-3"` or as a bare integer. A frame with no pane id is treated as
/// matching, since not every event kind carries one.
fn isPane(obj: std.json.ObjectMap, want: protocol.PaneId) bool {
    const pid = obj.get("pane_id") orelse return true;
    const got: ?protocol.PaneId = switch (pid) {
        .integer => |n| protocol.PaneId.init(@intCast(n)),
        .string => |str| protocol.PaneId.parseString(str),
        else => null,
    };
    return got != null and protocol.PaneId.eql(got.?, want);
}
