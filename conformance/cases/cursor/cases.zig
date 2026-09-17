//! Cursor Movement Tests: Position, movement, and cursor state.

pub const Test = struct {
    name: []const u8,
    input: []const u8,
    expected_cur_x: usize,
    expected_cur_y: usize,
    expected_plain: []const u8,
};

/// Helper to create cursor position string
inline fn pos(r: usize, c: usize) [16]u8 {
    return std.fmt.comptimePrint("{d},{d}", .{ r, c });
}

const std = @import("std");

pub const cases = [_]Test{
    .{
        .name = "cursor_up",
        .input = "\x1b[5A",
        .expected_cur_x = 0,
        .expected_cur_y = 0,
        .expected_plain = "",
    },
    .{
        .name = "cursor_down",
        .input = "\x1b[3B",
        .expected_cur_x = 0,
        .expected_cur_y = 3,
        .expected_plain = "",
    },
    .{
        .name = "cursor_right",
        .input = "\x1b[5C",
        .expected_cur_x = 5,
        .expected_cur_y = 0,
        .expected_plain = "",
    },
    .{
        .name = "cursor_left",
        .input = "Hello\x1b[3D",
        .expected_cur_x = 2,
        .expected_cur_y = 0,
        .expected_plain = "Hello",
    },
    .{
        .name = "cursor_position_ch10",
        .input = "\x1b[5;10H",
        .expected_cur_x = 9,
        .expected_cur_y = 4,
        .expected_plain = "",
    },
    .{
        .name = "cursor_home",
        .input = "Hello\x1b[H",
        .expected_cur_x = 0,
        .expected_cur_y = 0,
        .expected_plain = "Hello",
    },
    .{
        .name = "cursor_save_restore",
        .input = "Hello\x1b7World\x1b8",
        .expected_cur_x = 5,
        .expected_cur_y = 0,
        .expected_plain = "HelloWorld",
    },
    .{
        .name = "cursor_esc_home",
        .input = "\x1b[H",
        .expected_cur_x = 0,
        .expected_cur_y = 0,
        .expected_plain = "",
    },
    .{
        .name = "cursor_esc_7",
        .input = "\x1b7",
        .expected_cur_x = 0,
        .expected_cur_y = 0,
        .expected_plain = "",
    },
    .{
        .name = "cursor_esc_8",
        .input = "\x1b8",
        .expected_cur_x = 0,
        .expected_cur_y = 0,
        .expected_plain = "",
    },
    .{
        .name = "cursor_default_param_zero",
        .input = "\x1b[A",
        .expected_cur_x = 0,
        .expected_cur_y = 0,
        .expected_plain = "",
    },
    .{
        .name = "cursor_default_param_zero_down",
        .input = "\x1b[B",
        .expected_cur_x = 0,
        .expected_cur_y = 1,
        .expected_plain = "",
    },
    .{
        .name = "cursor_default_param_zero_right",
        .input = "\x1b[C",
        .expected_cur_x = 1,
        .expected_cur_y = 0,
        .expected_plain = "",
    },
};
