//! Windows apprt renderer adapter skeleton.
//!
//! Mirrors the generic renderer contract (src/renderer.zig -> src/renderer/generic.zig)
//! but all methods are stubbed returning error.Unimplemented because the Win32
//! rendering layer (Direct2D, OpenGL, or software) is implemented in G3.4+.
//!
//! The adapter is owned by a Surface (src/apprt/windows/surface.zig) and receives
//! calls from that surface's message routing for WM_PAINT, resize, etc.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Window = @import("Window.zig");

/// Renderer adapter stub for Windows.
/// All operations are unimplemented; callers should not rely on this until
/// G3.4+ when real backend rendering is added.
pub const Renderer = struct {
    alloc: Allocator,
    hwnd: Window.Hwnd,

    /// Failures with this error code indicate the underlying Win32 renderer
    /// backend has not yet been implemented.
    pub const Error = error{Unimplemented};

    /// Create a renderer adapter bound to an HWND. Currently no-op.
    pub fn init(alloc: Allocator, hwnd: Window.Hwnd) Error!Renderer {
        _ = alloc;
        _ = hwnd;
        return Error.Unimplemented;
    }

    /// Release any held resources (none at present).
    pub fn deinit(self: *Renderer) void {
        _ = self;
    }

    /// Draw the next frame. No real rendering yet.
    pub fn renderFrame(self: *Renderer) Error!void {
        _ = self;
        return Error.Unimplemented;
    }

    /// Invalidate the client area, schedule a repaint. Stubbed.
    pub fn invalidate(self: *Renderer) Error!void {
        _ = self;
        return Error.Unimplemented;
    }

    /// Resize the render target. Stubbed.
    pub fn resize(self: *Renderer, width: u32, height: u32) Error!void {
        _ = self;
        _ = width;
        _ = height;
        return Error.Unimplemented;
    }
};

test "windows renderer stub" {
    const t = std.testing;
    // init returns Unimplemented; deinit is a no-op.
    const hwnd: Window.Hwnd = undefined;
    try t.expectError(error.Unimplemented, Renderer.init(t.allocator, hwnd));
}
