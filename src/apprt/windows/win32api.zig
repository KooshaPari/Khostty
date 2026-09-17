//! Win32 API declarations for the Windows app runtime.
//! This file is a skeleton stub providing the minimal FFI needed for the
//! surface and renderer adapters. Actual implementation of functions
//! (e.g., CreateWindowExW, BeginPaintW) is deferred to a follow-up task
//! (G3.4+).
//!
//! These declarations mirror the official Windows SDK types from
//! `winuser.h` / `wingdi.h` but are intentionally incomplete.
//! All API calls are commented out; the stubs return placeholder values
//! or do nothing so compilation succeeds without linking.

const std = @import("std");

pub const HWND = std.os.windows.HWND;
pub const HINSTANCE = std.os.windows.HINSTANCE;
pub const HMONITOR = std.os.windows.HMONITOR;
pub const WNDCLASS = std.os.windows.WNDCLASSW;
pub const WNDCLASSEX = std.os.windows.WNDCLASSEXW;
pub const HBRUSH = std.os.windows.HBRUSH;
pub const HICON = std.os.windows.HICON;
pub const HCURSOR = std.os.windows.HCURSOR;
pub const DWORD = std.os.windows.DWORD;
pub const UINT = std.os.windows.UINT;
pub const INT = std.os.windows.INT;
pub const LPARAM = std.os.windows.LPARAM;
pub const WPARAM = std.os.windows.WPARAM;
pub const LRESULT = std.os.windows.LRESULT;
pub const BOOL = std.os.windows.BOOL;
pub const RECT = std.os.windows.RECT;
pub const POINT = std.os.windows.POINT;
pub const PAINTSTRUCT = std.os.windows.PAINTSTRUCT;

/// Message constants from WinUser.h.
pub const WM_SIZE: u32 = 0x0005;
pub const WM_PAINT: u32 = 0x000F;
pub const WM_CLOSE: u32 = 0x0010;
pub const WM_DESTROY: u32 = 0x0002;
pub const WM_ERASEBKGND: u32 = 0x0014;

/// Size request types for WM_SIZE lParam wParam.
pub const SIZE_RESTORED: u32 = 0;
pub const SIZE_MINIMIZED: u32 = 1;
pub const SIZE_MAXIMIZED: u32 = 2;

/// Window style constants (partial).
pub const WS_OVERLAPPEDWINDOW: DWORD = 0xCF0000;
pub const WS_VISIBLE: DWORD = 0x10000000;
pub const CS_HREDRAW: u32 = 0x0001;
pub const CS_VREDRAW: u32 = 0x0002;

/// Standard cursors.
pub const IDC_ARROW: c_int = 32512;
pub const IDC_IBEAM: c_int = 32513;
pub const IDC_HAND: c_int = 32649;

/// Return type for MessageBoxW.
pub const IDOK: c_int = 1;
pub const IDCANCEL: c_int = 2;

/// Placeholder stub functions. Real implementation is pending.
pub const kernel32 = struct {
    pub const GetModuleHandleW = std.os.windows.kernel32.GetModuleHandleW;
    pub const GetLastError = std.os.windows.kernel32.GetLastError;
};

pub const user32 = struct {
    pub const DefWindowProcW = std.os.windows.user32.DefWindowProcW;
    pub const RegisterClassExW = std.os.windows.user32.RegisterClassExW;
    pub const CreateWindowExW = std.os.windows.user32.CreateWindowExW;
    pub const ShowWindow = std.os.windows.user32.ShowWindow;
    pub const UpdateWindow = std.os.windows.user32.UpdateWindow;
    pub const GetMessageW = std.os.windows.user32.GetMessageW;
    pub const TranslateMessage = std.os.windows.user32.TranslateMessage;
    pub const DispatchMessageW = std.os.windows.user32.DispatchMessageW;
    pub const BeginPaint = std.os.windows.user32.BeginPaint;
    pub const EndPaint = std.os.windows.user32.EndPaint;
    pub const InvalidateRect = std.os.windows.user32.InvalidateRect;
    pub const DestroyWindow = std.os.windows.user32.DestroyWindow;
    pub const MessageBoxW = std.os.windows.user32.MessageBoxW;
};

pub const dwmapi = struct {
    pub const EnableMMCSS = std.os.windows.dwmapi.EnableMMCSS;
    pub const SetWindowAttribute = std.os.windows.dwmapi.SetWindowAttribute;
};
