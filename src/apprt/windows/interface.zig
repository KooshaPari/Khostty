//! Windows AppRT contract, using GTK's standalone application lifecycle.
//!
//! App implements init(*App, *CoreApp, struct {}) !void, run() !void,
//! terminate() void, wakeup() void, performAction(target, comptime action,
//! value) !bool, performIpc(allocator, target, comptime action, value) !bool,
//! and redrawInspector(*Surface) void with the same signatures as GTK.
//! Embedded uses host callbacks and different init options, not a native loop.
//!
//! Native lifecycle: App registers a process-scoped window class, creates an
//! HWND, shows it, and pumps messages until WM_DESTROY posts WM_QUIT.
//! Window and Surface construction, core actions and IPC remain unavailable.
//! The Win32 host tests exercise an invisible native window without capture.
//!
//! Surface's HWND association is maintained separately in surface.zig. The
//! future core bridge must supply GTK's core() *CoreSurface, rtApp() *App,
//! close(bool), cgroup() ?[]const u8, getTitle() ?[:0]const u8,
//! getContentScale() !ContentScale, getSize() !SurfaceSize,
//! getCursorPos() !CursorPos, supportsClipboard(Clipboard) bool,
//! clipboardRequest(Clipboard, ClipboardRequest) !ClipboardReadResult,
//! setClipboard(Clipboard, []const ClipboardContent, bool) !void,
//! defaultTermioEnv() !std.process.Environ.Map, and redrawInspector() void.
//! These core/clipboard/render hooks are NOT implemented by this scaffold.
//! Selection of this runtime does not imply a usable Windows terminal.
const std = @import("std");
pub const App = @import("App.zig");
pub const Window = @import("Window.zig");
pub const Surface = @import("surface.zig");

comptime {
    for (.{ "init", "run", "terminate", "wakeup", "performAction", "performIpc", "redrawInspector", "registerWindowClass" }) |name| {
        if (!@hasDecl(App, name)) @compileError("Windows App missing " ++ name);
    }
}

test "native App initialization and termination release the HWND" {
    const api = @import("win32api.zig");
    // init currently only needs the core identity, not initialized core state.
    var core: @import("../../App.zig") = undefined;
    core.alloc = std.testing.allocator;
    var app: App = .{};
    try std.testing.expectError(error.WindowNotInitialized, app.run());
    try app.init(&core, .{});
    defer app.terminate();
    try app.registerWindowClass();
    const hwnd = app.hwnd;
    try std.testing.expect(api.c.IsWindow(hwnd) != 0);
    app.wakeup();
    app.terminate();
    try std.testing.expectEqual(null, app.hwnd);
    try std.testing.expectEqual(null, app.previous_dpi);
    try std.testing.expect(api.c.IsWindow(hwnd) == 0);
    // DestroyWindow posts quit. Drain it so it cannot end another test's loop.
    var msg: api.c.MSG = undefined;
    while (api.c.PeekMessageW(&msg, null, 0, 0, api.c.PM_REMOVE) != 0) {}
}

test "Windows Surface construction remains unavailable" {
    try std.testing.expectError(error.Unimplemented, Surface.init());
}
