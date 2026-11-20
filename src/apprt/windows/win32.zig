//! Hand-declared Win32 USER32 surface for the Windows AppRT.
//!
//! Zig's Windows target resolves these names from its shipped mingw import
//! libraries, so no `linkSystemLibrary` is required (measured: a probe with
//! `extern "user32"` linked with rc=0 on zig 0.16.0 for
//! x86_64-windows-gnu). Only the declarations the window code actually calls
//! exist here: the window lifecycle, the background brush, and a single
//! fixed-pitch text path. There is no grid, style, colour-pair or cursor
//! rendering here.
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

pub const PAINTSTRUCT = extern struct {
    hdc: ?*anyopaque = null,
    fErase: i32 = 0,
    rcPaint: RECT = .{},
    fRestore: i32 = 0,
    fIncUpdate: i32 = 0,
    rgbReserved: [32]u8 = [_]u8{0} ** 32,
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

// Painting. GDI object creation lives in gdi32; the rest is user32. Zig's
// Windows target links both import libraries, so no build.zig change is needed.
pub extern "user32" fn GetClientRect(hwnd: ?*anyopaque, rect: *RECT) callconv(.winapi) i32;
pub extern "user32" fn FillRect(
    hdc: ?*anyopaque,
    rect: *const RECT,
    brush: ?*anyopaque,
) callconv(.winapi) i32;
pub extern "user32" fn BeginPaint(hwnd: ?*anyopaque, ps: *PAINTSTRUCT) callconv(.winapi) ?*anyopaque;
pub extern "user32" fn EndPaint(hwnd: ?*anyopaque, ps: *const PAINTSTRUCT) callconv(.winapi) i32;
pub extern "gdi32" fn CreateSolidBrush(color: u32) callconv(.winapi) ?*anyopaque;
pub extern "gdi32" fn DeleteObject(object: ?*anyopaque) callconv(.winapi) i32;

// Text. The terminal cell grid is approximated by one fixed-pitch font and a
// fixed row pitch, so the declarations below are exactly the ones that path
// uses: create a font, measure it, select it into the paint DC, and emit a
// run of UTF-16 text per row.

/// A `COLORREF` is `0x00BBGGRR`; only the low three bytes are meaningful.
pub const TEXT_COLOR_LIGHT: u32 = 0x00e0e0e0;

/// `LOGFONT` argument values used by `CreateFontW`.
pub const FW_NORMAL: i32 = 400;
pub const DEFAULT_CHARSET: u32 = 1;
pub const OUT_DEFAULT_PRECIS: u32 = 0;
pub const CLIP_DEFAULT_PRECIS: u32 = 0;
pub const DEFAULT_QUALITY: u32 = 0;
/// `FIXED_PITCH` is a low bit, `FF_MODERN` a `FF_*` family in the high byte.
pub const FIXED_PITCH: u32 = 1;
pub const FF_MODERN: u32 = 48;

/// `SetBkMode`: leave the background behind the glyphs untouched so the row
/// fill shows through.
pub const TRANSPARENT: i32 = 1;

/// `MultiByteToWideChar` code page for UTF-8.
pub const CP_UTF8: u32 = 65001;

/// `TEXTMETRICW` from `wingdi.h`. Eleven `LONG`s, four `WCHAR`s, five `BYTE`s;
/// the C layout pads the tail to 60 bytes on x64.
pub const TEXTMETRICW = extern struct {
    tmHeight: i32 = 0,
    tmAscent: i32 = 0,
    tmDescent: i32 = 0,
    tmInternalLeading: i32 = 0,
    tmExternalLeading: i32 = 0,
    tmAveCharWidth: i32 = 0,
    tmMaxCharWidth: i32 = 0,
    tmWeight: i32 = 0,
    tmOverhang: i32 = 0,
    tmDigitizedAspectX: i32 = 0,
    tmDigitizedAspectY: i32 = 0,
    tmFirstChar: u16 = 0,
    tmLastChar: u16 = 0,
    tmDefaultChar: u16 = 0,
    tmBreakChar: u16 = 0,
    tmItalic: u8 = 0,
    tmUnderlined: u8 = 0,
    tmStruckOut: u8 = 0,
    tmPitchAndFamily: u8 = 0,
    tmCharSet: u8 = 0,
};

/// Negative height means "a character cell this many pixels tall", which is
/// how a screen font is requested at a fixed pixel size rather than in points.
pub extern "gdi32" fn CreateFontW(
    height: i32,
    width: i32,
    escapement: i32,
    orientation: i32,
    weight: i32,
    italic: u32,
    underline: u32,
    strike_out: u32,
    charset: u32,
    out_precision: u32,
    clip_precision: u32,
    quality: u32,
    pitch_and_family: u32,
    face: ?[*:0]const u16,
) callconv(.winapi) ?*anyopaque;
pub extern "gdi32" fn SelectObject(
    hdc: ?*anyopaque,
    object: ?*anyopaque,
) callconv(.winapi) ?*anyopaque;
pub extern "gdi32" fn GetTextMetricsW(
    hdc: ?*anyopaque,
    metrics: *TEXTMETRICW,
) callconv(.winapi) i32;
pub extern "gdi32" fn SetTextColor(hdc: ?*anyopaque, color: u32) callconv(.winapi) u32;
pub extern "gdi32" fn SetBkMode(hdc: ?*anyopaque, mode: i32) callconv(.winapi) i32;
pub extern "gdi32" fn TextOutW(
    hdc: ?*anyopaque,
    x: i32,
    y: i32,
    string: [*]const u16,
    len: i32,
) callconv(.winapi) i32;
pub extern "gdi32" fn CreateCompatibleDC(hdc: ?*anyopaque) callconv(.winapi) ?*anyopaque;
pub extern "gdi32" fn DeleteDC(hdc: ?*anyopaque) callconv(.winapi) i32;

/// `src` is borrowed and need not be NUL-terminated; `dst_len` bounds the
/// write. The return value is the number of UTF-16 units written, or 0 for an
/// empty string, and `src_len` is `i32` because that is the Win32 signature.
pub extern "kernel32" fn MultiByteToWideChar(
    codepage: u32,
    flags: u32,
    src: [*]const u8,
    src_len: i32,
    dst: ?[*]u16,
    dst_len: i32,
) callconv(.winapi) i32;
