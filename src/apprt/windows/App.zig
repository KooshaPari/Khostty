//! Windows application lifecycle: Win32 window-class registration, one
//! top-level window owned by this scaffold, and the message pump.
//!
//! Scope: a visible, correctly-sized window whose WM_SIZE is recorded by the
//! Surface, whose background is painted with a solid-colour brush, and which
//! draws the visible viewport of the focused terminal as plain fixed-pitch
//! text with GDI. There is no cell grid, no per-cell style, no colour pairs,
//! no cursor and no selection rendering: this is a text path, not a renderer.
//!
//! The text path reaches terminal content through the core app
//! (`focused_surface`) rather than through this module's `Surface`, because
//! nothing in the Windows runtime yet calls `core.Surface.init` with a typed
//! AppRT surface. In practice `focused_surface` is null, so today the window
//! paints its background and reports that it has no terminal content; the
//! drawing code below is exercised only once a core surface is wired up.
const App = @This();
const std = @import("std");
const global = @import("../../global.zig");
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

/// Byte capacity of one viewport dump. The paint path may not allocate, so a
/// dump larger than this is truncated instead of grown. A 200x50 viewport of
/// 4-byte graphemes is well inside it; a very wide, very tall window is not.
const text_capacity = 16 * 1024;

/// UTF-16 capacity of a single drawn row. A row wider than this in columns is
/// truncated; 1024 columns needs a ~20000px window.
const line_capacity = 1024;

/// Pixel height requested for the font. Negative means "cell height in
/// pixels" rather than points, so the grid does not scale with DPI.
const font_height: i32 = 16;

/// Drawn in place of terminal text while no core surface is attached. This is
/// not terminal output and must never be mistaken for it: it exists so the GDI
/// text path is observable on Windows before the core surface wiring exists,
/// and it disappears as soon as a viewport dump produces any text.
const status_text = "khostty: no terminal attached (Windows AppRT)";

/// `L"Consolas"`, a monospace face present on every supported Windows. If it
/// is missing, GDI substitutes another face and the columns stop lining up,
/// but the text still draws.
const font_face = [_:0]u16{ 'C', 'o', 'n', 's', 'o', 'l', 'a', 's' };

/// Fixed-pitch font for the text path, created on first paint and deleted in
/// `terminate`. Module-level like the brush, for the same reason: the window
/// procedure is static.
var text_font: ?*anyopaque = null;

/// Row pitch in pixels, taken from the created font's metrics. Distinct from
/// `font_height` because GDI's cell height includes ascent, descent and
/// internal leading.
var cell_height: i32 = font_height;

hwnd: ?*anyopaque = null,
instance: ?*anyopaque = null,
registered: bool = false,
surface: Surface = .{},

/// The core app, borrowed. Used to find the focused core surface, which owns
/// the terminal and the render state mutex. Null in unit tests.
core: ?*CoreApp = null,

pub fn init(self: *App, core: *CoreApp, _: struct {}) !void {
    self.core = core;
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
                _ = win32.SetWindowLongPtrW(hwnd, win32.GWLP_USERDATA, @bitCast(@intFromPtr(app)));
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
            if (appFromWindow(hwnd)) |app| {
                app.paint(hwnd, hdc);
            } else if (backgroundBrush()) |brush| {
                // No App yet: WM_PAINT can arrive before WM_CREATE has stored
                // the pointer. Background only.
                var rect: win32.RECT = undefined;
                if (win32.GetClientRect(hwnd, &rect) != 0) {
                    _ = win32.FillRect(hdc, &rect, brush);
                }
            }
            _ = win32.EndPaint(hwnd, &ps);
            return 0;
        },
        win32.WM_SIZE => {
            if (appFromWindow(hwnd)) |app| {
                if (app.surface.handleMessage(msg, wparam, lparam)) |result| return result;
            }
        },
        else => {},
    }
    return win32.DefWindowProcW(hwnd, msg, wparam, lparam);
}

/// Recover the App bound to `hwnd` by WM_CREATE. Returns null before the
/// pointer is stored, which is why the paint path still paints a background.
fn appFromWindow(hwnd: ?*anyopaque) ?*App {
    const raw = win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA);
    if (raw == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(raw)));
}

/// Fill the client area, then draw terminal text, or the status row when no
/// terminal text is reachable.
fn paint(self: *App, hwnd: ?*anyopaque, hdc: ?*anyopaque) void {
    var rect: win32.RECT = undefined;
    if (win32.GetClientRect(hwnd, &rect) == 0) return;
    const brush = backgroundBrush() orelse return;
    _ = win32.FillRect(hdc, &rect, brush);

    var buf: [text_capacity]u8 = undefined;
    if (self.viewportText(&buf)) |text| {
        if (text.len > 0) {
            drawText(hdc, text, rect);
            return;
        }
    }
    drawText(hdc, status_text, rect);
}

/// Dump the visible viewport of the focused core surface as plain text.
///
/// Returns null when there is no core surface to read, which is the state of
/// this runtime today: `src/App.zig` only ever sets `focused_surface` when an
/// AppRT creates a core surface, and no Windows runtime path does that yet
/// (see `src/apprt/windows/mod.zig`, which never calls
/// `core.Surface.init`). Returning null is the honest answer in that state,
/// not a placeholder to be filled in later.
fn viewportText(self: *App, buf: []u8) ?[]const u8 {
    const core = self.core orelse return null;
    const surface = core.focused_surface orelse return null;

    // Same contract as `src/apprt/embedded.zig`: terminal state is only valid
    // under the render state mutex. The unlocked read it replaces is the
    // `dumpText` path, which takes a selection we do not have.
    const state = &surface.renderer_state;
    state.mutex.lockUncancelable(global.io());
    defer state.mutex.unlock(global.io());

    const screen = state.terminal.screens.active;
    var writer: std.Io.Writer = .fixed(buf);
    screen.dumpString(&writer, .{
        .tl = screen.pages.getTopLeft(.viewport),
        // Without an explicit bottom-right the dump runs to the bottom of the
        // whole screen, which is the end of scrollback, not the window. The
        // viewport bottom may be unpinned (a scrolled-up window), hence the
        // fallback.
        .br = screen.pages.getBottomRight(.viewport) orelse
            screen.pages.getBottomRight(.screen),
        // Paint is not a reflow pass: keep trailing blanks instead of
        // reporting a truncation.
        .unwrap = false,
    }) catch {
        // Buffer exhausted (a wider viewport than `text_capacity`). Draw the
        // rows that fit rather than nothing.
        return writer.buffered();
    };
    return writer.buffered();
}

/// Draw `text` as one row per '\n', top-left aligned, at the font's row pitch.
/// Rows that fall outside `client` are skipped, so a wide window shows the top
/// of the screen instead of overdrawing the frame.
fn drawText(hdc: ?*anyopaque, text: []const u8, client: win32.RECT) void {
    const font = terminalFont() orelse return;
    const previous_font = win32.SelectObject(hdc, font);
    defer _ = win32.SelectObject(hdc, previous_font);

    _ = win32.SetBkMode(hdc, win32.TRANSPARENT);
    _ = win32.SetTextColor(hdc, win32.TEXT_COLOR_LIGHT);

    var wide: [line_capacity]u16 = undefined;
    var y = client.top;
    var rows = std.mem.splitScalar(u8, text, '\n');
    while (rows.next()) |row| {
        if (y + cell_height > client.bottom) break;
        const len = utf8ToWide(row, &wide) orelse break;
        if (len > 0) _ = win32.TextOutW(hdc, client.left, y, &wide, len);
        y += cell_height;
    }
}

/// The one fixed-pitch font, created on first use.
fn terminalFont() ?*anyopaque {
    if (text_font) |font| return font;
    const font = win32.CreateFontW(
        -font_height,
        0,
        0,
        0,
        win32.FW_NORMAL,
        0, // italic
        0, // underline
        0, // strike out
        win32.DEFAULT_CHARSET,
        win32.OUT_DEFAULT_PRECIS,
        win32.CLIP_DEFAULT_PRECIS,
        win32.DEFAULT_QUALITY,
        win32.FIXED_PITCH | win32.FF_MODERN,
        &font_face,
    ) orelse return null;
    text_font = font;

    // The requested pixel size is a glyph height, not a row pitch. Measure the
    // face to get the pitch, so rows do not overlap. Without a readable metric
    // the requested height is used, which is close enough to be legible.
    if (fontMetrics(font)) |metrics| {
        if (metrics.tmHeight > 0) cell_height = metrics.tmHeight;
    }
    return font;
}

/// Read the metrics of `font` through a memory DC, because a font is only
/// measurable while it is selected into a device context.
fn fontMetrics(font: ?*anyopaque) ?win32.TEXTMETRICW {
    const dc = win32.CreateCompatibleDC(null);
    if (dc == null) return null;
    defer _ = win32.DeleteDC(dc);

    const previous = win32.SelectObject(dc, font);
    defer _ = win32.SelectObject(dc, previous);

    var metrics: win32.TEXTMETRICW = .{};
    if (win32.GetTextMetricsW(dc, &metrics) == 0) return null;
    return metrics;
}

/// Convert one row of UTF-8 to UTF-16 for `TextOutW`. Returns null if the row
/// cannot be converted (invalid UTF-8) or does not fit `out`.
fn utf8ToWide(row: []const u8, out: []u16) ?i32 {
    if (row.len == 0) return 0;
    if (row.len > out.len) return null;
    const len = win32.MultiByteToWideChar(
        win32.CP_UTF8,
        0,
        row.ptr,
        @intCast(row.len),
        out.ptr,
        @intCast(out.len),
    );
    if (len <= 0) return null;
    return len;
}

/// Release the native window and class. Safe when nothing was created.
pub fn terminate(self: *App) void {
    if (text_font) |font| {
        _ = win32.DeleteObject(font);
        text_font = null;
    }
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

// The paint path's reachability boundary is the one thing that can be tested
// without a Win32 device context or a live core app, so it is asserted here
// rather than left as a comment: with no core app there is no terminal content
// and the window must fall back to its background fill.
test "no terminal text is reachable without a core surface" {
    const testing = std.testing;

    var app: App = .{};
    var buf: [text_capacity]u8 = undefined;
    try testing.expectEqual(@as(?[]const u8, null), app.viewportText(&buf));
}
