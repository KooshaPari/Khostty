const std = @import("std");
const ghostty_vt = @import("ghostty-vt");

pub fn main(init: std.process.Init) !void {
    var t: ghostty_vt.Terminal = try .init(init.io, init.gpa, .{ .cols = 80, .rows = 24 });
    defer t.deinit(init.gpa);

    // Create a read-only VT stream for parsing terminal sequences
    var stream = t.vtStream();
    defer stream.deinit();

    // Basic text with newline
    stream.nextSlice("Hello, World!\r\n");

    // ANSI color codes: ESC[1;32m = bold green, ESC[0m = reset
    stream.nextSlice("\x1b[1;32mGreen Text\x1b[0m\r\n");

    // Cursor positioning: ESC[1;1H = move to row 1, column 1
    stream.nextSlice("\x1b[1;1HTop-left corner\r\n");

    // Cursor movement: ESC[5B = move down 5 lines
    stream.nextSlice("\x1b[5B");
    stream.nextSlice("Moved down!\r\n");

    // Erase line: ESC[2K = clear entire line
    stream.nextSlice("\x1b[2K");
    stream.nextSlice("New content\r\n");

    // Multiple lines
    stream.nextSlice("Line A\r\nLine B\r\nLine C\r\n");

    // Get the final terminal state as a plain string
    const str = try t.plainString(init.gpa);
    defer init.gpa.free(str);
    std.debug.print("{s}\n", .{str});
}

test "stream renders text, cursor moves and line erase" {
    var t: ghostty_vt.Terminal = try .init(std.testing.io, std.testing.allocator, .{
        .cols = 40,
        .rows = 10,
    });
    defer t.deinit(std.testing.allocator);

    var stream = t.vtStream();
    defer stream.deinit();

    stream.nextSlice("one\r\ntwo");
    const first = try t.plainStringUnwrapped(std.testing.allocator);
    defer std.testing.allocator.free(first);
    try std.testing.expectEqualStrings("one\ntwo", first);

    // cursor positioning puts text at the requested row instead of appending
    stream.nextSlice("\x1b[1;1HTOP");
    const moved = try t.plainStringUnwrapped(std.testing.allocator);
    defer std.testing.allocator.free(moved);
    try std.testing.expect(std.mem.startsWith(u8, moved, "TOP"));

    // erase line removes the contents of the current row
    stream.nextSlice("\x1b[2;1H\x1b[2K");
    const erased = try t.plainStringUnwrapped(std.testing.allocator);
    defer std.testing.allocator.free(erased);
    try std.testing.expect(std.mem.indexOf(u8, erased, "two") == null);
}
