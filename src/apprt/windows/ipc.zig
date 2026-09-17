//! Windows named-pipe IPC stub.
//!
//! Implements the skeleton for libghostty's IPC transport on Windows
//! using named pipes. The actual pipe operations (CreateNamedPipe,
//! ConnectNamedPipe, ReadFile, WriteFile) are deferred to G3.4+.
//! Currently all operations return error.Unimplemented so the code compiles
//! but does not function — placeholder for the real Win32 implementation.
//!
//! Pipe naming: \\.\pipe\khostty-{server_pid} where {server_pid} is the
//! server's GetCurrentProcessId. Used for the Windows equivalent of the
//! Unix-domain socket pair used on GTK/macOS.

const std = @import("std");
const Allocator = std.mem.Allocator;

const stdwin = std.os.windows;

/// Constant prefix used for all khostty named pipes.
/// The runtime string literal `\\.\\pipe\\khostty-` (two backslashes per
/// visual backslash, as Zig requires) yields the Win32 namespace string
/// `\.pipe\khostty-` — matching the test expectation.
pub const PIPE_PREFIX: []const u8 = "\\.\\pipe\\khostty-";

/// Named pipe server stub.
pub const Server = struct {
    handle: stdwin.HANDLE = stdwin.INVALID_HANDLE_VALUE,
    pipe_name: []const u8,

    /// Failure code for unimplemented functionality.
    pub const Error = error{Unimplemented};

    /// Initialize the pipe server. Stubbed.
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
    pipe_name: []const u8,

    pub const Error = error{Unimplemented};

    /// Connect to a server's pipe. Stubbed.
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
    // Prefix renders as \\.\\pipe\\khostty-
    try t.expectEqualStrings("\\.\\pipe\\khostty-", PIPE_PREFIX);
}
