//! Windows named-pipe IPC stub.
//!
//! This is the skeleton for libghostty's IPC transport on Windows, the
//! counterpart of the Unix-domain socket pair used on GTK and macOS. The pipe
//! operations themselves (CreateNamedPipe, ConnectNamedPipe, ReadFile,
//! WriteFile) are deferred to G3.4+; every operation returns
//! `error.Unimplemented`, so nothing here is reachable today.
//!
//! Three decisions are recorded here rather than left to the implementation,
//! because each was wrong or absent in an earlier revision:
//!
//! 1. The path namespace. Pipes live at
//!    `\.\pipe\khostty-{server_pid}` — see `PIPE_PREFIX` and `pipeName`.
//! 2. The DACL. Pipes are owner-only, not process-default — see
//!    `PIPE_DACL_SDDL`.
//! 3. Handle inheritance. Pipe handles must not leak into child processes —
//!    see `PIPE_HANDLE_INHERITABLE`.
//!
//! `docs/SECURITY.md#4-windows-transport-weakness-scaffold` tracks why 2 and 3
//! matter; this file is where they become concrete.

const std = @import("std");
const Allocator = std.mem.Allocator;

const stdwin = std.os.windows;

/// A single backslash, spelled once so no literal has to count them.
const backslash: u8 = '\\';

/// Runtime prefix of every khostty named pipe: `\.\pipe\khostty-`.
///
/// The two leading backslashes are load-bearing. Win32 named pipes live in the
/// `\.\pipe\` device namespace. A path with a *single* leading backslash is an
/// absolute path on the current drive, which is a different namespace, not where
/// `CreateNamedPipeW` puts a pipe, and not where a client would find one.
///
/// The bytes are spelled out one at a time on purpose. Zig has no raw strings,
/// so a literal has to double every backslash, and the previous revision of this
/// constant lost exactly that doubling: it read `"\\.\\pipe\\khostty-"`, whose
/// runtime value is `\.\pipe\khostty-`, one backslash short. Writing the bytes
/// takes escape arithmetic off the review surface, and the tests below assert
/// byte positions rather than comparing two literals, so a mistake cannot agree
/// with itself.
pub const PIPE_PREFIX: []const u8 = &.{
    backslash, backslash, '.', backslash, 'p', 'i', 'p', 'e', backslash,
    'k',       'h',       'o', 's',       't', 't', 'y', '-',
};

/// Decimal digits a `u32` process id can need.
const max_pid_digits = 10;

/// Full runtime path of the pipe served by `server_pid`:
/// `\.\pipe\khostty-{server_pid}`.
///
/// The caller owns the result. It is null-terminated because Win32 object APIs
/// consume NUL-terminated strings; converting to the UTF-16 form that
/// `CreateNamedPipeW` wants is the implementation's job.
pub fn pipeName(alloc: Allocator, server_pid: u32) Allocator.Error![:0]u8 {
    var digits_buf: [max_pid_digits]u8 = undefined;
    const digits = std.fmt.bufPrint(&digits_buf, "{d}", .{server_pid}) catch unreachable;

    const buf = try alloc.allocSentinel(u8, PIPE_PREFIX.len + digits.len, 0);
    @memcpy(buf[0..PIPE_PREFIX.len], PIPE_PREFIX);
    @memcpy(buf[PIPE_PREFIX.len..][0..digits.len], digits);
    return buf;
}

/// The DACL every khostty pipe must carry once a pipe is actually created.
///
/// Security Descriptor Definition Language: `D:P(A;;GA;;;OW)`.
///
/// | Part | Meaning |
/// |---|---|
/// | `D:` | This is the DACL. |
/// | `P` | Protected: it inherits no ACE from its parent container. |
/// | `(A;;GA;;;OW)` | One ACE: allow `GENERIC_ALL` to `OW`, the owner-rights SID. |
///
/// `OW` is `S-1-3-4`, which the system resolves to the object's owner. The ACE
/// therefore grants the user who created the pipe and no one else — the Windows
/// counterpart of the `0o600` socket the Unix transports use. A pipe left on the
/// process default DACL instead admits every process in the session, which is the
/// Windows equivalent of a world-writable socket.
pub const PIPE_DACL_SDDL = "D:P(A;;GA;;;OW)";

/// Pipe handles must not be inheritable. An inheritable handle would pass the
/// transport into every child process the terminal spawns, a wider trust
/// boundary than `PIPE_DACL_SDDL` draws.
pub const PIPE_HANDLE_INHERITABLE = false;

/// Not applied yet, and deliberately so: converting `PIPE_DACL_SDDL` into a
/// `SECURITY_ATTRIBUTES` needs
/// `ConvertStringSecurityDescriptorToSecurityDescriptorW` and
/// `LocalFree`, neither of which `std.os.windows` declares, and there is no pipe
/// to attach a descriptor to while every operation returns
/// `error.Unimplemented`. The two constants above are the decision the earlier
/// revision lacked; wiring them belongs to the pipe implementation.
///
/// The v1 IPC auth design in `src/apprt/ipc/protocol.md` is Unix-socket-shaped
/// and does not describe this transport. It needs to, before G3 and G4 converge.
/// Named pipe server stub.
pub const Server = struct {
    handle: stdwin.HANDLE = stdwin.INVALID_HANDLE_VALUE,
    /// Owned by the caller. Build it with `pipeName`.
    pipe_name: []const u8,

    /// Failure code for unimplemented functionality.
    pub const Error = error{Unimplemented};

    /// Initialize the pipe server. Stubbed.
    ///
    /// The real implementation creates `pipeName(server_pid)` with
    /// `PIPE_DACL_SDDL` as its DACL and `PIPE_HANDLE_INHERITABLE` as its
    /// inheritance flag.
    pub fn init(alloc: Allocator, server_pid: u32) Error!Server {
        _ = alloc;
        _ = server_pid;
        return Error.Unimplemented;
    }

    /// Free any held resources (none today).
    pub fn deinit(self: *Server) void {
        _ = self;
    }

    /// Accept an incoming client connection. Stubbed.
    pub fn acceptConnection(self: *Server) Error!stdwin.HANDLE {
        _ = self;
        return Error.Unimplemented;
    }
};

/// Named pipe client stub.
pub const Client = struct {
    handle: stdwin.HANDLE = stdwin.INVALID_HANDLE_VALUE,
    /// Owned by the caller. Build it with `pipeName`.
    pipe_name: []const u8,

    pub const Error = error{Unimplemented};

    /// Connect to the pipe served by `server_pid`. Stubbed.
    pub fn connect(alloc: Allocator, server_pid: u32) Error!Client {
        _ = alloc;
        _ = server_pid;
        return Error.Unimplemented;
    }

    /// Release the connection and handle.
    pub fn deinit(self: *Client) void {
        _ = self;
    }

    /// Send an IPC frame (action + payload). Stubbed.
    pub fn send(self: *Client, action: u16, payload: []const u8) Error!void {
        _ = self;
        _ = action;
        _ = payload;
        return Error.Unimplemented;
    }

    /// Receive an IPC frame from the server. Stubbed.
    pub fn receive(self: *Client) Error![]const u8 {
        _ = self;
        return Error.Unimplemented;
    }
};

/// IPC message frame layout (G4 will define version and exact payload).
pub const MessageFrame = extern struct {
    action: u16, // Ghostty IPC action tag (see apprt/ipc.zig).
    length: u32, // Size of the payload in bytes.
    // Payload follows immediately after this header (packed).
};

test "windows ipc stubs" {
    const t = std.testing;
    // Server init returns Unimplemented.
    try t.expectError(error.Unimplemented, Server.init(t.allocator, 1234));
    // Client init returns Unimplemented.
    try t.expectError(error.Unimplemented, Client.connect(t.allocator, 1234));
}

test "the pipe prefix names the Win32 device namespace" {
    const t = std.testing;

    // `\.\pipe\` is two backslashes, a dot and a backslash. One leading
    // backslash is a drive-relative path and not a pipe at all.
    try t.expectEqual(@as(usize, 17), PIPE_PREFIX.len);
    try t.expectEqual(backslash, PIPE_PREFIX[0]);
    try t.expectEqual(backslash, PIPE_PREFIX[1]);
    try t.expectEqual(@as(u8, '.'), PIPE_PREFIX[2]);
    try t.expectEqual(backslash, PIPE_PREFIX[3]);
    try t.expectEqualStrings("pipe", PIPE_PREFIX[4..8]);
    try t.expectEqual(backslash, PIPE_PREFIX[8]);
    try t.expectEqualStrings("khostty-", PIPE_PREFIX[9..]);
}

test "pipeName builds the device-namespace path for a pid" {
    const t = std.testing;

    const name = try pipeName(t.allocator, 1234);
    defer t.allocator.free(name);

    // The form one writes in docs: `\.\pipe\khostty-1234`. Two leading
    // backslashes. The byte assertions below are the load-bearing ones; this
    // line exists to fail loudly if the prefix regresses.
    try t.expectEqualStrings("\\\\.\\pipe\\khostty-1234", name);
    try t.expectEqual(backslash, name[0]);
    try t.expectEqual(backslash, name[1]);
    try t.expectEqual(@as(u8, 0), name.ptr[name.len]);

    const max = try pipeName(t.allocator, std.math.maxInt(u32));
    defer t.allocator.free(max);
    try t.expectEqualStrings("\\\\.\\pipe\\khostty-4294967295", max);
}

test "the pipe ACL is owner-only and not inheritable" {
    const t = std.testing;

    try t.expectEqualStrings("D:P(A;;GA;;;OW)", PIPE_DACL_SDDL);

    // Exactly one ACE, and it is the owner-rights SID.
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, PIPE_DACL_SDDL, "("));
    try t.expect(std.mem.endsWith(u8, PIPE_DACL_SDDL, ";;;OW)"));
    // Protected, so a parent container cannot widen it.
    try t.expect(std.mem.startsWith(u8, PIPE_DACL_SDDL, "D:P"));

    // No well-known wider trustee, by SID abbreviation.
    for ([_][]const u8{ "WD", "BU", "AU", "AN", "BG", "SY", "BA", "CO" }) |sid| {
        var needle: [6]u8 = undefined;
        const pattern = try std.fmt.bufPrint(&needle, ";;;{s})", .{sid});
        try t.expectEqual(
            @as(?usize, null),
            std.mem.indexOf(u8, PIPE_DACL_SDDL, pattern),
        );
    }

    try t.expect(!PIPE_HANDLE_INHERITABLE);
}
