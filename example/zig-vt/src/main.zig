const std = @import("std");
const ghostty_vt = @import("ghostty-vt");

pub fn main(init: std.process.Init) !void {
    // Initialize a terminal.
    var t: ghostty_vt.Terminal = try .init(init.io, init.gpa, .{
        .cols = 6,
        .rows = 40,
    });
    defer t.deinit(init.gpa);

    // Write some text. It'll wrap because this is too long for our
    // columns size above (6).
    try t.printString("Hello, World!");

    // Get the plain string view of the terminal screen.
    const str = try t.plainString(init.gpa);
    defer init.gpa.free(str);
    std.debug.print("{s}\n", .{str});
}

test "printString wraps at the declared width" {
    var t: ghostty_vt.Terminal = try .init(std.testing.io, std.testing.allocator, .{
        .cols = 3,
        .rows = 10,
    });
    defer t.deinit(std.testing.allocator);

    try t.printString("abcd");

    const wrapped = try t.plainString(std.testing.allocator);
    defer std.testing.allocator.free(wrapped);
    const unwrapped = try t.plainStringUnwrapped(std.testing.allocator);
    defer std.testing.allocator.free(unwrapped);

    try std.testing.expectEqualStrings("abc\nd", wrapped);
    try std.testing.expectEqualStrings("abcd", unwrapped);
}

test "printString treats a newline as carriage return plus linefeed" {
    var t: ghostty_vt.Terminal = try .init(std.testing.io, std.testing.allocator, .{
        .cols = 20,
        .rows = 5,
    });
    defer t.deinit(std.testing.allocator);

    try t.printString("a\nb");

    const unwrapped = try t.plainStringUnwrapped(std.testing.allocator);
    defer std.testing.allocator.free(unwrapped);
    try std.testing.expectEqualStrings("a\nb", unwrapped);
}
