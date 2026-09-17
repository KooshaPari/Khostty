//! Win32 keyboard messages to Ghostty key events.
//!
//! ## Message model
//!
//! | Message                      | wParam        | Provides     |
//! |------------------------------|---------------|--------------|
//! | WM_KEYDOWN / WM_SYSKEYDOWN   | virtual key   | physical key |
//! | WM_CHAR / WM_SYSCHAR         | UTF-16 unit   | layout text  |
//! | WM_UNICHAR                   | UTF-32 scalar | layout text  |
//! | WM_DEADCHAR / WM_SYSDEADCHAR | UTF-16 unit   | dead key     |
//! | WM_KEYUP / WM_SYSKEYUP       | virtual key   | release      |
//!
//! `TranslateMessage` synthesizes the char message from the key message for keys
//! that produce text in the active layout. Ghostty needs both halves in one
//! `input.KeyEvent`: the physical key drives bindings and the Kitty/CSIu encoding,
//! while the text drives legacy encoding. A key event with a real key and empty
//! `utf8` encodes nothing for a character key (see `ctrlSeq` and
//! `pcStyleFunctionKey` in `src/input/key_encode.zig`), so the two messages must
//! be merged rather than forwarded separately. This file is the stateless half of
//! that merge: `keyEvent` builds an event from a key message, `Decoder.applyText`
//! completes it with the text of a char message, and `mayProduceText` reports
//! whether a char message is expected at all. Which press still awaits its text,
//! and the release that can resolve it, is state owned by the router in
//! `src/apprt/windows/input.zig`.
//!
//! ## lParam key data (bits, from `winuser.h`)
//!
//! | Bits  | Meaning                                                    |
//! |-------|------------------------------------------------------------|
//! | 0-15  | Repeat count for the current message                       |
//! | 16-23 | Scan code                                                  |
//! | 24    | Extended key (right Ctrl/Alt, numpad Divide, numpad Enter)  |
//! | 25-28 | Reserved                                                   |
//! | 29    | Context code: Alt was held (system keys only)               |
//! | 30    | Previous key state: 1 means the key was already down       |
//! | 31    | Transition state: 0 key-down, 1 key-up                     |
//!
//! ## Virtual key to Ghostty key
//!
//! Contiguous ranges map by offset: `VK_A`-`VK_Z` (0x41-0x5A) to `key_a`-`key_z`,
//! `VK_0`-`VK_9` (0x30-0x39) to `digit_0`-`digit_9`, `VK_NUMPAD0`-`VK_NUMPAD9`
//! (0x60-0x69) to `numpad_0`-`numpad_9`, and `VK_F1`-`VK_F24` (0x70-0x87) to
//! `f1`-`f24`. Every other key is in `keymap`, whose group comments name the
//! `winuser.h` keys they cover.
//!
//! ## Not implemented here
//!
//! No Win32 function is called; only message parameters are decoded.
//! `GetKeyState`/`GetAsyncKeyState` are the authoritative modifier source on
//! Windows, and `ToUnicodeEx` recovers an exact unshifted codepoint; `ModifierState`
//! mirrors modifier state from the message stream and is a public field of the
//! router so the apprt can overwrite it once G3.4 lands.

const std = @import("std");
const key = @import("../../input/key.zig");

const log = std.log.scoped(.win32_keyboard);

/// `WPARAM` from the Win32 ABI (`typedef UINT_PTR WPARAM`). `std.os.windows`
/// does not declare it, so it is spelled out here.
pub const WPARAM = usize;

/// `LPARAM` from the Win32 ABI (`typedef LONG_PTR LPARAM`).
pub const LPARAM = std.os.windows.LPARAM;

/// Longest UTF-8 sequence a scalar value produces; a surrogate pair spans two
/// messages but still yields one sequence.
pub const max_utf8_len = 4;

// ── Window messages (winuser.h) ─────────────────────────────────────────────

pub const WM_KEYDOWN: u32 = 0x0100;
pub const WM_KEYUP: u32 = 0x0101;
pub const WM_CHAR: u32 = 0x0102;
pub const WM_DEADCHAR: u32 = 0x0103;
pub const WM_SYSKEYDOWN: u32 = 0x0104;
pub const WM_SYSKEYUP: u32 = 0x0105;
pub const WM_SYSCHAR: u32 = 0x0106;
pub const WM_SYSDEADCHAR: u32 = 0x0107;
pub const WM_UNICHAR: u32 = 0x0109;

/// `WM_UNICHAR` with this value asks the window procedure to report whether it
/// handles Unicode input; there is no text to forward.
pub const UNICODE_NOCHAR: u32 = 0xFFFF;

// ── Virtual key codes (winuser.h) ───────────────────────────────────────────

pub const VK_BACK: u8 = 0x08;
pub const VK_TAB: u8 = 0x09;
pub const VK_CLEAR: u8 = 0x0C;
pub const VK_RETURN: u8 = 0x0D;
pub const VK_SHIFT: u8 = 0x10;
pub const VK_CONTROL: u8 = 0x11;
pub const VK_MENU: u8 = 0x12;
pub const VK_PAUSE: u8 = 0x13;
pub const VK_CAPITAL: u8 = 0x14;
pub const VK_KANA: u8 = 0x15;
pub const VK_HANJA: u8 = 0x19;
pub const VK_ESCAPE: u8 = 0x1B;
pub const VK_CONVERT: u8 = 0x1C;
pub const VK_NONCONVERT: u8 = 0x1D;
pub const VK_SPACE: u8 = 0x20;
pub const VK_PRIOR: u8 = 0x21;
pub const VK_NEXT: u8 = 0x22;
pub const VK_END: u8 = 0x23;
pub const VK_HOME: u8 = 0x24;
pub const VK_LEFT: u8 = 0x25;
pub const VK_UP: u8 = 0x26;
pub const VK_RIGHT: u8 = 0x27;
pub const VK_DOWN: u8 = 0x28;
pub const VK_SNAPSHOT: u8 = 0x2C;
pub const VK_INSERT: u8 = 0x2D;
pub const VK_DELETE: u8 = 0x2E;
pub const VK_HELP: u8 = 0x2F;
pub const VK_0: u8 = 0x30;
pub const VK_9: u8 = 0x39;
pub const VK_A: u8 = 0x41;
pub const VK_Z: u8 = 0x5A;
pub const VK_LWIN: u8 = 0x5B;
pub const VK_RWIN: u8 = 0x5C;
pub const VK_APPS: u8 = 0x5D;
pub const VK_SLEEP: u8 = 0x5F;
pub const VK_NUMPAD0: u8 = 0x60;
pub const VK_NUMPAD9: u8 = 0x69;
pub const VK_MULTIPLY: u8 = 0x6A;
pub const VK_ADD: u8 = 0x6B;
pub const VK_SEPARATOR: u8 = 0x6C;
pub const VK_SUBTRACT: u8 = 0x6D;
pub const VK_DECIMAL: u8 = 0x6E;
pub const VK_DIVIDE: u8 = 0x6F;
pub const VK_F1: u8 = 0x70;
pub const VK_F24: u8 = 0x87;
pub const VK_NUMLOCK: u8 = 0x90;
pub const VK_SCROLL: u8 = 0x91;
pub const VK_LSHIFT: u8 = 0xA0;
pub const VK_RSHIFT: u8 = 0xA1;
pub const VK_LCONTROL: u8 = 0xA2;
pub const VK_RCONTROL: u8 = 0xA3;
pub const VK_LMENU: u8 = 0xA4;
pub const VK_RMENU: u8 = 0xA5;
pub const VK_BROWSER_BACK: u8 = 0xA6;
pub const VK_BROWSER_FORWARD: u8 = 0xA7;
pub const VK_BROWSER_REFRESH: u8 = 0xA8;
pub const VK_BROWSER_STOP: u8 = 0xA9;
pub const VK_BROWSER_SEARCH: u8 = 0xAA;
pub const VK_BROWSER_FAVORITES: u8 = 0xAB;
pub const VK_BROWSER_HOME: u8 = 0xAC;
pub const VK_VOLUME_MUTE: u8 = 0xAD;
pub const VK_VOLUME_DOWN: u8 = 0xAE;
pub const VK_VOLUME_UP: u8 = 0xAF;
pub const VK_MEDIA_NEXT_TRACK: u8 = 0xB0;
pub const VK_MEDIA_PREV_TRACK: u8 = 0xB1;
pub const VK_MEDIA_STOP: u8 = 0xB2;
pub const VK_MEDIA_PLAY_PAUSE: u8 = 0xB3;
pub const VK_LAUNCH_MAIL: u8 = 0xB4;
pub const VK_LAUNCH_MEDIA_SELECT: u8 = 0xB5;
pub const VK_LAUNCH_APP1: u8 = 0xB6;
pub const VK_LAUNCH_APP2: u8 = 0xB7;
pub const VK_OEM_1: u8 = 0xBA;
pub const VK_OEM_PLUS: u8 = 0xBB;
pub const VK_OEM_COMMA: u8 = 0xBC;
pub const VK_OEM_MINUS: u8 = 0xBD;
pub const VK_OEM_PERIOD: u8 = 0xBE;
pub const VK_OEM_2: u8 = 0xBF;
pub const VK_OEM_3: u8 = 0xC0;
pub const VK_ABNT_C1: u8 = 0xC1;
pub const VK_ABNT_C2: u8 = 0xC2;
pub const VK_OEM_4: u8 = 0xDB;
pub const VK_OEM_5: u8 = 0xDC;
pub const VK_OEM_6: u8 = 0xDD;
pub const VK_OEM_7: u8 = 0xDE;
pub const VK_OEM_8: u8 = 0xDF;
pub const VK_OEM_102: u8 = 0xE2;

/// Key data decoded from the `lParam` of a key message. The fields mirror the
/// documented bit layout above.
pub const KeyInfo = struct {
    repeat_count: u16,
    scan_code: u8,
    /// Extended key: right Ctrl/Alt, numpad Enter, numpad Divide.
    extended: bool,
    /// Alt was held (system key messages only).
    alt_context: bool,
    /// The key was already down, i.e. auto-repeat.
    was_down: bool,
    /// Key-up transition.
    is_release: bool,

    /// Decode the `lParam` of a key message using the documented bit layout.
    pub fn fromLParam(value: LPARAM) KeyInfo {
        const bits: usize = @bitCast(value);
        return .{
            .repeat_count = @truncate(bits),
            .scan_code = @truncate(bits >> 16),
            .extended = bits & (@as(usize, 1) << 24) != 0,
            .alt_context = bits & (@as(usize, 1) << 29) != 0,
            .was_down = bits & (@as(usize, 1) << 30) != 0,
            .is_release = bits & (@as(usize, 1) << 31) != 0,
        };
    }

    /// Key action for this message.
    pub fn action(self: KeyInfo) key.Action {
        if (self.is_release) return .release;
        return if (self.was_down) .repeat else .press;
    }
};

/// Modifier state for a key message.
///
/// Windows reports the left and right variants of Shift, Ctrl and Alt as
/// separate keys: the virtual key is the same and only the scan code or the
/// extended flag differs. Tracking each side keeps a modifier latched while the
/// other side is still held.
pub const ModifierState = struct {
    shift_left: bool = false,
    shift_right: bool = false,
    ctrl_left: bool = false,
    ctrl_right: bool = false,
    alt_left: bool = false,
    alt_right: bool = false,
    win_left: bool = false,
    win_right: bool = false,
    /// Which physical side of each modifier was last seen. This persists across
    /// the key-up transition, because the side is a property of the key that was
    /// pressed rather than of whether it is currently held (see
    /// `input.Mods.Side`).
    sides: key.Mods.Side = .{},
    /// Toggle keys. Windows reports their state through `GetKeyState`, not
    /// through key messages, so this is a best-effort mirror that the apprt is
    /// expected to overwrite. Num Lock gates whether numpad keys produce text.
    caps_lock: bool = false,
    num_lock: bool = false,

    /// Convert to the core modifier set. Each modifier is set when either side is
    /// held, and `sides` reports the side that was last seen.
    pub fn mods(self: ModifierState) key.Mods {
        return .{
            .shift = self.shift_left or self.shift_right,
            .ctrl = self.ctrl_left or self.ctrl_right,
            .alt = self.alt_left or self.alt_right,
            .super = self.win_left or self.win_right,
            .caps_lock = self.caps_lock,
            .num_lock = self.num_lock,
            .sides = self.sides,
        };
    }

    /// Apply one key message. Returns true when the key is a Shift/Ctrl/Alt/Win
    /// modifier, which never produces a char message.
    pub fn applyKey(self: *ModifierState, vk: u8, info: KeyInfo) bool {
        const down = !info.is_release;
        switch (vk) {
            VK_SHIFT, VK_LSHIFT, VK_RSHIFT => {
                // Only the scan code distinguishes the two Shift keys.
                const right = vk == VK_RSHIFT or info.scan_code == SCAN_SHIFT_RIGHT;
                self.sides.shift = if (right) .right else .left;
                if (right) self.shift_right = down else self.shift_left = down;
                return true;
            },
            VK_CONTROL, VK_LCONTROL, VK_RCONTROL => {
                const right = vk == VK_RCONTROL or info.extended;
                self.sides.ctrl = if (right) .right else .left;
                if (right) self.ctrl_right = down else self.ctrl_left = down;
                return true;
            },
            VK_MENU, VK_LMENU, VK_RMENU => {
                const right = vk == VK_RMENU or info.extended;
                self.sides.alt = if (right) .right else .left;
                if (right) self.alt_right = down else self.alt_left = down;
                return true;
            },
            VK_LWIN => {
                self.sides.super = .left;
                self.win_left = down;
                return true;
            },
            VK_RWIN => {
                self.sides.super = .right;
                self.win_right = down;
                return true;
            },
            VK_CAPITAL => {
                if (info.is_release) self.caps_lock = !self.caps_lock;
                return false;
            },
            VK_NUMLOCK => {
                if (info.is_release) self.num_lock = !self.num_lock;
                return false;
            },
            else => return false,
        }
    }
};

/// Scan code of the right-hand Shift key: Windows sends both Shift keys as
/// `VK_SHIFT`, so only the scan code tells them apart. Ctrl and Alt use the
/// extended flag in `lParam` (bit 24) instead.
const SCAN_SHIFT_RIGHT: u8 = 0x36;

/// Windows virtual key to Ghostty key for every key outside a contiguous range.
/// Entry order and one-per-line layout follow `src/apprt/gtk/key.zig`.
const keymap: []const RawEntry = &.{
    // Writing-system keys.
    .{ VK_OEM_3, .backquote },
    .{ VK_OEM_5, .backslash },
    .{ VK_OEM_4, .bracket_left },
    .{ VK_OEM_6, .bracket_right },
    .{ VK_OEM_COMMA, .comma },
    .{ VK_OEM_PLUS, .equal },
    .{ VK_ABNT_C1, .intl_backslash },
    .{ VK_OEM_102, .intl_backslash },
    .{ VK_OEM_MINUS, .minus },
    .{ VK_OEM_PERIOD, .period },
    .{ VK_OEM_7, .quote },
    .{ VK_OEM_1, .semicolon },
    .{ VK_OEM_2, .slash },
    .{ VK_SPACE, .space },

    // Modifier keys, including the left/right virtual keys that only
    // `GetKeyState` callers normally see.
    .{ VK_SHIFT, .shift_left },
    .{ VK_LSHIFT, .shift_left },
    .{ VK_RSHIFT, .shift_right },
    .{ VK_CONTROL, .control_left },
    .{ VK_LCONTROL, .control_left },
    .{ VK_RCONTROL, .control_right },
    .{ VK_MENU, .alt_left },
    .{ VK_LMENU, .alt_left },
    .{ VK_RMENU, .alt_right },
    .{ VK_LWIN, .meta_left },
    .{ VK_RWIN, .meta_right },
    .{ VK_CAPITAL, .caps_lock },
    .{ VK_NUMLOCK, .num_lock },
    .{ VK_SCROLL, .scroll_lock },

    // Control and editing keys.
    .{ VK_BACK, .backspace },
    .{ VK_TAB, .tab },
    .{ VK_RETURN, .enter },
    .{ VK_ESCAPE, .escape },
    .{ VK_CLEAR, .numpad_clear },
    .{ VK_INSERT, .insert },
    .{ VK_DELETE, .delete },
    .{ VK_HOME, .home },
    .{ VK_END, .end },
    .{ VK_PRIOR, .page_up },
    .{ VK_NEXT, .page_down },
    .{ VK_LEFT, .arrow_left },
    .{ VK_RIGHT, .arrow_right },
    .{ VK_UP, .arrow_up },
    .{ VK_DOWN, .arrow_down },
    .{ VK_HELP, .help },
    .{ VK_SNAPSHOT, .print_screen },
    .{ VK_PAUSE, .pause },
    .{ VK_APPS, .context_menu },

    // Input-method and layout keys.
    .{ VK_KANA, .kana_mode },
    .{ VK_HANJA, .convert },
    .{ VK_CONVERT, .convert },
    .{ VK_NONCONVERT, .non_convert },

    // Numpad operators. The numpad digits are contiguous and map by offset.
    .{ VK_MULTIPLY, .numpad_multiply },
    .{ VK_ADD, .numpad_add },
    .{ VK_SEPARATOR, .numpad_separator },
    .{ VK_SUBTRACT, .numpad_subtract },
    .{ VK_DECIMAL, .numpad_decimal },
    .{ VK_DIVIDE, .numpad_divide },
    .{ VK_ABNT_C2, .numpad_separator },

    // Browser, media, volume and power keys.
    .{ VK_BROWSER_BACK, .browser_back },
    .{ VK_BROWSER_FORWARD, .browser_forward },
    .{ VK_BROWSER_REFRESH, .browser_refresh },
    .{ VK_BROWSER_STOP, .browser_stop },
    .{ VK_BROWSER_SEARCH, .browser_search },
    .{ VK_BROWSER_FAVORITES, .browser_favorites },
    .{ VK_BROWSER_HOME, .browser_home },
    .{ VK_VOLUME_MUTE, .audio_volume_mute },
    .{ VK_VOLUME_DOWN, .audio_volume_down },
    .{ VK_VOLUME_UP, .audio_volume_up },
    .{ VK_MEDIA_NEXT_TRACK, .media_track_next },
    .{ VK_MEDIA_PREV_TRACK, .media_track_previous },
    .{ VK_MEDIA_STOP, .media_stop },
    .{ VK_MEDIA_PLAY_PAUSE, .media_play_pause },
    .{ VK_LAUNCH_MAIL, .launch_mail },
    .{ VK_LAUNCH_MEDIA_SELECT, .media_select },
    .{ VK_LAUNCH_APP1, .launch_app_1 },
    .{ VK_LAUNCH_APP2, .launch_app_2 },
    .{ VK_SLEEP, .sleep },
};

/// One row of `keymap`.
const RawEntry = struct { u8, key.Key };

/// Ghostty key for a Windows virtual key, or null when Ghostty has no
/// equivalent (callers then use `.unidentified`).
pub fn keyFromVirtualKey(vk: u8) ?key.Key {
    // Letters, digits, numpad digits and function keys are contiguous in the
    // virtual key space and in the Ghostty key space, so they map by offset.
    if (vk >= VK_A and vk <= VK_Z) return @enumFromInt(@intFromEnum(key.Key.key_a) + (vk - VK_A));
    if (vk >= VK_0 and vk <= VK_9) return @enumFromInt(@intFromEnum(key.Key.digit_0) + (vk - VK_0));
    if (vk >= VK_NUMPAD0 and vk <= VK_NUMPAD9) return @enumFromInt(@intFromEnum(key.Key.numpad_0) + (vk - VK_NUMPAD0));
    if (vk >= VK_F1 and vk <= VK_F24) return @enumFromInt(@intFromEnum(key.Key.f1) + (vk - VK_F1));

    for (keymap) |entry| {
        if (entry[0] == vk) return entry[1];
    }

    return null;
}

/// Build the key event for a key message. `state` must already include this
/// key's own modifier transition so that a modifier press reports itself.
pub fn keyEvent(vk: u8, info: KeyInfo, state: ModifierState) key.KeyEvent {
    return .{
        .action = info.action(),
        .key = keyFromVirtualKey(vk) orelse .unidentified,
        .mods = state.mods(),
    };
}

/// Whether `TranslateMessage` is expected to synthesize a char message for this
/// virtual key. Keys that never produce text are emitted immediately so they are
/// not delayed behind a char message that will never arrive.
pub fn mayProduceText(vk: u8, state: ModifierState) bool {
    return switch (vk) {
        // Numpad keys produce text only while Num Lock is on; otherwise they
        // generate the navigation codes.
        VK_NUMPAD0...VK_NUMPAD9,
        VK_MULTIPLY,
        VK_ADD,
        VK_SEPARATOR,
        VK_SUBTRACT,
        VK_DECIMAL,
        VK_DIVIDE,
        => state.num_lock,

        // Keys whose text arrives as a control character.
        VK_ESCAPE, VK_RETURN, VK_BACK, VK_TAB, VK_SPACE => true,

        // Keys that produce the layout's text. VK_OEM_1 through VK_OEM_8 covers
        // the punctuation keys and the ABNT variants between them.
        VK_0...VK_9, VK_A...VK_Z, VK_OEM_1...VK_OEM_8, VK_OEM_102 => true,

        else => false,
    };
}

/// Control characters are encoded by the core from the key and modifiers rather
/// than from text (`ctrlSeq` in `src/input/key_encode.zig`).
pub fn isControlChar(cp: u21) bool {
    return cp < 0x20 or cp == 0x7F;
}

/// The key a C0 control character stands for, used when no key message preceded
/// the char message.
fn keyFromControlChar(cp: u21) key.Key {
    return switch (cp) {
        0x08, 0x7F => .backspace,
        0x09 => .tab,
        0x0A, 0x0D => .enter,
        0x1B => .escape,
        else => .unidentified,
    };
}

/// Base key for a C0 control character: Ctrl+A is 0x01, Ctrl+B is 0x02 and so on
/// (ECMA-48 / xterm). This is the alternate key the Kitty keyboard protocol
/// reports.
fn unshiftedFromControlChar(cp: u21) u21 {
    if (cp >= 0x01 and cp <= 0x1A) return cp + 0x60;
    return 0;
}

/// Best-effort unshifted codepoint for `cp`. Windows recovers this exactly with
/// `ToUnicodeEx` against the active layout, which this scaffold does not call;
/// ASCII shift pairs are inverted from the US layout and everything else falls
/// back to `cp`.
pub fn unshiftedCodepoint(cp: u21, shifted: bool) u21 {
    // Shift and Caps Lock both uppercase an ASCII letter.
    if (cp >= 'A' and cp <= 'Z') return cp + 0x20;
    if (!shifted) return cp;

    return switch (cp) {
        '!' => '1',
        '@' => '2',
        '#' => '3',
        '$' => '4',
        '%' => '5',
        '^' => '6',
        '&' => '7',
        '*' => '8',
        '(' => '9',
        ')' => '0',
        '_' => '-',
        '+' => '=',
        '{' => '[',
        '}' => ']',
        '|' => '\\',
        ':' => ';',
        '"' => '\'',
        '<' => ',',
        '>' => '.',
        '?' => '/',
        '~' => '`',
        else => cp,
    };
}

/// Decodes the text side of the keyboard message stream.
pub const Decoder = struct {
    /// High half of a UTF-16 surrogate pair, awaiting its low half.
    high_surrogate: ?u16 = null,

    /// Backing storage for `KeyEvent.utf8`. Only one event with text is produced
    /// per message, so one buffer is enough.
    utf8_buf: [max_utf8_len]u8 = [_]u8{0} ** max_utf8_len,

    /// Forget any half-received surrogate pair.
    pub fn reset(self: *Decoder) void {
        self.high_surrogate = null;
    }

    /// Decode one UTF-16 code unit from a char message. Returns null while a high
    /// surrogate awaits its low half, and for a lone low surrogate.
    pub fn decode(self: *Decoder, unit: u16) ?u21 {
        if (std.unicode.utf16IsHighSurrogate(unit)) {
            self.high_surrogate = unit;
            return null;
        }

        if (std.unicode.utf16IsLowSurrogate(unit)) {
            const high = self.high_surrogate orelse return null;
            self.high_surrogate = null;
            return std.unicode.utf16DecodeSurrogatePair(&[_]u16{ high, unit }) catch null;
        }

        self.high_surrogate = null;
        return @intCast(unit);
    }

    /// Decode a `WM_UNICHAR` scalar. Returns null for `UNICODE_NOCHAR` and for
    /// values that are not valid Unicode scalar values.
    pub fn decodeUnichar(self: *Decoder, value: u32) ?u21 {
        _ = self;
        if (value == UNICODE_NOCHAR) return null;
        const cp = std.math.cast(u21, value) orelse return null;
        if (!std.unicode.utf8ValidCodepoint(cp)) {
            log.warn("ignoring invalid WM_UNICHAR codepoint=0x{x}", .{value});
            return null;
        }
        return cp;
    }

    /// Complete `event` with the text decoded from a char message.
    ///
    /// Control characters intentionally leave `utf8` empty: the core encodes them
    /// from the key and modifiers, so forwarding the control character as text
    /// would encode the same key twice.
    pub fn applyText(self: *Decoder, event: *key.KeyEvent, cp: u21) void {
        if (isControlChar(cp)) {
            if (event.key == .unidentified) event.key = keyFromControlChar(cp);
            event.unshifted_codepoint = unshiftedFromControlChar(cp);
            return;
        }

        const shifted = event.mods.shift;
        const unshifted = unshiftedCodepoint(cp, shifted);
        const len = std.unicode.utf8Encode(cp, &self.utf8_buf) catch 0;
        event.utf8 = self.utf8_buf[0..len];
        event.unshifted_codepoint = unshifted;
        event.consumed_mods = .{ .shift = shifted and unshifted != cp };
    }

    /// Complete `event` with the preedit text of a dead key. The event is marked
    /// composing so the core leaves encoding to the input method.
    pub fn applyDeadChar(self: *Decoder, event: *key.KeyEvent, cp: u21) void {
        const len = std.unicode.utf8Encode(cp, &self.utf8_buf) catch 0;
        event.utf8 = self.utf8_buf[0..len];
        event.composing = true;
    }
};

// ── Tests ───────────────────────────────────────────────────────────────────

test "keyFromVirtualKey covers the ranges and the table" {
    const t = std.testing;
    try t.expectEqual(key.Key.key_a, keyFromVirtualKey(VK_A).?);
    try t.expectEqual(key.Key.key_z, keyFromVirtualKey(VK_Z).?);
    try t.expectEqual(key.Key.digit_0, keyFromVirtualKey(VK_0).?);
    try t.expectEqual(key.Key.numpad_9, keyFromVirtualKey(VK_NUMPAD9).?);
    try t.expectEqual(key.Key.f24, keyFromVirtualKey(VK_F24).?);
    try t.expectEqual(key.Key.semicolon, keyFromVirtualKey(VK_OEM_1).?);
    try t.expectEqual(key.Key.arrow_up, keyFromVirtualKey(VK_UP).?);
    try t.expectEqual(key.Key.meta_right, keyFromVirtualKey(VK_RWIN).?);
    try t.expectEqual(key.Key.media_play_pause, keyFromVirtualKey(VK_MEDIA_PLAY_PAUSE).?);
    // VK_SELECT (0x29) has no Ghostty equivalent.
    try t.expectEqual(null, keyFromVirtualKey(0x29));
}

test "KeyInfo decodes the documented lParam layout" {
    const t = std.testing;
    // Repeat count 0x21, scan code 0x3A, extended (bit 24), key-down.
    const info = KeyInfo.fromLParam(@bitCast(@as(usize, 0x013A0021)));
    try t.expectEqual(@as(u16, 0x21), info.repeat_count);
    try t.expectEqual(@as(u8, 0x3A), info.scan_code);
    try t.expect(info.extended);
    try t.expect(!info.alt_context);
    try t.expectEqual(key.Action.press, info.action());

    // Transition bit: release after auto-repeat.
    try t.expectEqual(key.Action.release, KeyInfo.fromLParam(@bitCast(@as(usize, 0xC0000000))).action());
    // Previous-state bit alone: auto-repeat.
    try t.expectEqual(key.Action.repeat, KeyInfo.fromLParam(@bitCast(@as(usize, 0x40000000))).action());
}

test "applyText completes a key event with the layout text" {
    const t = std.testing;
    var decoder: Decoder = .{};
    const down = KeyInfo.fromLParam(@bitCast(@as(usize, 0x001E0001)));

    // Shift+A: WM_CHAR delivers "A".
    var uppercase = keyEvent(VK_A, down, .{ .shift_left = true });
    decoder.applyText(&uppercase, 'A');
    try t.expectEqual(key.Key.key_a, uppercase.key);
    try t.expectEqual(key.Action.press, uppercase.action);
    try t.expect(uppercase.mods.shift);
    try t.expectEqualStrings("A", uppercase.utf8);
    try t.expectEqual(@as(u21, 'a'), uppercase.unshifted_codepoint);
    try t.expect(uppercase.consumed_mods.shift);

    // Ctrl+C arrives as the C0 byte 0x03 and must not be forwarded as text.
    var control = keyEvent(VK_A + 2, down, .{ .ctrl_left = true }); // VK_C
    decoder.applyText(&control, 0x03);
    try t.expectEqual(key.Key.key_c, control.key);
    try t.expectEqualStrings("", control.utf8);
    try t.expectEqual(@as(u21, 'c'), control.unshifted_codepoint);
    try t.expect(control.mods.ctrl);

    // With no key message first the control character still names the key.
    var enter: key.KeyEvent = .{};
    decoder.applyText(&enter, 0x0D);
    try t.expectEqual(key.Key.enter, enter.key);
    try t.expectEqualStrings("", enter.utf8);
}

test "modifier sides, predicate and US shift pairs" {
    const t = std.testing;
    var state: ModifierState = .{};
    // Right Shift is the generic virtual key plus the right-hand scan code.
    const right_shift = KeyInfo.fromLParam(@bitCast(@as(usize, 0x00360001)));
    try t.expect(state.applyKey(VK_SHIFT, right_shift));
    try t.expect(state.mods().shift);
    try t.expect(state.mods().sides.shift == .right);

    // The key-up transition (bit 31) clears the state but keeps reporting the side.
    _ = state.applyKey(VK_SHIFT, KeyInfo.fromLParam(@bitCast(@as(usize, 0x80360001))));
    try t.expect(!state.mods().shift);
    try t.expect(state.mods().sides.shift == .right);

    // Right Ctrl is the generic virtual key plus the extended flag.
    try t.expect(state.applyKey(VK_CONTROL, KeyInfo.fromLParam(@bitCast(@as(usize, 0x011D0001)))));
    try t.expect(state.mods().sides.ctrl == .right);
    try t.expect(!state.applyKey(VK_BACK, right_shift));

    try t.expect(mayProduceText(VK_ESCAPE, .{}));
    try t.expect(!mayProduceText(VK_F1 + 4, .{})); // VK_F5
    try t.expect(!mayProduceText(VK_LEFT, .{}));
    try t.expect(!mayProduceText(VK_NUMPAD0 + 1, .{})); // VK_NUMPAD1
    try t.expect(mayProduceText(VK_NUMPAD0 + 1, .{ .num_lock = true }));

    try t.expectEqual(@as(u21, 'a'), unshiftedCodepoint('A', true));
    try t.expectEqual(@as(u21, '1'), unshiftedCodepoint('!', true));
    try t.expectEqual(@as(u21, '/'), unshiftedCodepoint('?', true));
    try t.expectEqual(@as(u21, 0x00E9), unshiftedCodepoint(0x00E9, false));
}

test "decoder pairs surrogates and marks dead keys composing" {
    const t = std.testing;
    var decoder: Decoder = .{};

    // U+1F600 arrives as a UTF-16 surrogate pair: two char messages.
    try t.expectEqual(null, decoder.decode(0xD83D));
    try t.expectEqual(@as(?u21, 0x1F600), decoder.decode(0xDE00));
    // A lone low surrogate is dropped.
    try t.expectEqual(null, decoder.decode(0xDE00));

    var event: key.KeyEvent = .{};
    decoder.applyDeadChar(&event, 0x00B4);
    try t.expect(event.composing);
    try t.expectEqualStrings("\u{00B4}", event.utf8);

    // UNICODE_NOCHAR is a query, not text.
    try t.expectEqual(null, decoder.decodeUnichar(UNICODE_NOCHAR));
    try t.expectEqual(null, decoder.decodeUnichar(0x110000));
    try t.expectEqual(@as(?u21, 0x00E9), decoder.decodeUnichar(0x00E9));
}
