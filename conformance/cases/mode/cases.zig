//! Mode Set/Reset Tests: DEC Private Mode sequences.

pub const Test = struct {
    name: []const u8,
    input: []const u8,
    expected_active_mode: []const u8,
    expected_mode_reversed: bool,
};

pub const cases = [_]Test{
    .{
        .name = "mode_decckm_horiz",
        .input = "\x1b[?1l",
        .expected_active_mode = "Normal Cursor",
        .expected_mode_reversed = false,
    },
    .{
        .name = "mode_decckm_app",
        .input = "\x1b[?1h",
        .expected_active_mode = "Application Cursor",
        .expected_mode_reversed = true,
    },
    .{
        .name = "mode_deccnm_origin",
        .input = "\x1b[?6l",
        .expected_active_mode = "Normal Mode",
        .expected_mode_reversed = false,
    },
    .{
        .name = "mode_deccnm_app",
        .input = "\x1b[?6h",
        .expected_active_mode = "Origin Mode",
        .expected_mode_reversed = true,
    },
    .{
        .name = "mode_decscnm_reverse",
        .input = "\x1b[?5h",
        .expected_active_mode = "Reverse Video",
        .expected_mode_reversed = true,
    },
    .{
        .name = "mode_decscnm_normal",
        .input = "\x1b[?5l",
        .expected_active_mode = "Normal Video",
        .expected_mode_reversed = false,
    },
    .{
        .name = "mode_decawm_autowrap",
        .input = "\x1b?7h",
        .expected_active_mode = "Auto Wrap",
        .expected_mode_reversed = true,
    },
    .{
        .name = "mode_decawm_noautowrap",
        .input = "\x1b?7l",
        .expected_active_mode = "No Auto Wrap",
        .expected_mode_reversed = false,
    },
    .{
        .name = "mode_decom_origin",
        .input = "\x1b[?25h",
        .expected_active_mode = "Cursor Visible",
        .expected_mode_reversed = false,
    },
    .{
        .name = "mode_decarm_8bit",
        .input = "\x1b[?3h",
        .expected_active_mode = "8-Bit Mode",
        .expected_mode_reversed = true,
    },
    .{
        .name = "mode_decarm_7bit",
        .input = "\x1b[3l",
        .expected_active_mode = "7-Bit Mode",
        .expected_mode_reversed = false,
    },
    .{
        .name = "mode_decim",
        .input = "\x1b[4l",
        .expected_active_mode = "Insert Mode Off",
        .expected_mode_reversed = false,
    },
    .{
        .name = "mode_decipam",
        .input = "\x1b[?25l",
        .expected_active_mode = "Cursor Hidden",
        .expected_mode_reversed = false,
    },
    .{
        .name = "mode_decilm",
        .input = "\x1b[9m",
        .expected_active_mode = "Conceal",
        .expected_mode_reversed = true,
    },
    .{
        .name = "mode_riscap",
        .input = "\x1b[?2004l",
        .expected_active_mode = "No Clickable",
        .expected_mode_reversed = false,
    },
};