//! Standalone host integration fixture; echoes transport frames, never app actions.
const std = @import("std");
const ipc = @import("ipc.zig");
const api = @import("ipc_win32.zig");
pub fn main() !void {
    var server = try ipc.Server.init(std.heap.page_allocator, api.GetCurrentProcessId());
    defer server.deinit();
    // Two successive connections exercise reconnect after a client exits.
    for (0..2) |_| {
        _ = try server.acceptConnection();
        for (0..2) |_| {
            const frame = try server.receive();
            defer frame.deinit(std.heap.page_allocator);
            try server.send(frame.action, frame.payload);
        }
        try server.flush();
        try server.disconnect();
    }
}
