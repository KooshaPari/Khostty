//! Windows AppRT tests. Message decoders remain host-runnable; the native
//! lifecycle and Win32 wrappers are only imported on a Windows target.
//! Run: zig build test-windows-apprt -Dtest-filter=<name>

test {
    if (@import("builtin").os.tag == .windows) _ = @import("apprt/windows/App.zig");
    _ = @import("apprt/windows/Window.zig");
    _ = @import("apprt/windows/input.zig");
    if (@import("builtin").os.tag == .windows) _ = @import("apprt/windows/interface.zig");
    _ = @import("apprt/windows/ipc.zig");
    if (@import("builtin").os.tag == .windows) _ = @import("apprt/windows/mod.zig");
    _ = @import("apprt/windows/mouse.zig");
    if (@import("builtin").os.tag == .windows) _ = @import("apprt/windows/renderer.zig");
    _ = @import("apprt/windows/surface.zig");
    if (@import("builtin").os.tag == .windows) _ = @import("apprt/windows/win32api.zig");
}
