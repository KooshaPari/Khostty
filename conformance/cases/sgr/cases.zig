//! SGR Tests: Select Graphic Rendition escape sequences.

pub const Test = struct {
    name: []const u8,
    input: []const u8,
    expected_plain: []const u8,
    expected_attributes: ?Attributes,
};

pub const Attributes = struct {
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    strikethrough: bool = false,
    reverse: bool = false,
    color: Color = .none,
};

pub const Color = union(enum) {
    none: void,
    rgb: struct { r: u8, g: u8, b: u8 },
    index: u8,
};

pub const cases = [_]Test{
    .{
        .name = "sgr_reset_all",
        .input = "\x1b[0m",
        .expected_plain = "",
        .expected_attributes = null,
    },
    .{
        .name = "sgr_bold",
        .input = "\x1b[1mText",
        .expected_plain = "Text",
        .expected_attributes = Attributes{ .bold = true },
    },
    .{
        .name = "sgr_dim",
        .input = "\x1b[2mText",
        .expected_plain = "Text",
        .expected_attributes = Attributes{},
    },
    .{
        .name = "sgr_italic",
        .input = "\x1b[3mText",
        .expected_plain = "Text",
        .expected_attributes = Attributes{ .italic = true },
    },
    .{
        .name = "sgr_underline",
        .input = "\x1b[4mText",
        .expected_plain = "Text",
        .expected_attributes = Attributes{ .underline = true },
    },
    .{
        .name = "sgr_blink",
        .input = "\x1b[5mText",
        .expected_plain = "Text",
        .expected_attributes = Attributes{},
    },
    .{
        .name = "sgr_reverse",
        .input = "\x1b[7mText",
        .expected_plain = "Text",
        .expected_attributes = Attributes{ .reverse = true },
    },
    .{
        .name = "sgr_conceal",
        .input = "\x1b[8mText",
        .expected_plain = "Text",
        .expected_attributes = Attributes{},
    },
    .{
        .name = "sgr_strikethrough",
        .input = "\x1b[9mText",
        .expected_plain = "Text",
        .expected_attributes = Attributes{ .strikethrough = true },
    },
    .{
        .name = "sgr_rgb_fg_red",
        .input = "\x1b[38;2;255;0;0mX",
        .expected_plain = "X",
        .expected_attributes = Attributes{ .color = Color.rgb{ .r = 255, .g = 0, .b = 0 } },
    },
    .{
        .name = "sgr_rgb_bg_green",
        .input = "\x1b[48;2;0;255;0mX",
        .expected_plain = "X",
        .expected_attributes = Attributes{ .color = Color.rgb{ .r = 0, .g = 255, .b = 0 } },
    },
    .{
        .name = "sgr_256_fg",
        .input = "\x1b[38;5;196mX",
        .expected_plain = "X",
        .expected_attributes = Attributes{ .color = Color.index(196) },
    },
    .{
        .name = "sgr_combined_bold_underline",
        .input = "\x1b[1;4mText",
        .expected_plain = "Text",
        .expected_attributes = Attributes{ .bold = true, .underline = true },
    },
    .{
        .name = "sgr_reset_specific_bold",
        .input = "\x1b[22mText",
        .expected_plain = "Text",
        .expected_attributes = null,
    },
    .{
        .name = "sgr_reset_default_fg",
        .input = "\x1b[39mText",
        .expected_plain = "Text",
        .expected_attributes = null,
    },
};
