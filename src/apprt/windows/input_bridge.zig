//! Win32 messages -> shared Ghostty encoders. No shell or clipboard side effects.
const std = @import("std");
const Router = @import("input.zig").Router;
const Window = @import("Window.zig");
const Terminal = @import("../../terminal/Terminal.zig");
const key_encode = @import("../../input/key_encode.zig");
const mouse_encode = @import("../../input/mouse_encode.zig");
const core_mouse = @import("../../input/mouse.zig");
const Size = @import("../../renderer/size.zig").Size;

pub const Bridge = struct {
    router: Router = .{},
    any_button: bool = false,
    pos: mouse_encode.Event.Pos = .{},

    pub fn message(self: *Bridge, alloc: std.mem.Allocator, terminal: *Terminal, hwnd: Window.Hwnd, size: Size, msg: u32, wp: usize, lp: isize) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(alloc);
        defer out.deinit();
        var event = self.router.handleMessage(hwnd, msg, wp, lp);
        while (event) |input| : (event = self.router.poll()) {
            switch (input) {
                .key => |original| {
                    var key = original;
                    var control_text: [4]u8 = undefined;
                    // WM_CHAR delivers C0 bytes for Ctrl chords. The shared
                    // encoder needs the printable base character plus modifiers.
                    if (key.utf8.len == 0 and key.mods.ctrl and (msg == 0x102 or msg == 0x106)) {
                        const base: ?u21 = switch (wp) {
                            0 => ' ',
                            1...26 => @intCast(wp + 0x60),
                            27...31 => @intCast(wp + 0x40),
                            0x7f => '?',
                            else => null,
                        };
                        if (base) |cp| {
                            const len = try std.unicode.utf8Encode(cp, &control_text);
                            key.utf8 = control_text[0..len];
                            if (key.unshifted_codepoint == 0) key.unshifted_codepoint = cp;
                        }
                    }
                    // Windows AltGr is synthesized as left Ctrl + right Alt.
                    // Text from WM_CHAR already contains the composed character.
                    if (key.utf8.len > 0 and self.router.mods.ctrl_left and self.router.mods.alt_right) {
                        key.mods.ctrl = false;
                        key.mods.alt = false;
                    }
                    try key_encode.encode(&out.writer, key, .fromTerminal(terminal));
                },
                .mouse => |mouse| {
                    self.pos = mouse.pos;
                    self.any_button = (wp & 0x73) != 0;
                    var opts = mouse_encode.Options.fromTerminal(terminal, size);
                    opts.any_button_pressed = self.any_button;
                    try mouse_encode.encode(&out.writer, mouse, opts);
                },
                .scroll => |scroll| {
                    const axes = [_]f64{ scroll.y, scroll.x };
                    for (axes, 0..) |amount, axis| {
                        const button: core_mouse.Button = if (axis == 0)
                            (if (amount > 0) .four else .five)
                        else
                            (if (amount > 0) .six else .seven);
                        const ticks: usize = @intFromFloat(@abs(amount));
                        for (0..@min(ticks, 1024)) |_| try mouse_encode.encode(&out.writer, .{
                            .action = .press,
                            .button = button,
                            .pos = self.pos,
                            .mods = self.router.mods.mods(),
                        }, .fromTerminal(terminal, size));
                    }
                },
            }
        }
        return out.toOwnedSlice();
    }
};

test "native input bridge arrow AltGr and dead-key encodings" {
    const TerminalType = @import("../../terminal/Terminal.zig");
    var terminal = try TerminalType.init(std.testing.io, std.testing.allocator, .{ .cols = 80, .rows = 24 });
    defer terminal.deinit(std.testing.allocator);
    var token: u8 = 0;
    const hwnd: Window.Hwnd = @ptrCast(&token);
    const size: Size = .{ .screen = .{ .width = 800, .height = 480 }, .cell = .{ .width = 10, .height = 20 }, .padding = .{} };
    var bridge: Bridge = .{};
    const arrow = try bridge.message(std.testing.allocator, &terminal, hwnd, size, 0x100, 0x26, 0);
    defer std.testing.allocator.free(arrow);
    try std.testing.expectEqualStrings("\x1b[A", arrow);
    bridge.router.mods.ctrl_left = true;
    bridge.router.mods.alt_right = true;
    const altgr = try bridge.message(std.testing.allocator, &terminal, hwnd, size, 0x102, '€', 0);
    defer std.testing.allocator.free(altgr);
    try std.testing.expectEqualStrings("€", altgr);
    bridge.router.mods = .{};
    const dead = try bridge.message(std.testing.allocator, &terminal, hwnd, size, 0x103, '^', 0);
    defer std.testing.allocator.free(dead);
    try std.testing.expectEqual(@as(usize, 0), dead.len);
    const composed = try bridge.message(std.testing.allocator, &terminal, hwnd, size, 0x102, 'ê', 0);
    defer std.testing.allocator.free(composed);
    try std.testing.expectEqualStrings("ê", composed);
    bridge.router.mods = .{ .ctrl_left = true };
    const ctrl = try bridge.message(std.testing.allocator, &terminal, hwnd, size, 0x102, 1, 0);
    defer std.testing.allocator.free(ctrl);
    try std.testing.expectEqualStrings("\x01", ctrl);
    bridge.router.mods = .{ .alt_left = true };
    const alt = try bridge.message(std.testing.allocator, &terminal, hwnd, size, 0x106, 'a', 0);
    defer std.testing.allocator.free(alt);
    try std.testing.expectEqualStrings("\x1ba", alt);
    bridge.router.mods = .{};
    const high = try bridge.message(std.testing.allocator, &terminal, hwnd, size, 0x102, 0xd83d, 0);
    defer std.testing.allocator.free(high);
    try std.testing.expectEqual(@as(usize, 0), high.len);
    const low = try bridge.message(std.testing.allocator, &terminal, hwnd, size, 0x102, 0xde00, 0);
    defer std.testing.allocator.free(low);
    try std.testing.expectEqualStrings("😀", low);
}

test "native input bridge mouse mode and bracketed paste controls" {
    const paste = @import("../../input/paste.zig");
    var terminal = try Terminal.init(std.testing.io, std.testing.allocator, .{ .cols = 80, .rows = 24 });
    defer terminal.deinit(std.testing.allocator);
    var stream = terminal.vtStream();
    defer stream.deinit();
    var token: u8 = 0;
    const hwnd: Window.Hwnd = @ptrCast(&token);
    const size: Size = .{ .screen = .{ .width = 800, .height = 480 }, .cell = .{ .width = 10, .height = 20 }, .padding = .{} };
    var bridge: Bridge = .{};
    const disabled = try bridge.message(std.testing.allocator, &terminal, hwnd, size, 0x201, 1, (20 << 16) | 10);
    defer std.testing.allocator.free(disabled);
    try std.testing.expectEqual(@as(usize, 0), disabled.len);
    stream.nextSlice("\x1b[?1000h\x1b[?1006h\x1b[?2004h");
    const enabled = try bridge.message(std.testing.allocator, &terminal, hwnd, size, 0x201, 1, (20 << 16) | 10);
    defer std.testing.allocator.free(enabled);
    try std.testing.expectEqualStrings("\x1b[<0;2;2M", enabled);
    var text = [_]u8{'x'};
    const framed = paste.encode(@as([]u8, &text), .fromTerminal(&terminal));
    try std.testing.expectEqualStrings("\x1b[200~", framed[0]);
    try std.testing.expectEqualStrings("x", framed[1]);
    try std.testing.expectEqualStrings("\x1b[201~", framed[2]);
    stream.nextSlice("\x1b[?2004l");
    const plain = paste.encode(@as([]u8, &text), .fromTerminal(&terminal));
    try std.testing.expectEqual(@as(usize, 0), plain[0].len + plain[2].len);
}
