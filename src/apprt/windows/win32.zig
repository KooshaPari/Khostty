//! Hand-declared Win32 USER32 surface for the Windows AppRT.
//!
//! Zig's Windows target resolves these names from its shipped mingw import
//! libraries, so no `linkSystemLibrary` is required (measured: a probe with
//! `extern "user32"` linked with rc=0 on zig 0.16.0 for
//! x86_64-windows-gnu). Only the declarations the window scaffold actually
//! calls exist here: no GDI, no rendering, no input translation.
//!
//! Widening rules used below: WPARAM is `usize`, LPARAM/LRESULT are `isize`,
//! handles are `?*anyopaque` (null is a legal handle value on Win32).

pub const WM_CREATE: u32 = 0x0001;
pub const WM_DESTROY: u32 = 0x0002;
pub const WM_SIZE: u32 = 0x0005;
pub const WM_PAINT: u32 = 0x000f;
pub const WM_ERASEBKGND: u32 = 0x0014;

/// First message in the application-private range (WM_APP). Anything at or
/// above this is ours; the window procedure must not read a system meaning
/// into it. `wakeup` uses WM_APP + 1 purely to unblock `GetMessageW`.
pub const WM_APP: u32 = 0x8000;

pub const WS_OVERLAPPEDWINDOW: u32 = 0x00CF0000;
pub const SW_SHOW: i32 = 5;
/// Index for the per-window user data slot; negative by Win32 convention.
pub const GWLP_USERDATA: i32 = -21;

pub const POINT = extern struct {
    x: i32 = 0,
    y: i32 = 0,
};

pub const RECT = extern struct {
    left: i32 = 0,
    top: i32 = 0,
    right: i32 = 0,
    bottom: i32 = 0,
};

pub const MSG = extern struct {
    hwnd: ?*anyopaque = null,
    message: u32 = 0,
    wParam: usize = 0,
    lParam: isize = 0,
    time: u32 = 0,
    pt: POINT = .{},
};

pub const WNDPROC = *const fn (
    hwnd: ?*anyopaque,
    msg: u32,
    wparam: usize,
    lparam: isize,
) callconv(.winapi) isize;

pub const WNDCLASSEXW = extern struct {
    cbSize: u32 = @sizeOf(WNDCLASSEXW),
    style: u32 = 0,
    lpfnWndProc: ?WNDPROC = null,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: ?*anyopaque = null,
    hIcon: ?*anyopaque = null,
    hCursor: ?*anyopaque = null,
    hbrBackground: ?*anyopaque = null,
    lpszMenuName: ?[*:0]const u16 = null,
    lpszClassName: ?[*:0]const u16 = null,
    hIconSm: ?*anyopaque = null,
};

pub extern "user32" fn RegisterClassExW(*const WNDCLASSEXW) callconv(.winapi) u16;
pub extern "user32" fn CreateWindowExW(
    ex_style: u32,
    class_name: ?[*:0]const u16,
    window_name: ?[*:0]const u16,
    style: u32,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    parent: ?*anyopaque,
    menu: ?*anyopaque,
    instance: ?*anyopaque,
    param: ?*anyopaque,
) callconv(.winapi) ?*anyopaque;
pub extern "user32" fn DefWindowProcW(
    hwnd: ?*anyopaque,
    msg: u32,
    wparam: usize,
    lparam: isize,
) callconv(.winapi) isize;
pub extern "user32" fn ShowWindow(hwnd: ?*anyopaque, cmd: i32) callconv(.winapi) i32;
pub extern "user32" fn UpdateWindow(hwnd: ?*anyopaque) callconv(.winapi) i32;
pub extern "user32" fn GetMessageW(
    msg: *MSG,
    hwnd: ?*anyopaque,
    filter_min: u32,
    filter_max: u32,
) callconv(.winapi) i32;
pub extern "user32" fn TranslateMessage(*const MSG) callconv(.winapi) i32;
pub extern "user32" fn DispatchMessageW(*const MSG) callconv(.winapi) isize;
pub extern "user32" fn PostQuitMessage(exit_code: i32) callconv(.winapi) void;
pub extern "user32" fn PostMessageW(
    hwnd: ?*anyopaque,
    msg: u32,
    wparam: usize,
    lparam: isize,
) callconv(.winapi) i32;
pub extern "user32" fn DestroyWindow(hwnd: ?*anyopaque) callconv(.winapi) i32;
pub extern "user32" fn UnregisterClassW(
    class_name: ?[*:0]const u16,
    instance: ?*anyopaque,
) callconv(.winapi) i32;
pub extern "user32" fn GetModuleHandleW(name: ?[*:0]const u16) callconv(.winapi) ?*anyopaque;
pub extern "user32" fn SetWindowLongPtrW(
    hwnd: ?*anyopaque,
    index: i32,
    value: isize,
) callconv(.winapi) isize;
pub extern "user32" fn GetWindowLongPtrW(hwnd: ?*anyopaque, index: i32) callconv(.winapi) isize;
