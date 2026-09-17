//! Win32 input message router for the Windows app runtime.
//!
//! `Router` turns the `WM_*` messages of a window procedure into Ghostty input
//! events. It owns the cross-message state that the per-message decoders in
//! `keyboard.zig` and `mouse.zig` deliberately do not: the key press waiting for
//! its text, and the wheel remainder.
//!
//! ## Dispatch
//!
//! | Message group                          | Event     | Callback |
//! |----------------------------------------|-----------|----------|
//! | WM_KEYDOWN/UP, WM_SYSKEYDOWN/UP        | `.key`    | `Surface.keyCallback` |
//! | WM_CHAR, WM_SYSCHAR, WM_UNICHAR        | `.key`    | `Surface.keyCallback`, completes the pending press |
//! | WM_DEADCHAR, WM_SYSDEADCHAR            | `.key` (composing) | `Surface.keyCallback` |
//! | WM_MOUSEMOVE, WM_*BUTTONDOWN/UP        | `.mouse`  | `Surface.mouseButtonCallback`, `Surface.cursorPosCallback` |
//! | WM_MOUSELEAVE                          | `.mouse` (motion at -1,-1) | `Surface.cursorPosCallback` |
//! | WM_MOUSEWHEEL, WM_MOUSEHWHEEL          | `.scroll` | `Surface.scrollCallback` |
//! | anything else                          | null      | `DefWindowProcW` |
//!
//! No Win32 function is called, so `hwnd` is accepted only to match the window
//! procedure signature.
//!
//! ## Merge contract
//!
//! Win32 delivers the physical key and the layout text of one key press in two
//! separate messages, and the core needs both in a single `input.KeyEvent` (see
//! the module documentation of `keyboard.zig`). The router therefore defers a
//! key-down that may produce text:
//!
//! 1. The key-down is held in `deferred` and produces no event.
//! 2. The char message that follows completes it, and the merged event is
//!    returned.
//! 3. If no char message arrives, the next key message or a call to `flush`
//!    emits the press with empty text.
//!
//! A key release that resolves a still-deferred press yields two events, so
//! `handleMessage` returns the *next* event in order rather than necessarily the
//! event for the message it was given. Callers must drain with `poll` until it
//! returns null before assuming the queue is empty.

const std = @import("std");
const key = @import("../../input/key.zig");
const core_mouse = @import("../../input/mouse.zig");
const mouse_encode = @import("../../input/mouse_encode.zig");

const keyboard = @import("keyboard.zig");
const win_mouse = @import("mouse.zig");
const Window = @import("Window.zig");

const log = std.log.scoped(.win32_input);

/// Win32 message parameters. Both decoders use the same ABI types.
pub const WPARAM = keyboard.WPARAM;
pub const LPARAM = keyboard.LPARAM;

/// An input event produced by a window message.
pub const InputEvent = union(enum) {
    /// A keyboard event, for `Surface.keyCallback`.
    key: key.KeyEvent,
    /// A pointer event, for `Surface.mouseButtonCallback` for button actions and
    /// `Surface.cursorPosCallback` for motion.
    mouse: mouse_encode.Event,
    /// A wheel event, for `Surface.scrollCallback`.
    scroll: win_mouse.ScrollEvent,
};

/// Routes Win32 input messages to Ghostty input events.
pub const Router = struct {
    /// Keyboard text decoding: surrogate pairing and the UTF-8 buffer.
    decoder: keyboard.Decoder = .{},
    /// Tracked modifier state for key messages. Overwrite this with
    /// authoritative state from `GetKeyState` when it is available.
    mods: keyboard.ModifierState = .{},
    /// Mouse decoding, which owns the wheel accumulator.
    mouse: win_mouse.Translator = .{},

    /// A key press whose char message has not arrived yet.
    deferred: ?key.KeyEvent = null,

    /// Events translated but not yet taken by the caller. One message can resolve
    /// two events, so two slots suffice.
    out: [2]InputEvent = .{ .{ .key = .{} }, .{ .key = .{} } },
    out_len: usize = 0,

    /// Decode one window message and return the next input event, if any.
    ///
    /// The caller must keep calling `poll` until it returns null so that a
    /// message which resolved two events does not drop the second one.
    pub fn handleMessage(
        self: *Router,
        hwnd: Window.Hwnd,
        msg: u32,
        wParam: WPARAM,
        lParam: LPARAM,
    ) ?InputEvent {
        _ = hwnd;

        switch (msg) {
            keyboard.WM_KEYDOWN,
            keyboard.WM_KEYUP,
            keyboard.WM_CHAR,
            keyboard.WM_DEADCHAR,
            keyboard.WM_SYSKEYDOWN,
            keyboard.WM_SYSKEYUP,
            keyboard.WM_SYSCHAR,
            keyboard.WM_SYSDEADCHAR,
            keyboard.WM_UNICHAR,
            => self.onKeyboard(msg, wParam, lParam),

            // Every other message is offered to the mouse decoder, which returns
            // null for messages it does not own.
            else => if (self.mouse.translate(msg, wParam, lParam)) |event| {
                self.push(switch (event) {
                    .pointer => |e| .{ .mouse = e },
                    .scroll => |e| .{ .scroll = e },
                });
            },
        }

        return self.poll();
    }

    /// Return the next queued event, or null when the queue is empty.
    pub fn poll(self: *Router) ?InputEvent {
        if (self.out_len == 0) return null;

        const event = self.out[0];
        self.out[0] = self.out[1];
        self.out_len -= 1;
        return event;
    }

    /// Emit a deferred key press whose text never arrived. The apprt must call
    /// this when input stops (WM_KILLFOCUS, WM_CLOSE) so the press is not lost.
    pub fn flush(self: *Router) void {
        self.flushDeferred();
    }

    /// Drop all pending input, for example when the window loses focus.
    pub fn reset(self: *Router) void {
        self.deferred = null;
        self.decoder.reset();
        self.out_len = 0;
    }

    fn onKeyboard(self: *Router, msg: u32, wParam: WPARAM, lParam: LPARAM) void {
        const info = keyboard.KeyInfo.fromLParam(lParam);
        const vk: u8 = @truncate(wParam);

        switch (msg) {
            keyboard.WM_KEYDOWN, keyboard.WM_SYSKEYDOWN => {
                // A new key press proves the previous one produced no text.
                self.flushDeferred();

                const is_modifier = self.mods.applyKey(vk, info);
                const event = keyboard.keyEvent(vk, info, self.mods);

                if (is_modifier or !keyboard.mayProduceText(vk, self.mods)) {
                    self.push(.{ .key = event });
                } else {
                    self.deferred = event;
                }
            },

            keyboard.WM_KEYUP, keyboard.WM_SYSKEYUP => {
                // A release while a press is still deferred means no text
                // arrived, so the press is queued first and the release follows.
                self.flushDeferred();

                _ = self.mods.applyKey(vk, info);
                self.push(.{ .key = keyboard.keyEvent(vk, info, self.mods) });
            },

            keyboard.WM_CHAR, keyboard.WM_SYSCHAR, keyboard.WM_UNICHAR => {
                const cp = if (msg == keyboard.WM_UNICHAR)
                    self.decoder.decodeUnichar(@truncate(wParam))
                else
                    self.decoder.decode(@truncate(wParam));
                if (cp) |codepoint| self.emitText(codepoint);
            },

            keyboard.WM_DEADCHAR, keyboard.WM_SYSDEADCHAR => {
                const cp = self.decoder.decode(@truncate(wParam)) orelse return;
                var event = self.takeDeferred();
                self.decoder.applyDeadChar(&event, cp);
                self.push(.{ .key = event });
            },

            else => {},
        }
    }

    /// Complete the pending key press with the text of a char message, or emit a
    /// standalone text event when no key press preceded it.
    fn emitText(self: *Router, cp: u21) void {
        var event = self.takeDeferred();
        self.decoder.applyText(&event, cp);
        self.push(.{ .key = event });
    }

    /// Take the deferred key press, substituting an unidentified press when none
    /// is waiting. This happens for synthetic input such as an on-screen
    /// keyboard, which sends char messages on their own.
    fn takeDeferred(self: *Router) key.KeyEvent {
        const event = self.deferred orelse return .{
            .action = .press,
            .key = .unidentified,
            .mods = self.mods.mods(),
        };
        self.deferred = null;
        return event;
    }

    fn flushDeferred(self: *Router) void {
        const pending = self.deferred orelse return;
        self.deferred = null;
        self.push(.{ .key = pending });
    }

    fn push(self: *Router, event: InputEvent) void {
        if (self.out_len == self.out.len) {
            log.warn("input event queue full, dropping event", .{});
            return;
        }

        self.out[self.out_len] = event;
        self.out_len += 1;
    }
};

// ── Tests ───────────────────────────────────────────────────────────────────

/// The router never dereferences the window handle; this matches the test style
/// of `surface.zig`.
const test_hwnd: Window.Hwnd = undefined;

/// Build a key-message `lParam`. Only the scan code, extended flag and transition
/// bits matter to the router.
fn keyLParam(scan: u8, opts: struct { extended: bool = false, up: bool = false }) LPARAM {
    var bits: usize = @as(usize, 1) | (@as(usize, scan) << 16);
    if (opts.extended) bits |= @as(usize, 1) << 24;
    if (opts.up) bits |= @as(usize, 1) << 31;
    return @bitCast(bits);
}

test "key press and its char message produce one merged event" {
    const t = std.testing;
    var router: Router = .{};

    // Shift down is emitted immediately: a modifier never produces text.
    const shift = router.handleMessage(test_hwnd, keyboard.WM_KEYDOWN, keyboard.VK_SHIFT, keyLParam(0x2A, .{})).?;
    try t.expectEqual(key.Key.shift_left, shift.key.key);
    try t.expect(shift.key.mods.shift);

    // 'A' down is deferred because its text is still to come.

    try t.expectEqual(null, router.handleMessage(test_hwnd, keyboard.WM_KEYDOWN, keyboard.VK_A, keyLParam(0x1E, .{})));

    const event = router.handleMessage(test_hwnd, keyboard.WM_CHAR, 'A', keyLParam(0x1E, .{})).?;
    try t.expectEqual(key.Action.press, event.key.action);
    try t.expectEqual(key.Key.key_a, event.key.key);
    try t.expect(event.key.mods.shift);
    try t.expectEqualStrings("A", event.key.utf8);
    try t.expectEqual(@as(u21, 'a'), event.key.unshifted_codepoint);
    try t.expectEqual(null, router.poll());

    // The release is a separate event.
    const release = router.handleMessage(test_hwnd, keyboard.WM_KEYUP, keyboard.VK_A, keyLParam(0x1E, .{ .up = true })).?;
    try t.expectEqual(key.Action.release, release.key.action);
    try t.expectEqual(key.Key.key_a, release.key.key);
}

test "function keys are emitted immediately" {
    const t = std.testing;
    var router: Router = .{};

    const event = router.handleMessage(test_hwnd, keyboard.WM_KEYDOWN, keyboard.VK_F1, keyLParam(0x3B, .{})).?;
    try t.expectEqual(key.Key.f1, event.key.key);
    try t.expectEqual(null, router.deferred);
    try t.expectEqual(null, router.poll());

    // Ctrl+K arrives as the C0 byte 0x0B, which must not become text.
    try t.expectEqual(null, router.handleMessage(test_hwnd, keyboard.WM_KEYDOWN, keyboard.VK_A + 10, keyLParam(0x25, .{})));
    const ctrl = router.handleMessage(test_hwnd, keyboard.WM_CHAR, 0x0B, keyLParam(0x25, .{})).?;
    try t.expectEqualStrings("", ctrl.key.utf8);
    try t.expectEqual(key.Key.key_k, ctrl.key.key);
}

test "a release resolves a stale deferred press before itself" {
    const t = std.testing;
    var router: Router = .{};

    // A key whose char message never arrives (an input method swallowed it).
    try t.expectEqual(null, router.handleMessage(test_hwnd, keyboard.WM_KEYDOWN, keyboard.VK_A, keyLParam(0x1E, .{})));

    // The release queues both the press and the release, in that order.
    const press = router.handleMessage(test_hwnd, keyboard.WM_KEYUP, keyboard.VK_A, keyLParam(0x1E, .{ .up = true })).?;
    try t.expectEqual(key.Action.press, press.key.action);
    try t.expectEqualStrings("", press.key.utf8);

    const release = router.poll().?;
    try t.expectEqual(key.Action.release, release.key.action);
    try t.expectEqual(null, router.poll());

    // `flush` covers the focus-loss path.
    try t.expectEqual(null, router.handleMessage(test_hwnd, keyboard.WM_KEYDOWN, keyboard.VK_A + 1, keyLParam(0x30, .{})));
    router.flush();
    try t.expectEqual(key.Key.key_b, router.poll().?.key.key); // VK_B

    router.reset();
    try t.expectEqual(null, router.poll());
    try t.expectEqual(null, router.deferred);
}

test "mouse and wheel messages route to their events" {
    const t = std.testing;
    var router: Router = .{};

    // Left click at (12, 34) with Ctrl held.
    const lparam: usize = 12 | (@as(usize, 34) << 16);
    const click = router.handleMessage(test_hwnd, win_mouse.WM_LBUTTONDOWN, win_mouse.MK_LBUTTON | win_mouse.MK_CONTROL, @bitCast(lparam)).?;
    try t.expectEqual(core_mouse.Action.press, click.mouse.action);
    try t.expectEqual(core_mouse.Button.left, click.mouse.button.?);
    try t.expect(click.mouse.mods.ctrl);
    try t.expectEqual(@as(f32, 12), click.mouse.pos.x);
    try t.expectEqual(@as(f32, 34), click.mouse.pos.y);

    // Wheel up.
    const up: WPARAM = @as(WPARAM, @bitCast(@as(isize, win_mouse.WHEEL_DELTA))) << 16;
    const scroll = router.handleMessage(test_hwnd, win_mouse.WM_MOUSEWHEEL, up, 0).?.scroll;
    try t.expectEqual(@as(f64, 1), scroll.y);
    try t.expectEqual(@as(f64, 0), scroll.x);
    try t.expect(!scroll.mods.precision);

    // A sub-tick wheel delta produces no event.
    try t.expectEqual(null, router.handleMessage(test_hwnd, win_mouse.WM_MOUSEWHEEL, @as(WPARAM, 60) << 16, 0));

    // Unrelated messages are ignored so the pump can call DefWindowProcW.
    try t.expectEqual(null, router.handleMessage(test_hwnd, 0x0005, 0, 0));
    try t.expectEqual(null, router.handleMessage(test_hwnd, 0x000F, 0, 0));
    try t.expectEqual(null, router.poll());
}
