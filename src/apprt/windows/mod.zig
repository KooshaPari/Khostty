//! Experimental Windows application runtime. No Win32 operations are implemented.
pub const App = @import("App.zig");
pub const Window = @import("Window.zig");
pub const Surface = @import("Surface.zig");

/// Resource discovery requires Windows packaging support (G3.4-G3.15).
pub fn resourcesDir(_: @import("std").mem.Allocator) !?[]const u8 {
    return null;
}
