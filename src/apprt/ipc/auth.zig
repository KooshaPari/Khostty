//! Token authentication for the agent IPC surface.
//!
//! Rules (see `protocol.md` section 5):
//!
//!   * `ping` is unauthenticated; every other command requires a token.
//!   * No token configured means **fail closed**: verification always returns
//!     false and the server rejects authenticated commands. The server never
//!     runs unauthenticated.
//!   * Comparison never compares variable-length secrets directly: both sides
//!     are hashed with SHA-256 and the 32-byte digests are compared in constant
//!     time, so neither content nor length leaks through timing.
//!   * Tokens are 32 random bytes, hex-encoded (64 characters), either taken
//!     from `KHOSTTY_IPC_TOKEN` or read from a `0600` token file that the server
//!     creates on first run.
//!
//!     zig test src/apprt/ipc/auth.zig

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

/// Entropy of a generated token, in bytes.
pub const token_bytes = 32;

/// Length of a hex-encoded token.
pub const token_hex_len = token_bytes * 2;

/// Largest token file we will read, in bytes.
pub const max_token_file_bytes = 4096;

/// Environment variable holding the token directly.
pub const token_env = "KHOSTTY_IPC_TOKEN";
/// Environment variable naming the socket path.
pub const socket_env = "KHOSTTY_IPC_SOCKET";
/// Environment variable naming the token file.
pub const token_file_env = "KHOSTTY_IPC_TOKEN_FILE";

// ─────────────────────────────────────────────────────────────────────────
// Environment lookup
// ─────────────────────────────────────────────────────────────────────────

/// Environment lookup, injectable so path and token resolution is testable
/// without touching the real process environment.
pub const Env = struct {
    ctx: ?*const anyopaque = null,
    getFn: *const fn (ctx: ?*const anyopaque, name: []const u8) ?[]const u8,

    pub fn get(self: Env, name: []const u8) ?[]const u8 {
        return self.getFn(self.ctx, name);
    }

    /// The real process environment. Under `zig test` this reads the testing
    /// environment; otherwise it reads through libc, which the app links on
    /// every supported platform.
    pub fn process() Env {
        if (builtin.is_test) return .{ .getFn = testingGet };
        if (builtin.link_libc) return .{ .getFn = libcGet };
        return .{ .getFn = noneGet };
    }

    /// A fixed table, for tests and for hosts that want a pinned environment.
    pub const Table = struct {
        vars: []const [2][]const u8,

        pub fn env(self: *const Table) Env {
            return .{ .ctx = self, .getFn = getFromTable };
        }

        fn getFromTable(ctx: ?*const anyopaque, name: []const u8) ?[]const u8 {
            const self: *const Table = @ptrCast(@alignCast(ctx.?));
            for (self.vars) |kv| {
                if (std.mem.eql(u8, kv[0], name)) return kv[1];
            }
            return null;
        }
    };

    fn noneGet(_: ?*const anyopaque, _: []const u8) ?[]const u8 {
        return null;
    }

    fn testingGet(_: ?*const anyopaque, name: []const u8) ?[]const u8 {
        if (comptime builtin.os.tag == .windows) return null;
        return std.testing.environ.getPosix(name);
    }

    fn libcGet(_: ?*const anyopaque, name: []const u8) ?[]const u8 {
        var buf: [256:0]u8 = undefined;
        if (name.len >= buf.len) return null;
        @memcpy(buf[0..name.len], name);
        buf[name.len] = 0;
        const value = std.c.getenv(&buf) orelse return null;
        return std.mem.sliceTo(value, 0);
    }
};

// ─────────────────────────────────────────────────────────────────────────
// Token generation and verification
// ─────────────────────────────────────────────────────────────────────────

/// Error set of `generateToken`.
pub const GenerateError = Allocator.Error || std.Io.RandomSecureError;

/// Generate a fresh token: 32 random bytes from the cryptographically secure
/// RNG, lowercase hex-encoded. Caller frees.
pub fn generateToken(alloc: Allocator, io: std.Io) GenerateError![]u8 {
    var raw: [token_bytes]u8 = undefined;
    try io.randomSecure(&raw);
    const out = try alloc.alloc(u8, token_hex_len);
    _ = std.fmt.bufPrint(out, "{x}", .{&raw}) catch unreachable;
    return out;
}

fn digest(token: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(token, &out, .{});
    return out;
}

/// Token verifier. Owns a copy of the configured token.
pub const Auth = struct {
    gpa: Allocator,
    token_buf: ?[]u8 = null,
    expected: [32]u8 = @splat(0),

    /// Create from a configured token, or from `null` for "not configured".
    /// The token is copied; `Auth` does not borrow it.
    pub fn init(gpa: Allocator, value: ?[]const u8) Allocator.Error!Auth {
        const provided = value orelse return .{ .gpa = gpa };
        const buf = try gpa.dupe(u8, provided);
        return .{
            .gpa = gpa,
            .token_buf = buf,
            .expected = digest(buf),
        };
    }

    pub fn deinit(self: *Auth) void {
        if (self.token_buf) |buf| self.gpa.free(buf);
        self.* = undefined;
    }

    /// Whether any token is configured. When false, every verification fails.
    pub fn isConfigured(self: *const Auth) bool {
        return self.token_buf != null;
    }

    /// Constant-time verification. Returns false when no token is configured,
    /// when the request carried none, or when it does not match.
    pub fn verify(self: *const Auth, candidate: ?[]const u8) bool {
        if (!self.isConfigured()) return false;
        const provided = candidate orelse return false;
        if (provided.len == 0) return false;
        const provided_digest = digest(provided);
        return std.crypto.timing_safe.eql([32]u8, self.expected, provided_digest);
    }

    /// The configured token. For bootstrap/tests only; never log this.
    pub fn token(self: *const Auth) ?[]const u8 {
        return self.token_buf;
    }
};

// ─────────────────────────────────────────────────────────────────────────
// File system layout
// ─────────────────────────────────────────────────────────────────────────

/// Resolved paths for the socket and token file. All owned by the allocation.
pub const Paths = struct {
    gpa: Allocator,
    socket: []u8,
    dir: []u8,
    token_file: []u8,

    pub fn deinit(self: *Paths) void {
        self.gpa.free(self.socket);
        self.gpa.free(self.dir);
        self.gpa.free(self.token_file);
        self.* = undefined;
    }
};

/// Runtime directory: `${KHOSTTY_IPC_SOCKET%/*}` when the socket is overridden,
/// else `$HOME/Library/Caches/khostty` on macOS and
/// `$XDG_RUNTIME_DIR/khostty` (or `/tmp/khostty-<uid>`) elsewhere.
fn resolveDir(gpa: Allocator, env: Env) Allocator.Error![]u8 {
    if (env.get("KHOSTTY_IPC_DIR")) |dir| return gpa.dupe(u8, dir);

    if (builtin.os.tag == .macos or builtin.os.tag == .ios) {
        const home = env.get("HOME") orelse "/tmp";
        return std.fmt.allocPrint(gpa, "{s}/Library/Caches/khostty", .{home});
    }

    if (builtin.os.tag == .windows) {
        const local = env.get("LOCALAPPDATA") orelse return gpa.dupe(u8, "\\tmp");
        return std.fmt.allocPrint(gpa, "{s}\\khostty", .{local});
    }

    if (env.get("XDG_RUNTIME_DIR")) |runtime| {
        return std.fmt.allocPrint(gpa, "{s}/khostty", .{runtime});
    }

    const uid: u32 = if (builtin.link_libc) @intCast(std.c.getuid()) else 0;
    return std.fmt.allocPrint(gpa, "/tmp/khostty-{d}", .{uid});
}

/// Resolve the socket path, runtime directory, and token file path.
pub fn resolvePaths(gpa: Allocator, env: Env) Allocator.Error!Paths {
    const dir = try resolveDir(gpa, env);
    errdefer gpa.free(dir);

    const socket = if (env.get(socket_env)) |path|
        try gpa.dupe(u8, path)
    else
        try std.fmt.allocPrint(gpa, "{s}{s}", .{ dir, switch (builtin.os.tag) {
            .windows => "\\ipc.pipe",
            else => "/ipc.sock",
        } });
    errdefer gpa.free(socket);

    const token_file = if (env.get(token_file_env)) |path|
        try gpa.dupe(u8, path)
    else
        try std.fmt.allocPrint(gpa, "{s}{s}", .{ dir, switch (builtin.os.tag) {
            .windows => "\\ipc.token",
            else => "/ipc.token",
        } });

    return .{ .gpa = gpa, .socket = socket, .dir = dir, .token_file = token_file };
}

/// An owned token read from somewhere, with a trimmed view.
pub const LoadedToken = struct {
    gpa: Allocator,
    buf: []u8,
    token: []const u8,

    pub fn deinit(self: *LoadedToken) void {
        self.gpa.free(self.buf);
        self.* = undefined;
    }
};

/// Read the token file, if it exists. Returns null when absent or empty.
pub fn readTokenFile(gpa: Allocator, io: std.Io, path: []const u8) !?LoadedToken {
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close(io);

    const len = try file.length(io);
    if (len == 0 or len > max_token_file_bytes) return null;

    const buf = try gpa.alloc(u8, @intCast(len));
    errdefer gpa.free(buf);
    const n = try file.readPositionalAll(io, buf, 0);

    const trimmed = std.mem.trim(u8, buf[0..n], " \t\r\n");
    if (trimmed.len == 0) {
        gpa.free(buf);
        return null;
    }
    std.mem.copyForwards(u8, buf, trimmed);
    return .{ .gpa = gpa, .buf = buf, .token = buf[0..trimmed.len] };
}

/// Write a token file, creating the runtime directory if needed. The file is
/// created `0600` and never clobbers an existing file.
pub fn writeTokenFile(
    gpa: Allocator,
    io: std.Io,
    paths: *const Paths,
    token: []const u8,
) !void {
    _ = gpa;
    std.Io.Dir.cwd().createDirPath(io, paths.dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const file = try std.Io.Dir.cwd().createFile(io, paths.token_file, .{
        .read = true,
        .exclusive = true,
        .permissions = std.Io.File.Permissions.fromMode(0o600),
    });
    defer file.close(io);
    try file.writeStreamingAll(io, token);
    try file.writeStreamingAll(io, "\n");
}

/// Where the effective token came from.
pub const Source = enum {
    /// `KHOSTTY_IPC_TOKEN` was set.
    environment,
    /// A token file was read.
    token_file,
    /// No token existed, so one was generated and written.
    generated,
    /// No token could be obtained; the server will reject authenticated
    /// commands (fail closed).
    unconfigured,
};

/// A ready-to-serve authentication setup.
pub const Setup = struct {
    gpa: Allocator,
    paths: Paths,
    auth: Auth,
    source: Source,

    pub fn deinit(self: *Setup) void {
        self.auth.deinit();
        self.paths.deinit();
        self.* = undefined;
    }
};

/// Resolve paths, then load the token from the environment, the token file, or
/// by generating a new one. Never returns an error for a missing token: a
/// failure to obtain one yields `Source.unconfigured` and a fail-closed `Auth`.
pub fn setup(gpa: Allocator, io: std.Io, env: Env) !Setup {
    const paths = try resolvePaths(gpa, env);
    errdefer {
        var p = paths;
        p.deinit();
    }

    if (env.get(token_env)) |raw| {
        const trimmed = std.mem.trim(u8, raw, " \t\r\n");
        if (trimmed.len > 0) {
            return .{
                .gpa = gpa,
                .paths = paths,
                .auth = try Auth.init(gpa, trimmed),
                .source = .environment,
            };
        }
    }

    if (readTokenFile(gpa, io, paths.token_file) catch null) |loaded| {
        defer gpa.free(loaded.buf);
        return .{
            .gpa = gpa,
            .paths = paths,
            .auth = try Auth.init(gpa, loaded.token),
            .source = .token_file,
        };
    }

    const generated = generateToken(gpa, io) catch {
        return .{ .gpa = gpa, .paths = paths, .auth = .{ .gpa = gpa }, .source = .unconfigured };
    };
    defer gpa.free(generated);

    writeTokenFile(gpa, io, &paths, generated) catch {
        return .{ .gpa = gpa, .paths = paths, .auth = .{ .gpa = gpa }, .source = .unconfigured };
    };

    return .{
        .gpa = gpa,
        .paths = paths,
        .auth = try Auth.init(gpa, generated),
        .source = .generated,
    };
}

// ─────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────

const testing = std.testing;

fn testIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

fn tableEnv(vars: []const [2][]const u8) Env {
    const holder = struct {
        var table: Env.Table = undefined;
    };
    holder.table = .{ .vars = vars };
    return holder.table.env();
}

test "generateToken: 64 lowercase hex characters" {
    const token = try generateToken(testing.allocator, testIo());
    defer testing.allocator.free(token);
    try testing.expectEqual(token_hex_len, token.len);
    for (token) |c| {
        try testing.expect((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f'));
    }

    const other = try generateToken(testing.allocator, testIo());
    defer testing.allocator.free(other);
    try testing.expect(!std.mem.eql(u8, token, other));
}

test "auth: correct token verifies" {
    var auth = try Auth.init(testing.allocator, "s3cret");
    defer auth.deinit();
    try testing.expect(auth.isConfigured());
    try testing.expect(auth.verify("s3cret"));
}

test "auth: wrong, missing, empty, and prefix tokens are rejected" {
    var auth = try Auth.init(testing.allocator, "s3cret");
    defer auth.deinit();
    try testing.expect(!auth.verify("s3cres"));
    try testing.expect(!auth.verify("s3cret "));
    try testing.expect(!auth.verify("s3cre"));
    try testing.expect(!auth.verify("s3crett"));
    try testing.expect(!auth.verify(""));
    try testing.expect(!auth.verify(null));
}

test "auth: unconfigured fails closed" {
    var auth = try Auth.init(testing.allocator, null);
    defer auth.deinit();
    try testing.expect(!auth.isConfigured());
    try testing.expect(!auth.verify(null));
    try testing.expect(!auth.verify(""));
    try testing.expect(!auth.verify("anything"));
}

test "auth: configured token is copied, not borrowed" {
    var source = "borrowed".*;
    var auth = try Auth.init(testing.allocator, &source);
    defer auth.deinit();
    @memset(&source, 'x');
    try testing.expect(auth.verify("borrowed"));
    try testing.expect(!auth.verify("xxxxxxxx"));
}

test "env table: lookup" {
    const env = tableEnv(&.{ .{ "A", "1" }, .{ "B", "" } });
    try testing.expectEqualStrings("1", env.get("A").?);
    try testing.expectEqualStrings("", env.get("B").?);
    try testing.expectEqual(@as(?[]const u8, null), env.get("C"));
}

test "paths: socket override wins and token file stays in the default dir" {
    const env = tableEnv(&.{
        .{ socket_env, "/custom/agent.sock" },
        .{ "KHOSTTY_IPC_DIR", "/run/khostty" },
    });
    var paths = try resolvePaths(testing.allocator, env);
    defer paths.deinit();
    try testing.expectEqualStrings("/custom/agent.sock", paths.socket);
    try testing.expectEqualStrings("/run/khostty", paths.dir);
    try testing.expectEqualStrings("/run/khostty/ipc.token", paths.token_file);
}

test "paths: token file override" {
    const env = tableEnv(&.{
        .{ "KHOSTTY_IPC_DIR", "/run/khostty" },
        .{ token_file_env, "/elsewhere/token" },
    });
    var paths = try resolvePaths(testing.allocator, env);
    defer paths.deinit();
    try testing.expectEqualStrings("/elsewhere/token", paths.token_file);
    try testing.expectEqualStrings("/run/khostty", paths.dir);
}

test "paths: default dir is platform-appropriate" {
    const env = tableEnv(&.{.{ "KHOSTTY_IPC_DIR", "/run/khostty" }});
    var paths = try resolvePaths(testing.allocator, env);
    defer paths.deinit();
    switch (builtin.os.tag) {
        .windows => try testing.expectEqualStrings("/run/khostty\\ipc.sock", paths.socket),
        else => try testing.expectEqualStrings("/run/khostty/ipc.sock", paths.socket),
    }
}

test "paths: xdg runtime dir and home fallbacks" {
    const xdg = tableEnv(&.{.{ "XDG_RUNTIME_DIR", "/run/user/1000" }});
    var xdg_paths = try resolvePaths(testing.allocator, xdg);
    defer xdg_paths.deinit();
    if (builtin.os.tag != .macos and builtin.os.tag != .windows and builtin.os.tag != .ios) {
        try testing.expectEqualStrings("/run/user/1000/khostty", xdg_paths.dir);
    }

    const home = tableEnv(&.{.{ "HOME", "/home/agent" }});
    var home_paths = try resolvePaths(testing.allocator, home);
    defer home_paths.deinit();
    if (builtin.os.tag == .macos) {
        try testing.expectEqualStrings("/home/agent/Library/Caches/khostty", home_paths.dir);
    }
}

test "setup: environment token is used verbatim" {
    const env = tableEnv(&.{.{ token_env, "from-env\n" }});
    var setup_result = try setup(testing.allocator, testIo(), env);
    defer setup_result.deinit();
    try testing.expectEqual(Source.environment, setup_result.source);
    try testing.expect(setup_result.auth.verify("from-env"));
    try testing.expect(!setup_result.auth.verify("from-env\n"));
}

test "setup: token file round-trip, then reuse" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Build an env pointing at the temp dir. The dir path must be absolute,
    // so resolve it through the Dir handle.
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path_len = try tmp.dir.realPath(testing.io, &buf);
    const dir_path = buf[0..dir_path_len];

    const vars = [_][2][]const u8{
        .{ "KHOSTTY_IPC_DIR", dir_path },
    };
    const env = tableEnv(&vars);

    var first = try setup(testing.allocator, testing.io, env);
    defer first.deinit();
    try testing.expectEqual(Source.generated, first.source);
    const token = try testing.allocator.dupe(u8, first.auth.token().?);
    defer testing.allocator.free(token);
    try testing.expect(token.len == token_hex_len);

    var second = try setup(testing.allocator, testing.io, env);
    defer second.deinit();
    try testing.expectEqual(Source.token_file, second.source);
    try testing.expect(second.auth.verify(token));
}
