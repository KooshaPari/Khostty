//! Test root for the Windows application runtime (`src/apprt/windows/`).
//!
//! Most modules decode Win32 message parameters; their tests are host-runnable.
//! IPC transport tests call Win32 on Windows and skip on other hosts. They cannot
//! be reached by rooting a module at `src/apprt/windows/`: the input modules
//! import `../../input/key.zig` and `../../input/mouse.zig`, which Zig rejects
//! with "import of file outside module path" once the module root is that deep.
//! This file therefore sits directly in `src/`, so the whole apprt stays inside
//! the module, and build.zig's `test-windows-apprt` step gives it the same
//! dependency set as the main test root (`src/main.zig`).
//!
//! `zig build test` does not reach these modules. The Windows runtime is opt-in
//! (`src/apprt.zig` selects it only for `-Dapp-runtime=windows`) and build.zig
//! rejects that combination outside a Windows target, so a host test run has to
//! name the modules directly.
//!
//! Run with: `zig build test-windows-apprt`

test {
    _ = @import("apprt/windows/App.zig");
    _ = @import("apprt/windows/Window.zig");
    _ = @import("apprt/windows/input.zig");
    _ = @import("apprt/windows/interface.zig");
    _ = @import("apprt/windows/ipc.zig");
    _ = @import("apprt/windows/mod.zig");
    _ = @import("apprt/windows/mouse.zig");
    _ = @import("apprt/windows/renderer.zig");
    _ = @import("apprt/windows/surface.zig");
    _ = @import("apprt/windows/win32api.zig");
}
