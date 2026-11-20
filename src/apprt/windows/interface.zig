//! Windows AppRT contract, using GTK's standalone application lifecycle.
//!
//! App implements init(*App, *CoreApp, struct {}) !void, run() !void,
//! terminate() void, wakeup() void, performAction(target, comptime action,
//! value) !bool, performIpc(allocator, target, comptime action, value) !bool,
//! and redrawInspector(*Surface) void with the same signatures as GTK.
//! Embedded uses host callbacks and different init options, not a native loop.
//!
//! Stub status for G3.4-G3.15:
//! - init, registerWindowClass and run create a real Win32 window (class
//!   registration, top-level window, message pump). Nothing is painted.
//! - performAction and performIpc still fail with error.Unimplemented.
//! - terminate destroys the native window and class when one exists; wakeup
//!   posts a message to unblock the pump; redrawInspector is a no-op.
//! - Window.init and Surface.init fail with error.Unimplemented.
//! - Window.handle and Surface.nativeWindow are null until explicitly attached.
//! - resourcesDir returns an empty ResourcesDir (both paths absent).
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

test "Windows App declares a native lifecycle" {
    var app: App = .{};
    // The lifecycle is native now, so it is asserted structurally: creating a
    // window needs a Win32 message queue that a test process does not own.
    try std.testing.expect(@hasDecl(App, "registerWindowClass"));
    try std.testing.expect(@hasDecl(App, "run"));
    try std.testing.expectEqual(null, app.hwnd);
    app.wakeup();
    app.terminate();
}

test "Windows Surface construction remains unavailable" {
    try std.testing.expectError(error.Unimplemented, Surface.init());
}
