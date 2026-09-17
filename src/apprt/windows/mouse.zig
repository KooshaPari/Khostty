//! Win32 mouse messages to Ghostty mouse events.
//!
//! ## Message model
//!
//! | Message                                | Action  | Coordinates |
//! |----------------------------------------|---------|-------------|
//! | WM_MOUSEMOVE                           | motion  | client      |
//! | WM_LBUTTONDOWN / WM_LBUTTONUP          | press / release | client |
//! | WM_RBUTTONDOWN / WM_RBUTTONUP          | press / release | client |
//! | WM_MBUTTONDOWN / WM_MBUTTONUP          | press / release | client |
//! | WM_XBUTTONDOWN / WM_XBUTTONUP          | press / release | client |
//! | WM_MOUSEWHEEL / WM_MOUSEHWHEEL         | scroll  | screen      |
//! | WM_MOUSELEAVE                          | motion  | none        |
//!
//! ## wParam and lParam
//!
//! | Bits        | Meaning                                              |
//! |-------------|------------------------------------------------------|
//! | wParam 0-15 | `MK_*` button and modifier state (see `KeyState`)    |
//! | wParam 16-31 | XBUTTON id for WM_XBUTTON*, signed wheel delta for WM_*WHEEL |
//! | lParam 0-15 | Signed 16-bit x coordinate                            |
//! | lParam 16-31 | Signed 16-bit y coordinate                           |
//!
//! Pointer messages carry *client-area* coordinates in device pixels, which is
//! what `mouse_encode.Event.pos` expects. Wheel messages carry *screen*
//! coordinates instead; `translate` ignores them, because the core consumes only
//! the scroll deltas, and the apprt must call `ScreenToClient` itself if it needs
//! the wheel position.
//!
//! ## Wheel accumulation
//!
//! Windows reports wheel motion in units of `WHEEL_DELTA` (120) and
//! high-resolution wheels report fractions of that, so `WheelAccumulator` carries
//! the remainder between messages: a run of sub-delta events eventually produces
//! one scroll instead of being dropped. Positive deltas rotate the wheel away
//! from the user, which this file reports as scrolling up (positive
//! `ScrollEvent.y`), matching the convention of the GTK apprt, which passes
//! `scaled.y * -1` to `Surface.scrollCallback`. Horizontal deltas are negated so
//! that positive `ScrollEvent.x` means scrolling left, likewise matching GTK's
//! `scaled.x * -1`.
//!
//! ## Not implemented here
//!
//! No Win32 function is called; only message parameters are decoded. Windows
//! reports only Shift and Ctrl through `MK_*`, so Alt and Win are absent from
//! `KeyState.mods`; the apprt fills them from `GetKeyState` if it needs them.
//! `WM_MOUSELEAVE` is only delivered after the apprt registers with
//! `TrackMouseEvent(TME_LEAVE)`, which is a G3.4+ task.

const std = @import("std");
const key = @import("../../input/key.zig");
const core_mouse = @import("../../input/mouse.zig");
const mouse_encode = @import("../../input/mouse_encode.zig");

/// `WPARAM` from the Win32 ABI (`typedef UINT_PTR WPARAM`). `std.os.windows`
/// does not declare it, so it is spelled out here.
pub const WPARAM = usize;

/// `LPARAM` from the Win32 ABI (`typedef LONG_PTR LPARAM`).
pub const LPARAM = std.os.windows.LPARAM;

// ── Window messages (winuser.h) ─────────────────────────────────────────────

pub const WM_MOUSEMOVE: u32 = 0x0200;
pub const WM_LBUTTONDOWN: u32 = 0x0201;
pub const WM_LBUTTONUP: u32 = 0x0202;
pub const WM_RBUTTONDOWN: u32 = 0x0204;
pub const WM_RBUTTONUP: u32 = 0x0205;
pub const WM_MBUTTONDOWN: u32 = 0x0207;
pub const WM_MBUTTONUP: u32 = 0x0208;
pub const WM_MOUSEWHEEL: u32 = 0x020A;
pub const WM_XBUTTONDOWN: u32 = 0x020B;
pub const WM_XBUTTONUP: u32 = 0x020C;
pub const WM_MOUSEHWHEEL: u32 = 0x020E;
pub const WM_MOUSELEAVE: u32 = 0x02A3;

/// Wheel delta that represents one scroll tick.
pub const WHEEL_DELTA: i32 = 120;

/// XBUTTON ids in the high word of `wParam` for WM_XBUTTON*.
pub const XBUTTON1: u16 = 0x0001;
pub const XBUTTON2: u16 = 0x0002;

// ── Key-state flags in the low word of wParam (winuser.h) ───────────────────

pub const MK_LBUTTON: u16 = 0x0001;
pub const MK_RBUTTON: u16 = 0x0002;
pub const MK_SHIFT: u16 = 0x0004;
pub const MK_CONTROL: u16 = 0x0008;
pub const MK_MBUTTON: u16 = 0x0010;
pub const MK_XBUTTON1: u16 = 0x0020;
pub const MK_XBUTTON2: u16 = 0x0040;

/// Button and modifier state carried in the low word of `wParam`.
pub const KeyState = packed struct(u16) {
    left: bool = false,
    right: bool = false,
    shift: bool = false,
    control: bool = false,
    middle: bool = false,
    xbutton1: bool = false,
    xbutton2: bool = false,
    _padding: u9 = 0,

    /// Decode the low word of `wParam`.
    pub fn fromWord(wParam: WPARAM) KeyState {
        return @bitCast(@as(u16, @truncate(wParam)));
    }

    /// Modifiers held during this message. Windows reports only Shift and Ctrl
    /// here; Alt and Win come from `GetKeyState`.
    pub fn mods(self: KeyState) key.Mods {
        return .{ .shift = self.shift, .ctrl = self.control };
    }

    /// The pressed button that initiated a drag, for motion events. Ghostty
    /// reports motion with the button that is held, if any.
    pub fn pressedButton(self: KeyState) ?core_mouse.Button {
        if (self.left) return .left;
        if (self.right) return .right;
        if (self.middle) return .middle;
        if (self.xbutton1) return .four;
        if (self.xbutton2) return .five;
        return null;
    }
};

/// Mouse position from `lParam`. Both halves are signed 16-bit client-area
/// coordinates in device pixels.
pub fn posFromLParam(lParam: LPARAM) mouse_encode.Event.Pos {
    const bits: usize = @bitCast(lParam);
    const x: i16 = @bitCast(@as(u16, @truncate(bits)));
    const y: i16 = @bitCast(@as(u16, @truncate(bits >> 16)));
    return .{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
}

/// The XBUTTON id from the high word of `wParam` for WM_XBUTTON*.
pub fn xbutton(wParam: WPARAM) u16 {
    return @truncate(wParam >> 16);
}

/// Signed wheel delta from the high word of `wParam`
/// (`GET_WHEEL_DELTA_WPARAM`). Windows stores it as a signed 16-bit value.
pub fn wheelDelta(wParam: WPARAM) i32 {
    const high: i16 = @bitCast(@as(u16, @truncate(wParam >> 16)));
    return high;
}

/// The button a button message refers to, or null for motion and scroll.
pub fn buttonFromMessage(message: u32, wParam: WPARAM) ?core_mouse.Button {
    return switch (message) {
        WM_LBUTTONDOWN, WM_LBUTTONUP => .left,
        WM_RBUTTONDOWN, WM_RBUTTONUP => .right,
        WM_MBUTTONDOWN, WM_MBUTTONUP => .middle,
        WM_XBUTTONDOWN, WM_XBUTTONUP => switch (xbutton(wParam)) {
            XBUTTON1 => .four,
            XBUTTON2 => .five,
            else => null,
        },
        else => null,
    };
}

/// The mouse action for a message, or null when the message is not a pointer
/// message.
pub fn actionFromMessage(message: u32) ?core_mouse.Action {
    return switch (message) {
        WM_MOUSEMOVE, WM_MOUSELEAVE => .motion,
        WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN, WM_XBUTTONDOWN => .press,
        WM_LBUTTONUP, WM_RBUTTONUP, WM_MBUTTONUP, WM_XBUTTONUP => .release,
        else => null,
    };
}

/// The `MouseKeyState` matching a translated action, for
/// `Surface.mouseButtonCallback`. Motion has no button state.
pub fn buttonState(action: core_mouse.Action) ?core_mouse.ButtonState {
    return switch (action) {
        .press => .press,
        .release => .release,
        .motion => null,
    };
}

/// Build the pointer event for a mouse message, or null when the message is not
/// a pointer message.
pub fn eventFromMessage(message: u32, wParam: WPARAM, lParam: LPARAM) ?mouse_encode.Event {
    const action = actionFromMessage(message) orelse return null;

    // WM_MOUSELEAVE has no usable parameters. The GTK apprt signals "pointer
    // left the surface" by calling the cursor position callback with an invalid
    // position, so do the same.
    if (message == WM_MOUSELEAVE) {
        return .{ .action = .motion, .button = null, .pos = .{ .x = -1, .y = -1 } };
    }

    const state = KeyState.fromWord(wParam);
    return .{
        .action = action,
        .button = switch (action) {
            .motion => state.pressedButton(),
            else => buttonFromMessage(message, wParam),
        },
        .mods = state.mods(),
        .pos = posFromLParam(lParam),
    };
}

/// A wheel axis.
pub const Axis = enum { vertical, horizontal };

/// Carries the sub-tick remainder of the wheel deltas across messages.
///
/// Windows reports wheel motion in `WHEEL_DELTA` units, and high-resolution
/// wheels and touchpads report fractions of a unit. Dropping the remainder would
/// lose slow scrolling entirely, so it is accumulated until it completes a tick.
pub const WheelAccumulator = struct {
    vertical: i32 = 0,
    horizontal: i32 = 0,

    /// Feed one raw wheel delta and return the whole ticks it completed. The
    /// unconsumed remainder is kept for the next call. The sign of the result
    /// matches the sign of the delta.
    pub fn feed(self: *WheelAccumulator, axis: Axis, delta: i32) i32 {
        const remainder = switch (axis) {
            .vertical => &self.vertical,
            .horizontal => &self.horizontal,
        };

        const total = remainder.* + delta;
        const ticks = @divTrunc(total, WHEEL_DELTA);
        remainder.* = total - ticks * WHEEL_DELTA;
        return ticks;
    }

    /// Drop the remainder for one axis, for example when the wheel reverses
    /// direction or the window loses focus.
    pub fn reset(self: *WheelAccumulator, axis: Axis) void {
        switch (axis) {
            .vertical => self.vertical = 0,
            .horizontal => self.horizontal = 0,
        }
    }
};

/// A scroll event for `Surface.scrollCallback`. The offsets are in wheel ticks.
pub const ScrollEvent = struct {
    /// Horizontal ticks. Positive scrolls left.
    x: f64 = 0,
    /// Vertical ticks. Positive scrolls up.
    y: f64 = 0,
    /// Windows wheel messages are discrete and carry no momentum phase, so
    /// `precision` is always false here.
    mods: core_mouse.ScrollMods = .{},
};

/// A translated mouse message.
pub const Event = union(enum) {
    /// A button press/release or motion, for `Surface.mouseButtonCallback` and
    /// `Surface.cursorPosCallback`.
    pointer: mouse_encode.Event,
    /// Wheel motion, for `Surface.scrollCallback`.
    scroll: ScrollEvent,
};

/// Stateful decoder for Win32 mouse messages.
pub const Translator = struct {
    /// Wheel deltas that did not yet add up to a whole tick.
    wheel: WheelAccumulator = .{},

    /// Decode one mouse message. Returns null for messages that are not mouse
    /// messages and for wheel messages that did not complete a tick.
    pub fn translate(self: *Translator, message: u32, wParam: WPARAM, lParam: LPARAM) ?Event {
        switch (message) {
            WM_MOUSEWHEEL => return self.wheelEvent(.vertical, wParam),
            WM_MOUSEHWHEEL => return self.wheelEvent(.horizontal, wParam),
            else => {},
        }

        const event = eventFromMessage(message, wParam, lParam) orelse return null;
        return .{ .pointer = event };
    }

    fn wheelEvent(self: *Translator, axis: Axis, wParam: WPARAM) ?Event {
        const ticks = self.wheel.feed(axis, wheelDelta(wParam));
        if (ticks == 0) return null;

        const amount: f64 = @floatFromInt(ticks);
        return .{
            .scroll = .{
                // Windows positive deltas are wheel-forward and wheel-right; the
                // core's convention is up and left, so the horizontal axis flips.
                .x = if (axis == .horizontal) -amount else 0,
                .y = if (axis == .vertical) amount else 0,
            },
        };
    }
};

// ── Tests ───────────────────────────────────────────────────────────────────

test "pointer messages map to buttons, actions and positions" {
    const t = std.testing;

    // Left button down at (300, 40) with Shift held.
    const lparam: usize = @as(u16, @intCast(@as(i16, 300))) | (@as(usize, @intCast(@as(i16, 40))) << 16);
    const event = eventFromMessage(WM_LBUTTONDOWN, MK_LBUTTON | MK_SHIFT, @bitCast(lparam)).?;
    try t.expectEqual(core_mouse.Action.press, event.action);
    try t.expectEqual(core_mouse.Button.left, event.button.?);
    try t.expect(event.mods.shift);
    try t.expect(!event.mods.ctrl);
    try t.expectEqual(@as(f32, 300), event.pos.x);
    try t.expectEqual(@as(f32, 40), event.pos.y);
    try t.expectEqual(core_mouse.ButtonState.press, buttonState(event.action).?);

    // Negative coordinates survive the signed decode.
    const negative: usize = @bitCast(@as(isize, -25));
    try t.expectEqual(@as(f32, -25), posFromLParam(@bitCast(negative)).x);

    // Right button up.
    try t.expectEqual(core_mouse.Button.right, buttonFromMessage(WM_RBUTTONUP, 0).?);
    try t.expectEqual(core_mouse.ButtonState.release, buttonState(.release).?);

    // XBUTTON1 and XBUTTON2 are Ghostty buttons four and five.
    const x1: WPARAM = @as(WPARAM, XBUTTON1) << 16;
    try t.expectEqual(core_mouse.Button.four, buttonFromMessage(WM_XBUTTONDOWN, x1).?);
    const x2: WPARAM = @as(WPARAM, XBUTTON2) << 16;
    try t.expectEqual(core_mouse.Button.five, buttonFromMessage(WM_XBUTTONUP, x2).?);
    try t.expectEqual(null, buttonFromMessage(WM_XBUTTONDOWN, 0));
}

test "motion reports the held button and leave reports an invalid position" {
    const t = std.testing;

    const moving = eventFromMessage(WM_MOUSEMOVE, MK_RBUTTON, 0).?;
    try t.expectEqual(core_mouse.Action.motion, moving.action);
    try t.expectEqual(core_mouse.Button.right, moving.button.?);
    try t.expectEqual(null, buttonState(moving.action));

    // WM_MOUSELEAVE mirrors the GTK apprt: an invalid position and no button.
    const left = eventFromMessage(WM_MOUSELEAVE, 0, 0).?;
    try t.expectEqual(core_mouse.Action.motion, left.action);
    try t.expectEqual(null, left.button);
    try t.expectEqual(@as(f32, -1), left.pos.x);
    try t.expectEqual(@as(f32, -1), left.pos.y);

    // A message Ghostty does not handle produces nothing.
    try t.expectEqual(null, eventFromMessage(0x0203, 0, 0));
}

test "wheel deltas accumulate into whole ticks" {
    const t = std.testing;
    var accum: WheelAccumulator = .{};

    // One notch in each direction.
    try t.expectEqual(@as(i32, 1), accum.feed(.vertical, WHEEL_DELTA));
    try t.expectEqual(@as(i32, -1), accum.feed(.vertical, -WHEEL_DELTA));

    // A high-resolution wheel sends sub-tick deltas that accumulate.
    try t.expectEqual(@as(i32, 0), accum.feed(.vertical, 40));
    try t.expectEqual(@as(i32, 0), accum.feed(.vertical, 40));
    try t.expectEqual(@as(i32, 1), accum.feed(.vertical, 40));
    try t.expectEqual(@as(i32, 0), accum.vertical);

    // Remainders keep their sign, so slow reverse scrolling is symmetric.
    try t.expectEqual(@as(i32, 0), accum.feed(.vertical, 30));
    try t.expectEqual(@as(i32, 0), accum.feed(.vertical, -30));
    try t.expectEqual(@as(i32, 0), accum.feed(.horizontal, 100));
    accum.reset(.horizontal);
    try t.expectEqual(@as(i32, 0), accum.horizontal);
}

test "translator turns wheel messages into scroll events" {
    const t = std.testing;
    var translator: Translator = .{};

    // Wheel up: positive delta, one tick.
    const up: WPARAM = @as(WPARAM, @bitCast(@as(isize, WHEEL_DELTA))) << 16;
    const scroll_up = translator.translate(WM_MOUSEWHEEL, up, 0).?.scroll;
    try t.expectEqual(@as(f64, 1), scroll_up.y);
    try t.expectEqual(@as(f64, 0), scroll_up.x);
    try t.expect(!scroll_up.mods.precision);

    // Wheel down.
    const down: WPARAM = @as(WPARAM, @bitCast(@as(isize, -WHEEL_DELTA))) << 16;
    try t.expectEqual(@as(f64, -1), translator.translate(WM_MOUSEWHEEL, down, 0).?.scroll.y);

    // Sub-tick deltas produce no event until they complete a tick: two 60-unit
    // deltas add up to one 120-unit tick.
    const half: WPARAM = @as(WPARAM, 60) << 16;
    try t.expectEqual(null, translator.translate(WM_MOUSEWHEEL, half, 0));
    const completed = translator.translate(WM_MOUSEWHEEL, half, 0).?.scroll;
    try t.expectEqual(@as(f64, 1), completed.y);

    // Horizontal deltas are negated: wheel-right scrolls left.
    const right: WPARAM = @as(WPARAM, WHEEL_DELTA) << 16;
    const scroll_right = translator.translate(WM_MOUSEHWHEEL, right, 0).?.scroll;
    try t.expectEqual(@as(f64, -1), scroll_right.x);
    try t.expectEqual(@as(f64, 0), scroll_right.y);

    // Pointer messages flow through the same entry point.
    try t.expectEqual(core_mouse.Action.press, translator.translate(WM_LBUTTONDOWN, 0, 0).?.pointer.action);
    // WM_PAINT is not a mouse message.
    try t.expectEqual(null, translator.translate(0x000F, 0, 0));
}
