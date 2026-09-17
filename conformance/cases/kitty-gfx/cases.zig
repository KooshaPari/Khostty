//! Kitty Graphics Tests: Image protocol sequences.

pub const Test = struct {
    name: []const u8,
    input: []const u8,
    expected_action: []const u8,
    expected_uri: ?[]const u8,
    expected_width: ?usize,
    expected_height: ?usize,
};

pub const cases = [_]Test{
    .{
        .name = "kitty_init",
        .input = "\x1b_Gi=32;a=s;c=32;k=16;s=100;t=100;f=24;v=1\x1b\\",
        .expected_action = "Init",
        .expected_uri = null,
        .expected_width = null,
        .expected_height = null,
    },
    .{
        .name = "kitty_progress",
        .input = "\x1b_Gp=1;f=100\x1b\\",
        .expected_action = "Progress",
        .expected_uri = null,
        .expected_width = null,
        .expected_height = null,
    },
    .{
        .name = "kitty_end",
        .input = "\x1b_Gm=1\x1b\\",
        .expected_action = "End",
        .expected_uri = null,
        .expected_width = null,
        .expected_height = null,
    },
    .{
        .name = "kitty_reset",
        .input = "\x1b_Gm=2\x1b\\",
        .expected_action = "Reset",
        .expected_uri = null,
        .expected_width = null,
        .expected_height = null,
    },
    .{
        .name = "kitty_transparency",
        .input = "\x1b_Gd=100\x1b\\",
        .expected_action = "Transparency",
        .expected_uri = null,
        .expected_width = null,
        .expected_height = null,
    },
};