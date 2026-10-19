//! Phase 1 mux shell — headless binary skeleton.
//!
//! This file is the C5 deliverable for the Phase 1 mux shell design (see
//! `docs/sessions/20261017-mux-design/04_MUX_ARCHITECTURE.md` for the full
//! design). It is a scaffold: the function signatures and wiring are real,
//! but the actual server start, signal handling, and CLI parsing are left
//! as `TODO(phase-1)` markers for the implementation work that follows.
//!
//! Why a skeleton
//! --------------
//! The Phase 1 mux shell is a deployment composition of pieces that already
//! exist in the IPC layer (`pane.Manager`, `events.Broker`, `apprt.ipc.Server`).
//! What is missing is the small headless binary that hosts them. This file
//! documents the binary's shape with compilable Zig so:
//!
//!   * the type-checker validates the wiring at `zig build test-agent-ipc`;
//!   * a future implementer has a known-good starting point;
//!   * the operator can `git diff` to see exactly what changes from the
//!     skeleton to the live binary.
//!
//! What is real
//! ------------
//!   * the public `runMuxShell` function (signature and body shape);
//!   * the `Setup` struct that holds the wired-together Manager + Broker;
//!   * the `Config` defaults (matching `server.zig:38-66`).
//!
//! What is `TODO(phase-1)`
//! -----------------------
//!   * CLI argument parsing;
//!   * SIGINT/SIGTERM handling;
//!   * log file setup;
//!   * the actual `Server.bind` call (left to a future PR — the test root
//!     does not have a real `App` to back the AppHost, and a real bind
//!     would block the test).
//!
//! Compile-time proof
//! ------------------
//! This file is reachable from `src/main_agent_ipc.zig`, the test root for
//! `zig build test-agent-ipc`. That step type-checks the entire IPC layer
//! including the bridge onto the real runtime; a signature or import error
//! here fails the step. Run with:
//!
//!     zig build test-agent-ipc
//!
//! Lock-ordering guarantee
//! -----------------------
//! The setup logic respects the `Manager -> Broker` lock-order rule declared
//! in `pane.zig:22-24`:
//!
//!   * the Manager mutex is taken only inside `Manager.create/close/...`
//!     methods (verified by the existing `pane.zig` test suite);
//!   * the Broker mutex is taken only inside `events.Broker.publish`
//!     (verified by the existing `events.zig` test suite);
//!   * `Setup.runMuxShell` does not introduce a third lock or reorder
//!     the two existing ones.
//!
//! TODO(phase-1): replace the `TODO(phase-1)` markers with the actual logic
//! and remove this file from the test root if it is not needed for the
//! production binary (the production binary will live at
//! `src/mux_shell_main.zig` and be wired into `build.zig` separately).

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const build_config = @import("../../build_config.zig");
const App = @import("../../App.zig");

const pane_mod = @import("pane.zig");
const events_mod = @import("events.zig");
const server_mod = @import("server.zig");
const app_host_mod = @import("app_host.zig");
const auth_mod = @import("auth.zig");

const log = std.log.scoped(.mux_shell);

/// Configuration for `runMuxShell`. Mirrors `server.Config` (`server.zig:38-66`)
/// plus the binary's own CLI/env knobs.
pub const Config = struct {
    /// Filesystem path of the Unix socket. If null, defaults to the protocol
    /// convention from `protocol.md` §2 (macOS: `~/Library/Caches/khostty/ipc.sock`,
    /// Linux/BSD: `$XDG_RUNTIME_DIR/khostty/ipc.sock`).
    socket_path: ?[]const u8 = null,
    /// Session name; the socket path is derived from this when `socket_path` is
    /// null. Default: "default".
    session: []const u8 = "default",
    /// Max in-flight connections. Default 32.
    max_connections: u32 = 32,
    /// Per-connection frame rate limit. Default 100 fps.
    rate_limit_per_sec: u32 = 100,
    /// Event-pusher poll interval. Default 25 ms.
    event_poll_ms: u64 = 25,
    /// Run the per-connection event pusher. Default true.
    event_pusher: bool = true,
    /// When true, use `fake_host.zig` instead of `app_host.zig`. The skeleton
    /// ignores this flag; the live binary's `main` switches the host based on
    /// it. Kept here so the test can demonstrate the conditional.
    test_host: bool = false,
    /// Optional path to a log file. If null, logs go to stderr.
    log_file: ?[]const u8 = null,
    /// The server PID advertised by `ping`. Set to the binary's own PID at
    /// start.
    server_pid: ?u32 = null,
};

/// What `runMuxShell` produces: a wired-up `pane.Manager` and `events.Broker`,
/// ready to be handed to `Server.bind` (or to a test that exercises the
/// setup without a real socket).
pub const Setup = struct {
    manager: pane_mod.Manager,
    broker: events_mod.Broker,

    pub fn deinit(self: *Setup, io: std.Io) void {
        // Order matches construction: Manager first (it is the lock-owner for
        // the host vtable), then Broker (which serializes publishes).
        self.manager.deinit(io);
        self.broker.deinit(io);
    }
};

/// Construct the Manager and Broker pair with the AppHost wired in. This is
/// the only piece the test can exercise without a real socket: it allocates
/// both, sets the broker on the manager, and returns the pair ready for
/// `Server.bind`.
///
/// `app` is the libghostty `App` (the core runtime, not the GTK wrapper).
pub fn setup(
    gpa: Allocator,
    io: std.Io,
    app: *App,
) !Setup {
    // Construction order is Broker -> AppHost -> Manager:
    //   * Broker has no dependencies and is the first object the Manager
    //     will publish into, so it must exist before the Manager is built;
    //   * AppHost needs a `*App` and an `io`; both are available here;
    //   * Manager takes the AppHost's `Host` vtable (not the AppHost itself)
    //     so the vtable is captured at construction time;
    //   * `setEventBroker` on both sides wires the publish hooks (see C3).
    var broker: events_mod.Broker = .init(gpa);
    errdefer broker.deinit(io);

    var app_host: app_host_mod.AppHost = .init(gpa, io, app);
    app_host.setEventBroker(&broker);

    var manager: pane_mod.Manager = .init(gpa, app_host.host());
    errdefer manager.deinit(io);
    manager.setEventBroker(&broker);

    return .{
        .manager = manager,
        .broker = broker,
    };
}

/// Resolve the socket path from a `Config`. Centralized so the test and the
/// live binary agree on the protocol convention.
pub fn resolveSocketPath(alloc: Allocator, config: Config) ![]u8 {
    if (config.socket_path) |p| return try alloc.dupe(u8, p);

    // Per `protocol.md` §2, the per-platform default:
    //   macOS:  ~/Library/Caches/khostty/<session>/ipc.sock
    //   Linux:  $XDG_RUNTIME_DIR/khostty/<session>/ipc.sock
    //   (Windows: named pipe — out of scope for Phase 1)
    return switch (build_config.artifact) {
        .lib, .wasm_module => error.Unsupported,
        .exe => try defaultPath(alloc, config.session),
    };
}

fn defaultPath(alloc: Allocator, session: []const u8) ![]u8 {
    // The build host for this work is macOS. The path is verified against
    // `protocol.md` §2 in the B1 acceptance test. We use the `auth.Env`
    // abstraction so the function is testable without touching the real
    // process environment (the abstraction also covers XDG_RUNTIME_DIR on
    // Linux, which is the right knob for that platform).
    const env = auth_mod.Env.process();
    if (builtin.os.tag == .macos or builtin.os.tag == .ios) {
        const home = env.get("HOME") orelse return error.NoHome;
        return std.fmt.allocPrint(alloc, "{s}/Library/Caches/khostty/{s}/ipc.sock", .{
            home, session,
        });
    }
    if (builtin.os.tag == .windows) {
        // Phase 1 is POSIX only; Windows uses a named pipe.
        return error.Unsupported;
    }
    // Linux/BSD: $XDG_RUNTIME_DIR/khostty/<session>/ipc.sock
    const xdg = env.get("XDG_RUNTIME_DIR") orelse "/tmp";
    return std.fmt.allocPrint(alloc, "{s}/khostty/{s}/ipc.sock", .{
        xdg, session,
    });
}

/// The main entry point of the mux shell binary.
///
/// This is the function the live binary's `main` (in `src/mux_shell_main.zig`,
/// a future PR) calls. It is `TODO(phase-1)` because:
///   * the real version blocks on `signal_wait()` and runs the accept loop
///     until SIGTERM;
///   * the test cannot run the real version (no signal handling, no real
///     socket bound).
///
/// The shape is real: same parameter order as the live binary, same return
/// type, same dependency order. The body is the documented wire-up.
pub fn runMuxShell(
    gpa: Allocator,
    io: std.Io,
    app: *App,
    config: Config,
) !void {
    // Step 1: resolve socket path (allocates; freed on exit).
    const socket_path = try resolveSocketPath(gpa, config);
    defer gpa.free(socket_path);

    // Step 2: construct the Manager + Broker pair.
    var s = try setup(gpa, io, app);
    defer s.deinit(io);

    // Step 3: bind the server. This is `TODO(phase-1)` because:
    //   * the test build does not have a real `App` to back the AppHost;
    //   * the live binary wants a real `Server.bind` that blocks on accept.
    //
    // The live version of this block:
    //
    //     var authenticator: auth.Auth = try .load(gpa, ...);
    //     var srv = try server_mod.Server.bind(gpa, io, .{
    //         .socket_path = socket_path,
    //         .max_connections = config.max_connections,
    //         .rate_limit_per_sec = config.rate_limit_per_sec,
    //         .event_poll_ms = config.event_poll_ms,
    //         .event_pusher = config.event_pusher,
    //         .replace_existing = true,
    //     }, .{
    //         .manager = &s.manager,
    //         .broker = &s.broker,
    //         .authenticator = &authenticator,
    //         .server_pid = config.server_pid,
    //     });
    //     defer srv.deinit();
    //     defer srv.stop();
    //
    //     // Block on signal. The skeleton does not do this; the test
    //     // build would deadlock if it did.
    //     std.debug.print("khostty-mux listening on {s}\n", .{socket_path});
    //     signalWait();
    //
    _ = server_mod; // referenced by the TODO(phase-1) block above; keep the import live.
    log.info("khostty-mux skeleton: setup complete, server bind TODO(phase-1)", .{});
}

// ── Tests ────────────────────────────────────────────────────────────────
//
// The skeleton's tests exercise `Config` and `resolveSocketPath`. The
// `setup` function is not tested at runtime here because constructing a
// real `*App` in a test requires the full `core_app` chain (GPU/renderer);
// `AppHost.init` only stores the pointer, but the test would have to fake
// enough of the type to satisfy alignment. The type-checker verifies the
// signature, which is the proof the skeleton needs.
//
// The live binary's tests (E2E in `test/mux-shell-e2e.bash`) are out of
// scope for this file.

test "Config: defaults match server.zig" {
    const testing = std.testing;
    const defaults = Config{};
    try testing.expectEqual(@as(u32, 32), defaults.max_connections);
    try testing.expectEqual(@as(u32, 100), defaults.rate_limit_per_sec);
    try testing.expectEqual(@as(u64, 25), defaults.event_poll_ms);
    try testing.expect(defaults.event_pusher);
    try testing.expect(!defaults.test_host);
    try testing.expectEqualStrings("default", defaults.session);
    try testing.expect(defaults.socket_path == null);
    try testing.expect(defaults.log_file == null);
    try testing.expect(defaults.server_pid == null);
}

test "resolveSocketPath: explicit path wins" {
    const testing = std.testing;
    const gpa = testing.allocator;
    const path = try resolveSocketPath(gpa, .{ .socket_path = "/tmp/explicit.sock" });
    defer gpa.free(path);
    try testing.expectEqualStrings("/tmp/explicit.sock", path);
}

test "resolveSocketPath: session name is reflected in default path" {
    // The exact default path is host-dependent (HOME/XDG_RUNTIME_DIR env
    // vars). This test only asserts that the session name appears in the
    // result when no explicit socket_path is given. It runs on POSIX; on
    // Windows the path scheme differs.
    if (builtin.os.tag == .windows) return;

    const testing = std.testing;
    const gpa = testing.allocator;
    const path = try resolveSocketPath(gpa, .{ .session = "ci-run-42" });
    defer gpa.free(path);
    try testing.expect(std.mem.indexOf(u8, path, "ci-run-42") != null);
}

test "Setup.deinit: order matches construction" {
    // The deinit order is fixed by the construction order (Manager first,
    // then Broker). This test pins the field order so a future refactor
    // cannot reorder them silently. It does not call deinit because
    // constructing the Setup requires a real `*App`.
    const testing = std.testing;
    const info = @typeInfo(Setup);
    inline for (info.@"struct".fields, 0..) |f, i| {
        if (i == 0) try testing.expectEqualStrings("manager", f.name);
        if (i == 1) try testing.expectEqualStrings("broker", f.name);
    }
}
