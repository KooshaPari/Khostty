//! Experimental Windows runtime with native window lifecycle; terminal rendering is pending.
pub const App = @import("App.zig");
pub const Window = @import("Window.zig");
pub const Surface = @import("surface.zig");

/// Resource discovery requires Windows packaging support (G3.4-G3.15).
pub fn resourcesDir(_: @import("std").mem.Allocator) !@import("../../os/resourcesdir.zig").ResourcesDir {
    return .{};
}
