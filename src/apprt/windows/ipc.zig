//! Local, synchronous Windows named-pipe transport. Not an application dispatcher.
//! Wire header: little-endian action (u16), payload length (u32), then payload.
const std = @import("std");
const w = std.os.windows;
const Allocator = std.mem.Allocator;
const api = @import("ipc_win32.zig");
pub const PIPE_PREFIX = "\\\\.\\pipe\\khostty-";
pub const max_frame_bytes = 1024 * 1024;
pub const MessageFrame = struct { action: u16, length: u32 };
pub const Frame = struct {
    action: u16,
    payload: []u8,
    pub fn deinit(self: Frame, alloc: Allocator) void {
        alloc.free(self.payload);
    }
};

pub fn pipeName(alloc: Allocator, pid: u32) ![:0]u8 {
    return std.fmt.allocPrintSentinel(alloc, "{s}{d}", .{ PIPE_PREFIX, pid }, 0);
}

pub const Server = struct {
    handle: w.HANDLE,
    alloc: Allocator,
    pipe_name: [:0]u8,
    connected: bool = false,

    pub fn init(alloc: Allocator, pid: u32) !Server {
        const name = try pipeName(alloc, pid);
        errdefer alloc.free(name);
        const wide = try std.unicode.utf8ToUtf16LeAllocZ(alloc, name);
        defer alloc.free(wide);
        var security = try api.Security.init(alloc);
        defer security.deinit();
        // FIRST_PIPE_INSTANCE refuses a pre-existing name, including a squatter.
        const handle = api.CreateNamedPipeW(wide, api.PIPE_ACCESS_DUPLEX | api.FILE_FLAG_FIRST_PIPE_INSTANCE, api.PIPE_REJECT_REMOTE_CLIENTS, 1, 65536, 65536, 0, &security.attributes);
        if (handle == w.INVALID_HANDLE_VALUE) return error.PipeCreateFailed;
        return .{ .handle = handle, .alloc = alloc, .pipe_name = name };
    }

    pub fn deinit(self: *Server) void {
        _ = api.CloseHandle(self.handle);
        self.alloc.free(self.pipe_name);
        self.* = undefined;
    }

    /// Borrowed handle; owned and closed by Server. One client at a time.
    pub fn acceptConnection(self: *Server) !w.HANDLE {
        if (self.connected) return error.AlreadyConnected;
        if (api.ConnectNamedPipe(self.handle, null) == 0 and api.GetLastError() != 535)
            return error.PipeConnectFailed;
        self.connected = true;
        return self.handle;
    }

    /// Disconnect without flushing: an unresponsive client cannot hold shutdown.
    pub fn disconnect(self: *Server) !void {
        if (!self.connected) return error.NotConnected;
        if (api.DisconnectNamedPipe(self.handle) == 0) return error.PipeDisconnectFailed;
        self.connected = false;
    }
    /// Wait for the peer to consume replies before an orderly disconnect.
    /// May block; shutdown should use deinit instead.
    pub fn flush(self: *Server) !void {
        if (!self.connected) return error.NotConnected;
        if (api.FlushFileBuffers(self.handle) == 0) return error.PipeFlushFailed;
    }
    pub fn send(self: *Server, action: u16, payload: []const u8) !void {
        if (!self.connected) return error.NotConnected;
        try sendFrame(self.handle, action, payload);
    }
    pub fn receive(self: *Server) !Frame {
        if (!self.connected) return error.NotConnected;
        return receiveFrame(self.alloc, self.handle);
    }
};

pub const Client = struct {
    handle: w.HANDLE,
    alloc: Allocator,
    pipe_name: [:0]u8,
    pub fn connect(alloc: Allocator, pid: u32) !Client {
        const name = try pipeName(alloc, pid);
        errdefer alloc.free(name);
        const wide = try std.unicode.utf8ToUtf16LeAllocZ(alloc, name);
        defer alloc.free(wide);
        // OPEN_EXISTING; no inheritance, no fallback to another transport.
        const handle = api.CreateFileW(wide, 0xC0000000, 0, null, 3, 0, null);
        if (handle == w.INVALID_HANDLE_VALUE) return error.PipeConnectFailed;
        return .{ .handle = handle, .alloc = alloc, .pipe_name = name };
    }
    pub fn deinit(self: *Client) void {
        _ = api.CloseHandle(self.handle);
        self.alloc.free(self.pipe_name);
        self.* = undefined;
    }
    pub fn send(self: *Client, action: u16, payload: []const u8) !void {
        try sendFrame(self.handle, action, payload);
    }
    /// Caller owns the returned payload and frees it with Client.alloc.
    pub fn receive(self: *Client) !Frame {
        return receiveFrame(self.alloc, self.handle);
    }
};

pub fn encodeHeader(action: u16, length: u32) [6]u8 {
    var bytes: [6]u8 = undefined;
    std.mem.writeInt(u16, bytes[0..2], action, .little);
    std.mem.writeInt(u32, bytes[2..6], length, .little);
    return bytes;
}
fn sendFrame(handle: w.HANDLE, action: u16, payload: []const u8) !void {
    if (payload.len > max_frame_bytes) return error.FrameTooLarge;
    const header = encodeHeader(action, @intCast(payload.len));
    try writeAll(handle, &header);
    try writeAll(handle, payload);
}
fn receiveFrame(alloc: Allocator, handle: w.HANDLE) !Frame {
    var header: [6]u8 = undefined;
    try readAll(handle, &header);
    const length = std.mem.readInt(u32, header[2..6], .little);
    if (length > max_frame_bytes) return error.FrameTooLarge;
    const payload = try alloc.alloc(u8, length);
    errdefer alloc.free(payload);
    try readAll(handle, payload);
    return .{ .action = std.mem.readInt(u16, header[0..2], .little), .payload = payload };
}
fn readAll(handle: w.HANDLE, bytes: []u8) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        var count: u32 = 0;
        if (api.ReadFile(handle, bytes[offset..].ptr, @intCast(bytes.len - offset), &count, null) == 0)
            return error.PipeReadFailed;
        if (count == 0) return error.EndOfStream;
        offset += count;
    }
}
fn writeAll(handle: w.HANDLE, bytes: []const u8) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        var count: u32 = 0;
        if (api.WriteFile(handle, bytes[offset..].ptr, @intCast(bytes.len - offset), &count, null) == 0)
            return error.PipeWriteFailed;
        if (count == 0) return error.PipeWriteFailed;
        offset += count;
    }
}

test "pipe namespace and six byte little endian header" {
    const name = try pipeName(std.testing.allocator, 1234);
    defer std.testing.allocator.free(name);
    try std.testing.expectEqualStrings("\\\\.\\pipe\\khostty-1234", name);
    try std.testing.expectEqualSlices(u8, &.{ 92, 92, 46, 92 }, name[0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 0x34, 0x12, 4, 3, 2, 1 }, &encodeHeader(0x1234, 0x01020304));
}

test "first instance rejects collision and closes release the name" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    var server = try Server.init(std.testing.allocator, api.GetCurrentProcessId());
    try std.testing.expectError(error.PipeCreateFailed, Server.init(std.testing.allocator, api.GetCurrentProcessId()));
    server.deinit();
    var next = try Server.init(std.testing.allocator, api.GetCurrentProcessId());
    defer next.deinit();
}

test "restricted token cannot connect to the user-only pipe" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    var server = try Server.init(std.testing.allocator, api.GetCurrentProcessId());
    defer server.deinit();
    const wide = try std.unicode.utf8ToUtf16LeAllocZ(std.testing.allocator, server.pipe_name);
    defer std.testing.allocator.free(wide);
    try api.expectRestrictedClientDenied(wide);
}

test "oversize send and disconnected server fail explicitly" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    var server = try Server.init(std.testing.allocator, api.GetCurrentProcessId());
    defer server.deinit();
    try std.testing.expectError(error.NotConnected, server.send(0, ""));
    try std.testing.expectError(error.NotConnected, server.receive());
    const bytes = try std.testing.allocator.alloc(u8, max_frame_bytes + 1);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectError(error.FrameTooLarge, sendFrame(w.INVALID_HANDLE_VALUE, 0, bytes));
}

test "oversize and truncated incoming frames fail without payload leaks" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    const alloc = std.testing.allocator;
    {
        var server = try Server.init(alloc, api.GetCurrentProcessId());
        defer server.deinit();
        var client = try Client.connect(alloc, api.GetCurrentProcessId());
        defer client.deinit();
        _ = try server.acceptConnection();
        const header = encodeHeader(1, max_frame_bytes + 1);
        try writeAll(client.handle, &header);
        try std.testing.expectError(error.FrameTooLarge, server.receive());
    }
    {
        var server = try Server.init(alloc, api.GetCurrentProcessId());
        defer server.deinit();
        var client = try Client.connect(alloc, api.GetCurrentProcessId());
        _ = server.acceptConnection() catch |err| {
            client.deinit();
            return err;
        };
        const header = encodeHeader(1, 4);
        writeAll(client.handle, &header) catch |err| {
            client.deinit();
            return err;
        };
        writeAll(client.handle, "x") catch |err| {
            client.deinit();
            return err;
        };
        client.deinit();
        try std.testing.expectError(error.PipeReadFailed, server.receive());
    }
}
