//! Edge Case Tests: Incomplete sequences, invalid parameters, boundary conditions.

pub const Test = struct {
    name: []const u8,
    input: []const u8,
    expected_plain: []const u8,
};

pub const cases = [_]Test{
    .{
        .name = "incomplete_esc_bracket",
        .input = "\x1b[",
        .expected_plain = "",
    },
    .{
        .name = "incomplete_csi_param",
        .input = "\x1b[1;",
        .expected_plain = "",
    },
    .{
        .name = "unrecognized_escape",
        .input = "\x1bZ",
        .expected_plain = "",
    },
    .{
        .name = "empty_string",
        .input = "",
        .expected_plain = "",
    },
    .{
        .name = "null_like",
        .input = "\x00\x00\x00",
        .expected_plain = "",
    },
    .{
        .name = "very_long_osc",
        .input = "\x1b]0;" ++ std.mem.repeat(u8, 0, 1000) ++ "\x07",
        .expected_plain = "",
    },
    .{
        .name = "mixed_sequences",
        .input = "\x1b[1;31mHello\x1b[0m World\x1b[44mTest\x1b[0m",
        .expected_plain = "Hello World Test",
    },
    .{
        .name = "unicode_char",
        .input = "\u{00E9}\u{00E8}\u{00EA}",
        .expected_plain = "\u{00E9}\u{00E8}\u{00EA}",
    },
    .{
        .name = "wide_char_test",
        .input = "\u{4E2D}\u{6587}",
        .expected_plain = "\u{4E2D}\u{6587}",
    },
    .{
        .name = "tab_expansion",
        .input = "\t\t\t",
        .expected_plain = "   ",
    },
    .{
        .name = "cr_lf",
        .input = "\r\n\r\n",
        .expected_plain = "\n\n",
    },
    .{
        .name = "bell",
        .input = "\x07",
        .expected_plain = "",
    },
    .{
        .name = "backspace",
        .input = "\x08",
        .expected_plain = "",
    },
    .{
        .name = "del_char",
        .input = "\x7f",
        .expected_plain = "",
    },
    .{
        .name = "invalid_sgr_param",
        .input = "\x1b[999m",
        .expected_plain = "",
    },
    .{
        .name = "negative_param",
        .input = "\x1b[-5m",
        .expected_plain = "",
    },
    .{
        .name = "zero_size_cursor",
        .input = "\x1b[0;0H",
        .expected_plain = "",
    },
};