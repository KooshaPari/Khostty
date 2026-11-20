//! Windows application lifecycle: Win32 window-class registration, one
//! top-level window owned by this scaffold, and the message pump.
//!
//! Scope: a visible, correctly-sized window whose WM_SIZE is recorded by the
//! Surface, and whose background is painted with a solid-colour brush. No
//! text/grid rendering, input translation or terminal-grid resize exists yet.
const App = @This();
const CoreApp = @import("../../App.zig");
const ipc = @import("../../apprt.zig").ipc;
const win32 = @import("win32.zig");
const Surface = @import("surface.zig");

/// Class and window names are UTF-16 with a NUL sentinel, which is the form
/// every Win32 `W` entry point expects. Zig has no `L"..."` literal form, so
/// the arrays are spelled out.
const class_name = [_:0]u16{ 'k', 'h', 'o', 's', 't', 't', 'y' };
const window_title = [_:0]u16{ 'k', 'h', 'o', 's', 't', 't', 'y' };

/// Set for the duration of CreateWindowExW so the class's static window
/// procedure can reach the owning App while WM_CREATE arrives. A scaffold
/// process owns at most one window.
var creating: ?*App = null;

/// Background colour for the client area, Win32 `COLORREF` (`0x00BBGGRR`).
/// The apprt has no reachable theme/background config yet, so this is an
/// explicit fallback rather than a configured colour.
const BACKGROUND_FALLBACK: u32 = 0x00101010;

/// The scaffold process owns at most one window (see `creating`), and the
/// window procedure is static, so the brush is module-level rather than a
/// struct field. Created lazily on first paint, deleted in `terminate`.
var background_brush: ?*anyopaque = null;

fn backgroundBrush() ?*anyopaque {
    if (background_brush == null) {
        background_brush = win32.CreateSolidBrush(BACKGROUND_FALLBACK);
    }
    return background_brush;
}

hwnd: ?*anyopaque = null,
instance: ?*anyopaque = null,
registered: bool = false,
surface: Surface = .{},

pub fn init(self: *App, _: *CoreApp, _: struct {}) !void {
    self.instance = win32.GetModuleHandleW(null);
    try self.registerWindowClass();
    // Create the window now so the Surface has a real HWND to attach to
    // before the pump runs. Nothing is shown until run().
    _ = try self.createWindow();
}

/// Register the `khostty` window class for this module instance. Idempotent.
pub fn registerWindowClass(self: *App) !void {
    if (self.registered) return;
    const wc: win32.WNDCLASSEXW = .{
        .lpfnWndProc = &wndProc,
        .hInstance = self.instance,
        .hbrBackground = null,
        .lpszClassName = &class_name,
    };
    if (win32.RegisterClassExW(&wc) == 0) return error.RegisterClassFailed;
    self.registered = true;
}

pub fn run(self: *App) !void {
    const hwnd = self.hwnd orelse (try self.createWindow()).?;
    _ = win32.ShowWindow(hwnd, win32.SW_SHOW);
    _ = win32.UpdateWindow(hwnd);

    var msg: win32.MSG = undefined;
    while (win32.GetMessageW(&msg, null, 0, 0) > 0) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageW(&msg);
    }
}

/// Create the top-level window and bind the Surface to its handle.
/// `core_surface` is the opaque App pointer: the typed core-Surface bridge
/// does not exist yet, and surface.zig never dereferences the handle.
fn createWindow(self: *App) !?*anyopaque {
    creating = self;
    defer creating = null;
    const hwnd = win32.CreateWindowExW(
        0,
        &class_name,
        &window_title,
        win32.WS_OVERLAPPEDWINDOW,
        100,
        100,
        800,
        600,
        null,
        null,
        self.instance,
        null,
    );
    if (hwnd == null) return error.CreateWindowFailed;
    self.hwnd = hwnd;
    self.surface.attach(@ptrCast(hwnd.?), @ptrCast(self));
    return hwnd;
}

/// Window procedure for the `khostty` class. Static because Win32 stores a
/// bare function pointer; state is reached through GWLP_USERDATA.
fn wndProc(
    hwnd: ?*anyopaque,
    msg: u32,
    wparam: usize,
    lparam: isize,
) callconv(.winapi) isize {
    switch (msg) {
        win32.WM_CREATE => {
            if (creating) |app| {
                _ = win32.SetWindowLongPtrW(hwnd, win32.GWLP_USERDATA, @bitCast(@intFromPtr(&app.surface)));
            }
            return 0;
        },
        win32.WM_DESTROY => {
            win32.PostQuitMessage(0);
            return 0;
        },
        // Erase: fill the client rect with the cached brush and claim the
        // erase so DefWindowProcW does not paint the class background.
        win32.WM_ERASEBKGND => {
            if (wparam == 0) return 0;
            const hdc: *anyopaque = @ptrFromInt(wparam);
            const brush = backgroundBrush() orelse return 0;
            var rect: win32.RECT = undefined;
            if (win32.GetClientRect(hwnd, &rect) == 0) return 0;
            _ = win32.FillRect(hdc, &rect, brush);
            return 1;
        },
        // Paint: all drawing happens between BeginPaint and EndPaint so the
        // update region is validated and cleared by the system.
        win32.WM_PAINT => {
            var ps: win32.PAINTSTRUCT = undefined;
            const hdc = win32.BeginPaint(hwnd, &ps);
            if (hdc == null) return 0;
            if (backgroundBrush()) |brush| {
                var rect: win32.RECT = undefined;
                if (win32.GetClientRect(hwnd, &rect) != 0) {
                    _ = win32.FillRect(hdc, &rect, brush);
                }
            }
            _ = win32.EndPaint(hwnd, &ps);
            return 0;
        },
        win32.WM_SIZE => {
            const raw = win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA);
            if (raw != 0) {
                const surface: *Surface = @ptrFromInt(@as(usize, @intCast(raw)));
                if (surface.handleMessage(msg, wparam, lparam)) |result| return result;
            }
        },
        else => {},
    }
    return win32.DefWindowProcW(hwnd, msg, wparam, lparam);
}

/// Release the native window and class. Safe when nothing was created.
pub fn terminate(self: *App) void {
    if (background_brush) |brush| {
        _ = win32.DeleteObject(brush);
        background_brush = null;
    }
    if (self.hwnd) |hwnd| {
        _ = win32.DestroyWindow(hwnd);
        self.hwnd = null;
    }
    self.surface.deinit();
    if (self.registered) {
        _ = win32.UnregisterClassW(&class_name, self.instance);
        self.registered = false;
    }
}

/// Post a wakeup message so a blocked GetMessageW returns. The scaffold does
/// not act on it yet; it only unblocks the pump. It must NOT reuse WM_SIZE:
/// that carries a client-area size in lparam, so a wakeup sent as WM_SIZE
/// would teach the Surface a bogus 0x0 size on every tick.
pub fn wakeup(self: *App) void {
    if (self.hwnd) |hwnd| {
        _ = win32.PostMessageW(hwnd, win32.WM_APP + 1, 0, 0);
    }
}

pub fn performAction(
    _: *App,
    _: @import("../../apprt.zig").Target,
    comptime action: @import("../../apprt.zig").Action.Key,
    _: @import("../../apprt.zig").Action.Value(action),
) error{Unimplemented}!bool {
    return error.Unimplemented;
}

/// Errors that a runtime able to build an executable may return from
/// `performIpc`.
///
/// `src/cli/new_window.zig`, `src/cli/new_tab.zig` and
/// `src/cli/toggle_quick_terminal.zig` all `switch` on the caught error and
/// name `error.IPCFailed`, so a runtime that produces the `ghostty` executable
/// must declare that member. `src/apprt/embedded.zig` does the same by naming
/// `apprt.ipc.Errors` in its return type. Narrowing this set to only the errors
/// this scaffold actually returns breaks every one of those call sites.
pub const PerformIpcError = ipc.Errors || error{
    /// No Win32 transport exists yet, so no IPC can be attempted.
    Unimplemented,
};

pub fn performIpc(
    _: @import("std").mem.Allocator,
    _: ipc.Target,
    comptime action: ipc.Action.Key,
    _: ipc.Action.Value(action),
) PerformIpcError!bool {
    return error.Unimplemented;
}

/// Inspector UI is unavailable in the scaffold.
pub fn redrawInspector(_: *App, _: *@import("surface.zig")) void {}
