//! Scroll Region Tests: Scrolling margins and viewport control.

pub const Test = struct {
    name: []const u8,
    input: []const u8,
    expected_top_margin: usize,
    expected_bottom_margin: usize,
    expected_plain: []const u8,
};

pub const cases = [_]Test{
    .{
        .name = "scroll_set_region",
        .input = "\x1b[5;20r",
        .expected_top_margin = 4,
        .expected_bottom_margin = 19,
        .expected_plain = "",
    },
    .{
        .name = "scroll_set_full",
        .input = "\x1b[1;24r",
        .expected_top_margin = 0,
        .expected_bottom_margin = 23,
        .expected_plain = "",
    },
    .{
        .name = "scroll_up",
        .input = "Line 1\nLine 2\nLine 3\n\x1bM",
        .expected_top_margin = 0,
        .expected_bottom_margin = 23,
        .expected_plain = "Line 1\nLine 2\nLine 3\n",
    },
    .{
        .name = "scroll_down",
        .input = "Line 1\nLine 2\nLine 3\n\x1bD",
        .expected_top_margin = 0,
        .expected_bottom_margin = 23,
        .expected_plain = "Line 1\nLine 2\nLine 3\n",
    },
    .{
        .name = "scroll_ind",
        .input = "Line 1\n\x1bD",
        .expected_top_margin = 0,
        .expected_bottom_margin = 23,
        .expected_plain = "Line 1\n",
    },
    .{
        .name = "scroll_ri",
        .input = "\x1bMLine 1\n",
        .expected_top_margin = 0,
        .expected_bottom_margin = 23,
        .expected_plain = "Line 1\n",
    },
    .{
        .name = "scroll_su",
        .input = "Line 1\nLine 2\nLine 3\n\x1b[2S",
        .expected_top_margin = 0,
        .expected_bottom_margin = 23,
        .expected_plain = "Line 1\nLine 2\nLine 3\n",
    },
    .{
        .name = "scroll_sd",
        .input = "\x1b[2T",
        .expected_top_margin = 0,
        .expected_bottom_margin = 23,
        .expected_plain = "",
    },
};