//! Charset Switching Tests: Character set selection and switching.

pub const Test = struct {
    name: []const u8,
    input: []const u8,
    expected_charset: []const u8,
};

pub const cases = [_]Test{
    .{
        .name = "charset_g0_uk",
        .input = "\x1b(A",
        .expected_charset = "UK",
    },
    .{
        .name = "charset_g0_us",
        .input = "\x1b(B",
        .expected_charset = "US",
    },
    .{
        .name = "charset_g1_line_drawing",
        .input = "\x1b)0",
        .expected_charset = "Line Drawing",
    },
    .{
        .name = "charset_g1_british",
        .input = "\x1b)1",
        .expected_charset = "British",
    },
    .{
        .name = "charset_ss2",
        .input = "\x0e",
        .expected_charset = "G1",
    },
    .{
        .name = "charset_ss3",
        .input = "\x0f",
        .expected_charset = "G2",
    },
    .{
        .name = "charset_lock_g1",
        .input = "\x1b~",
        .expected_charset = "G1 Lock",
    },
    .{
        .name = "charset_lock_g0",
        .input = "\x1bn",
        .expected_charset = "G0 Lock",
    },
};