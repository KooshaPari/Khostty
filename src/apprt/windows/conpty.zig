//! ConPTY C ownership wrapper. All returned output remains private to the caller.
const std = @import("std");
pub const Pty = opaque {};
extern fn khostty_pty_new(u16, u16, ?[*:0]const u16, *?*Pty) i32;
extern fn khostty_pty_close(*Pty) i32;
extern fn khostty_pty_read(*Pty, [*]u8, u32, *u32) i32;
extern fn khostty_pty_write(*Pty, [*]const u8, u32) i32;
extern fn khostty_pty_resize(*Pty, u16, u16) i32;
extern fn khostty_pty_alive(*Pty) c_int;
extern fn khostty_pty_pid(*Pty) u32;
extern fn khostty_pty_active(*Pty, *u32) i32;

pub fn create(cols: u16, rows: u16, command: ?[*:0]const u16) !*Pty {
    var result: ?*Pty = null;
    try check(khostty_pty_new(cols, rows, command, &result));
    return result orelse error.PtyInitializationFailed;
}
pub fn close(pty: *Pty) !void {
    try check(khostty_pty_close(pty));
}
pub fn read(pty: *Pty, buffer: []u8) !usize {
    var len: u32 = 0;
    try check(khostty_pty_read(pty, buffer.ptr, @intCast(buffer.len), &len));
    return len;
}
pub fn write(pty: *Pty, bytes: []const u8) !void {
    try check(khostty_pty_write(pty, bytes.ptr, @intCast(bytes.len)));
}
pub fn resize(pty: *Pty, cols: u16, rows: u16) !void {
    try check(khostty_pty_resize(pty, cols, rows));
}
pub fn alive(pty: *Pty) bool {
    return khostty_pty_alive(pty) != 0;
}
pub fn pid(pty: *Pty) u32 {
    return khostty_pty_pid(pty);
}
pub fn active(pty: *Pty) !u32 {
    var count: u32 = 0;
    try check(khostty_pty_active(pty, &count));
    return count;
}
fn check(hr: i32) !void {
    if (hr < 0) {
        std.log.err("ConPTY HRESULT=0x{x}", .{@as(u32, @bitCast(hr))});
        return error.ConPtyFailed;
    }
}

test "native ConPTY shell output resize input and cleanup" {
    const api = @import("win32api.zig");
    const command = std.unicode.utf8ToUtf16LeStringLiteral("cmd.exe /d /q");
    const pty = try create(80, 24, command);
    var closed = false;
    defer if (!closed) {
        close(pty) catch {};
    };
    const child = api.c.OpenProcess(api.c.SYNCHRONIZE, 0, pid(pty)) orelse return error.ProcessHandleFailed;
    defer _ = api.c.CloseHandle(child);
    try resize(pty, 100, 30);
    try write(pty, "echo KH_ConPTY_^roundtrip\r\n");
    var data: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer data.deinit();
    var found = false;
    for (0..500) |_| {
        var buffer: [4096]u8 = undefined;
        const len = try read(pty, &buffer);
        try data.writer.writeAll(buffer[0..len]);
        if (std.mem.indexOf(u8, data.written(), "KH_ConPTY_roundtrip") != null) {
            found = true;
            break;
        }
        api.c.Sleep(10);
    }
    try std.testing.expect(found);
    try std.testing.expect(alive(pty));
    try write(pty, "ping -n 30 127.0.0.1\r\n");
    var started = false;
    for (0..200) |_| {
        if (try active(pty) >= 2) {
            started = true;
            break;
        }
        api.c.Sleep(10);
    }
    try std.testing.expect(started);
    // A created process may not have attached its console/handler yet.
    // Wait for an actual reply before injecting the interrupt.
    data.clearRetainingCapacity();
    var ready = false;
    for (0..300) |_| {
        var buffer: [4096]u8 = undefined;
        const len = try read(pty, &buffer);
        try data.writer.writeAll(buffer[0..len]);
        if (std.mem.indexOf(u8, data.written(), "TTL=") != null) {
            ready = true;
            break;
        }
        api.c.Sleep(10);
    }
    try std.testing.expect(ready);
    try write(pty, "\x03");
    var interrupted = false;
    for (0..300) |_| {
        if (try active(pty) == 1) {
            interrupted = true;
            break;
        }
        api.c.Sleep(10);
    }
    try std.testing.expect(interrupted);
    try std.testing.expect(alive(pty));
    try close(pty);
    closed = true;
    try std.testing.expectEqual(@as(api.c.DWORD, api.c.WAIT_OBJECT_0), api.c.WaitForSingleObject(child, 5000));
}
