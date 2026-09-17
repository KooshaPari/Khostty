//! Raw `extern "C"` bindings for `libghostty-vt`.
//!
//! **Generated file.** Regenerate with `python3 tools/gen_ffi.py` from the
//! Khostty checkout (`include/ghostty/vt.h` plus `include/ghostty/vt/**`).
//! Do not edit by hand: `tests/ffi_coverage.rs` fails if this file drifts from
//! the C headers.
//!
//! Every declaration below is transcribed from the C headers by
//! `tools/gen_ffi.py`; the generator reports anything it could not represent in
//! the `SKIPPED` section at the bottom rather than dropping it silently.
//!
//! # Safety
//!
//! These are the *raw* bindings. Calling them directly requires upholding the
//! invariants documented in the corresponding C header: live handles must not
//! be double-freed, borrowed pointers (`GhosttyString`, row/cell `RAW` values,
//! search match buffers) are only valid until the next mutating call on the
//! object that produced them, and callbacks must not unwind across the FFI
//! boundary. Prefer the safe wrappers in [`crate::terminal`], [`crate::snapshot`],
//! [`crate::render`], [`crate::search`], [`crate::key`] and [`crate::mouse`].
//!
//! C enums are `int`-backed in this ABI (see the `GHOSTTY_ENUM_TYPED` comment
//! in `types.h`), so each C enum is a `c_int` type alias with `pub const`
//! values. That avoids relying on Rust enum layout and keeps unknown values
//! representable when a newer library returns a code this binding predates.

#![allow(
    non_camel_case_types,
    non_snake_case,
    non_upper_case_globals,
    dead_code,
    clippy::missing_safety_doc,
    clippy::too_many_arguments
)]


use core::ffi::{c_char, c_int, c_void};

// ---------------------------------------------------------------------
// Coverage: 198 functions, 179 types, 794 constants
// declared across 34 headers (201 `GHOSTTY_API` declarations detected).
// ---------------------------------------------------------------------

/// Number of `GHOSTTY_API` functions declared by this binding.
pub const BINDING_FUNCTION_COUNT: usize = 198;

// ---- Constants ---------------------------------------------------------

pub const GHOSTTY_BUILD_INFO_INVALID: GhosttyBuildInfo = 0;
pub const GHOSTTY_BUILD_INFO_KITTY_GRAPHICS: GhosttyBuildInfo = 2;
pub const GHOSTTY_BUILD_INFO_MAX_VALUE: GhosttyBuildInfo = c_int::MAX;
pub const GHOSTTY_BUILD_INFO_OPTIMIZE: GhosttyBuildInfo = 4;
pub const GHOSTTY_BUILD_INFO_SIMD: GhosttyBuildInfo = 1;
pub const GHOSTTY_BUILD_INFO_TMUX_CONTROL_MODE: GhosttyBuildInfo = 3;
pub const GHOSTTY_BUILD_INFO_VERSION_BUILD: GhosttyBuildInfo = 10;
pub const GHOSTTY_BUILD_INFO_VERSION_MAJOR: GhosttyBuildInfo = 6;
pub const GHOSTTY_BUILD_INFO_VERSION_MINOR: GhosttyBuildInfo = 7;
pub const GHOSTTY_BUILD_INFO_VERSION_PATCH: GhosttyBuildInfo = 8;
pub const GHOSTTY_BUILD_INFO_VERSION_PRE: GhosttyBuildInfo = 9;
pub const GHOSTTY_BUILD_INFO_VERSION_STRING: GhosttyBuildInfo = 5;
pub const GHOSTTY_CELL_CONTENT_BG_COLOR_PALETTE: GhosttyCellContentTag = 2;
pub const GHOSTTY_CELL_CONTENT_BG_COLOR_RGB: GhosttyCellContentTag = 3;
pub const GHOSTTY_CELL_CONTENT_CODEPOINT: GhosttyCellContentTag = 0;
pub const GHOSTTY_CELL_CONTENT_CODEPOINT_GRAPHEME: GhosttyCellContentTag = 1;
pub const GHOSTTY_CELL_CONTENT_TAG_MAX_VALUE: GhosttyCellContentTag = c_int::MAX;
pub const GHOSTTY_CELL_DATA_CODEPOINT: GhosttyCellData = 1;
pub const GHOSTTY_CELL_DATA_COLOR_PALETTE: GhosttyCellData = 10;
pub const GHOSTTY_CELL_DATA_COLOR_RGB: GhosttyCellData = 11;
pub const GHOSTTY_CELL_DATA_CONTENT_TAG: GhosttyCellData = 2;
pub const GHOSTTY_CELL_DATA_HAS_HYPERLINK: GhosttyCellData = 7;
pub const GHOSTTY_CELL_DATA_HAS_STYLING: GhosttyCellData = 5;
pub const GHOSTTY_CELL_DATA_HAS_TEXT: GhosttyCellData = 4;
pub const GHOSTTY_CELL_DATA_INVALID: GhosttyCellData = 0;
pub const GHOSTTY_CELL_DATA_MAX_VALUE: GhosttyCellData = c_int::MAX;
pub const GHOSTTY_CELL_DATA_PROTECTED: GhosttyCellData = 8;
pub const GHOSTTY_CELL_DATA_SEMANTIC_CONTENT: GhosttyCellData = 9;
pub const GHOSTTY_CELL_DATA_STYLE_ID: GhosttyCellData = 6;
pub const GHOSTTY_CELL_DATA_WIDE: GhosttyCellData = 3;
pub const GHOSTTY_CELL_SEMANTIC_INPUT: GhosttyCellSemanticContent = 1;
pub const GHOSTTY_CELL_SEMANTIC_MAX_VALUE: GhosttyCellSemanticContent = c_int::MAX;
pub const GHOSTTY_CELL_SEMANTIC_OUTPUT: GhosttyCellSemanticContent = 0;
pub const GHOSTTY_CELL_SEMANTIC_PROMPT: GhosttyCellSemanticContent = 2;
pub const GHOSTTY_CELL_WIDE_MAX_VALUE: GhosttyCellWide = c_int::MAX;
pub const GHOSTTY_CELL_WIDE_NARROW: GhosttyCellWide = 0;
pub const GHOSTTY_CELL_WIDE_SPACER_HEAD: GhosttyCellWide = 3;
pub const GHOSTTY_CELL_WIDE_SPACER_TAIL: GhosttyCellWide = 2;
pub const GHOSTTY_CELL_WIDE_WIDE: GhosttyCellWide = 1;
pub const GHOSTTY_CLIPBOARD_LOCATION_MAX_VALUE: GhosttyClipboardLocation = c_int::MAX;
pub const GHOSTTY_CLIPBOARD_LOCATION_PRIMARY: GhosttyClipboardLocation = 2;
pub const GHOSTTY_CLIPBOARD_LOCATION_SELECTION: GhosttyClipboardLocation = 1;
pub const GHOSTTY_CLIPBOARD_LOCATION_STANDARD: GhosttyClipboardLocation = 0;
pub const GHOSTTY_CLIPBOARD_READ_RESULT_BUSY: GhosttyClipboardReadResult = 3;
pub const GHOSTTY_CLIPBOARD_READ_RESULT_DENIED: GhosttyClipboardReadResult = 1;
pub const GHOSTTY_CLIPBOARD_READ_RESULT_IO_ERROR: GhosttyClipboardReadResult = 4;
pub const GHOSTTY_CLIPBOARD_READ_RESULT_MAX_VALUE: GhosttyClipboardReadResult = c_int::MAX;
pub const GHOSTTY_CLIPBOARD_READ_RESULT_SUCCESS: GhosttyClipboardReadResult = 0;
pub const GHOSTTY_CLIPBOARD_READ_RESULT_UNSUPPORTED: GhosttyClipboardReadResult = 2;
pub const GHOSTTY_CLIPBOARD_WRITE_RESULT_BUSY: GhosttyClipboardWriteResult = 3;
pub const GHOSTTY_CLIPBOARD_WRITE_RESULT_DENIED: GhosttyClipboardWriteResult = 1;
pub const GHOSTTY_CLIPBOARD_WRITE_RESULT_INVALID_DATA: GhosttyClipboardWriteResult = 4;
pub const GHOSTTY_CLIPBOARD_WRITE_RESULT_IO_ERROR: GhosttyClipboardWriteResult = 5;
pub const GHOSTTY_CLIPBOARD_WRITE_RESULT_MAX_VALUE: GhosttyClipboardWriteResult = c_int::MAX;
pub const GHOSTTY_CLIPBOARD_WRITE_RESULT_SUCCESS: GhosttyClipboardWriteResult = 0;
pub const GHOSTTY_CLIPBOARD_WRITE_RESULT_UNSUPPORTED: GhosttyClipboardWriteResult = 2;
pub const GHOSTTY_COLOR_NAMED_BLACK: c_int = 0;
pub const GHOSTTY_COLOR_NAMED_BLUE: c_int = 4;
pub const GHOSTTY_COLOR_NAMED_BRIGHT_BLACK: c_int = 8;
pub const GHOSTTY_COLOR_NAMED_BRIGHT_BLUE: c_int = 12;
pub const GHOSTTY_COLOR_NAMED_BRIGHT_CYAN: c_int = 14;
pub const GHOSTTY_COLOR_NAMED_BRIGHT_GREEN: c_int = 10;
pub const GHOSTTY_COLOR_NAMED_BRIGHT_MAGENTA: c_int = 13;
pub const GHOSTTY_COLOR_NAMED_BRIGHT_RED: c_int = 9;
pub const GHOSTTY_COLOR_NAMED_BRIGHT_WHITE: c_int = 15;
pub const GHOSTTY_COLOR_NAMED_BRIGHT_YELLOW: c_int = 11;
pub const GHOSTTY_COLOR_NAMED_CYAN: c_int = 6;
pub const GHOSTTY_COLOR_NAMED_GREEN: c_int = 2;
pub const GHOSTTY_COLOR_NAMED_MAGENTA: c_int = 5;
pub const GHOSTTY_COLOR_NAMED_RED: c_int = 1;
pub const GHOSTTY_COLOR_NAMED_WHITE: c_int = 7;
pub const GHOSTTY_COLOR_NAMED_YELLOW: c_int = 3;
pub const GHOSTTY_COLOR_SCHEME_DARK: GhosttyColorScheme = 1;
pub const GHOSTTY_COLOR_SCHEME_LIGHT: GhosttyColorScheme = 0;
pub const GHOSTTY_COLOR_SCHEME_MAX_VALUE: GhosttyColorScheme = c_int::MAX;
pub const GHOSTTY_DA_CONFORMANCE_LEVEL_2: c_int = 62;
pub const GHOSTTY_DA_CONFORMANCE_LEVEL_3: c_int = 63;
pub const GHOSTTY_DA_CONFORMANCE_LEVEL_4: c_int = 64;
pub const GHOSTTY_DA_CONFORMANCE_LEVEL_5: c_int = 65;
pub const GHOSTTY_DA_CONFORMANCE_VT100: c_int = 1;
pub const GHOSTTY_DA_CONFORMANCE_VT101: c_int = 1;
pub const GHOSTTY_DA_CONFORMANCE_VT102: c_int = 6;
pub const GHOSTTY_DA_CONFORMANCE_VT125: c_int = 12;
pub const GHOSTTY_DA_CONFORMANCE_VT131: c_int = 7;
pub const GHOSTTY_DA_CONFORMANCE_VT132: c_int = 4;
pub const GHOSTTY_DA_CONFORMANCE_VT220: c_int = 62;
pub const GHOSTTY_DA_CONFORMANCE_VT240: c_int = 62;
pub const GHOSTTY_DA_CONFORMANCE_VT320: c_int = 63;
pub const GHOSTTY_DA_CONFORMANCE_VT340: c_int = 63;
pub const GHOSTTY_DA_CONFORMANCE_VT420: c_int = 64;
pub const GHOSTTY_DA_CONFORMANCE_VT510: c_int = 65;
pub const GHOSTTY_DA_CONFORMANCE_VT520: c_int = 65;
pub const GHOSTTY_DA_CONFORMANCE_VT525: c_int = 65;
pub const GHOSTTY_DA_DEVICE_TYPE_VT100: c_int = 0;
pub const GHOSTTY_DA_DEVICE_TYPE_VT220: c_int = 1;
pub const GHOSTTY_DA_DEVICE_TYPE_VT240: c_int = 2;
pub const GHOSTTY_DA_DEVICE_TYPE_VT320: c_int = 24;
pub const GHOSTTY_DA_DEVICE_TYPE_VT330: c_int = 18;
pub const GHOSTTY_DA_DEVICE_TYPE_VT340: c_int = 19;
pub const GHOSTTY_DA_DEVICE_TYPE_VT382: c_int = 32;
pub const GHOSTTY_DA_DEVICE_TYPE_VT420: c_int = 41;
pub const GHOSTTY_DA_DEVICE_TYPE_VT510: c_int = 61;
pub const GHOSTTY_DA_DEVICE_TYPE_VT520: c_int = 64;
pub const GHOSTTY_DA_DEVICE_TYPE_VT525: c_int = 65;
pub const GHOSTTY_DA_FEATURE_ANSI_COLOR: c_int = 22;
pub const GHOSTTY_DA_FEATURE_ANSI_TEXT_LOCATOR: c_int = 29;
pub const GHOSTTY_DA_FEATURE_CLIPBOARD: c_int = 52;
pub const GHOSTTY_DA_FEATURE_COLUMNS_132: c_int = 1;
pub const GHOSTTY_DA_FEATURE_HORIZONTAL_SCROLLING: c_int = 21;
pub const GHOSTTY_DA_FEATURE_LOCATOR: c_int = 16;
pub const GHOSTTY_DA_FEATURE_NATIONAL_REPLACEMENT: c_int = 9;
pub const GHOSTTY_DA_FEATURE_PRINTER: c_int = 2;
pub const GHOSTTY_DA_FEATURE_RECTANGULAR_EDITING: c_int = 28;
pub const GHOSTTY_DA_FEATURE_REGIS: c_int = 3;
pub const GHOSTTY_DA_FEATURE_SELECTIVE_ERASE: c_int = 6;
pub const GHOSTTY_DA_FEATURE_SIXEL: c_int = 4;
pub const GHOSTTY_DA_FEATURE_TECHNICAL_CHARACTERS: c_int = 15;
pub const GHOSTTY_DA_FEATURE_TERMINAL_STATE: c_int = 17;
pub const GHOSTTY_DA_FEATURE_USER_DEFINED_KEYS: c_int = 8;
pub const GHOSTTY_DA_FEATURE_WINDOWING: c_int = 18;
pub const GHOSTTY_FOCUS_GAINED: GhosttyFocusEvent = 0;
pub const GHOSTTY_FOCUS_LOST: GhosttyFocusEvent = 1;
pub const GHOSTTY_FOCUS_MAX_VALUE: GhosttyFocusEvent = c_int::MAX;
pub const GHOSTTY_FORMATTER_FORMAT_HTML: GhosttyFormatterFormat = 2;
pub const GHOSTTY_FORMATTER_FORMAT_MAX_VALUE: GhosttyFormatterFormat = c_int::MAX;
pub const GHOSTTY_FORMATTER_FORMAT_PLAIN: GhosttyFormatterFormat = 0;
pub const GHOSTTY_FORMATTER_FORMAT_VT: GhosttyFormatterFormat = 1;
pub const GHOSTTY_INVALID_VALUE: GhosttyResult = -2;
pub const GHOSTTY_IO_ERROR: GhosttyResult = -5;
pub const GHOSTTY_KEY_A: GhosttyKey = 20;
pub const GHOSTTY_KEY_ACTION_MAX_VALUE: GhosttyKeyAction = c_int::MAX;
pub const GHOSTTY_KEY_ACTION_PRESS: GhosttyKeyAction = 1;
pub const GHOSTTY_KEY_ACTION_RELEASE: GhosttyKeyAction = 0;
pub const GHOSTTY_KEY_ACTION_REPEAT: GhosttyKeyAction = 2;
pub const GHOSTTY_KEY_ALT_LEFT: GhosttyKey = 51;
pub const GHOSTTY_KEY_ALT_RIGHT: GhosttyKey = 52;
pub const GHOSTTY_KEY_ARROW_DOWN: GhosttyKey = 75;
pub const GHOSTTY_KEY_ARROW_LEFT: GhosttyKey = 76;
pub const GHOSTTY_KEY_ARROW_RIGHT: GhosttyKey = 77;
pub const GHOSTTY_KEY_ARROW_UP: GhosttyKey = 78;
pub const GHOSTTY_KEY_AUDIO_VOLUME_DOWN: GhosttyKey = 169;
pub const GHOSTTY_KEY_AUDIO_VOLUME_MUTE: GhosttyKey = 170;
pub const GHOSTTY_KEY_AUDIO_VOLUME_UP: GhosttyKey = 171;
pub const GHOSTTY_KEY_B: GhosttyKey = 21;
pub const GHOSTTY_KEY_BACKQUOTE: GhosttyKey = 1;
pub const GHOSTTY_KEY_BACKSLASH: GhosttyKey = 2;
pub const GHOSTTY_KEY_BACKSPACE: GhosttyKey = 53;
pub const GHOSTTY_KEY_BRACKET_LEFT: GhosttyKey = 3;
pub const GHOSTTY_KEY_BRACKET_RIGHT: GhosttyKey = 4;
pub const GHOSTTY_KEY_BROWSER_BACK: GhosttyKey = 151;
pub const GHOSTTY_KEY_BROWSER_FAVORITES: GhosttyKey = 152;
pub const GHOSTTY_KEY_BROWSER_FORWARD: GhosttyKey = 153;
pub const GHOSTTY_KEY_BROWSER_HOME: GhosttyKey = 154;
pub const GHOSTTY_KEY_BROWSER_REFRESH: GhosttyKey = 155;
pub const GHOSTTY_KEY_BROWSER_SEARCH: GhosttyKey = 156;
pub const GHOSTTY_KEY_BROWSER_STOP: GhosttyKey = 157;
pub const GHOSTTY_KEY_C: GhosttyKey = 22;
pub const GHOSTTY_KEY_CAPS_LOCK: GhosttyKey = 54;
pub const GHOSTTY_KEY_COMMA: GhosttyKey = 5;
pub const GHOSTTY_KEY_CONTEXT_MENU: GhosttyKey = 55;
pub const GHOSTTY_KEY_CONTROL_LEFT: GhosttyKey = 56;
pub const GHOSTTY_KEY_CONTROL_RIGHT: GhosttyKey = 57;
pub const GHOSTTY_KEY_CONVERT: GhosttyKey = 65;
pub const GHOSTTY_KEY_COPY: GhosttyKey = 173;
pub const GHOSTTY_KEY_CUT: GhosttyKey = 174;
pub const GHOSTTY_KEY_D: GhosttyKey = 23;
pub const GHOSTTY_KEY_DELETE: GhosttyKey = 68;
pub const GHOSTTY_KEY_DIGIT_0: GhosttyKey = 6;
pub const GHOSTTY_KEY_DIGIT_1: GhosttyKey = 7;
pub const GHOSTTY_KEY_DIGIT_2: GhosttyKey = 8;
pub const GHOSTTY_KEY_DIGIT_3: GhosttyKey = 9;
pub const GHOSTTY_KEY_DIGIT_4: GhosttyKey = 10;
pub const GHOSTTY_KEY_DIGIT_5: GhosttyKey = 11;
pub const GHOSTTY_KEY_DIGIT_6: GhosttyKey = 12;
pub const GHOSTTY_KEY_DIGIT_7: GhosttyKey = 13;
pub const GHOSTTY_KEY_DIGIT_8: GhosttyKey = 14;
pub const GHOSTTY_KEY_DIGIT_9: GhosttyKey = 15;
pub const GHOSTTY_KEY_E: GhosttyKey = 24;
pub const GHOSTTY_KEY_EJECT: GhosttyKey = 158;
pub const GHOSTTY_KEY_ENCODER_OPT_ALT_ESC_PREFIX: GhosttyKeyEncoderOption = 3;
pub const GHOSTTY_KEY_ENCODER_OPT_BACKARROW_KEY_MODE: GhosttyKeyEncoderOption = 7;
pub const GHOSTTY_KEY_ENCODER_OPT_CURSOR_KEY_APPLICATION: GhosttyKeyEncoderOption = 0;
pub const GHOSTTY_KEY_ENCODER_OPT_IGNORE_KEYPAD_WITH_NUMLOCK: GhosttyKeyEncoderOption = 2;
pub const GHOSTTY_KEY_ENCODER_OPT_KEYPAD_KEY_APPLICATION: GhosttyKeyEncoderOption = 1;
pub const GHOSTTY_KEY_ENCODER_OPT_KITTY_FLAGS: GhosttyKeyEncoderOption = 5;
pub const GHOSTTY_KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT: GhosttyKeyEncoderOption = 6;
pub const GHOSTTY_KEY_ENCODER_OPT_MAX_VALUE: GhosttyKeyEncoderOption = c_int::MAX;
pub const GHOSTTY_KEY_ENCODER_OPT_MODIFY_OTHER_KEYS_STATE_2: GhosttyKeyEncoderOption = 4;
pub const GHOSTTY_KEY_END: GhosttyKey = 69;
pub const GHOSTTY_KEY_ENTER: GhosttyKey = 58;
pub const GHOSTTY_KEY_EQUAL: GhosttyKey = 16;
pub const GHOSTTY_KEY_ESCAPE: GhosttyKey = 120;
pub const GHOSTTY_KEY_F: GhosttyKey = 25;
pub const GHOSTTY_KEY_F1: GhosttyKey = 121;
pub const GHOSTTY_KEY_F10: GhosttyKey = 130;
pub const GHOSTTY_KEY_F11: GhosttyKey = 131;
pub const GHOSTTY_KEY_F12: GhosttyKey = 132;
pub const GHOSTTY_KEY_F13: GhosttyKey = 133;
pub const GHOSTTY_KEY_F14: GhosttyKey = 134;
pub const GHOSTTY_KEY_F15: GhosttyKey = 135;
pub const GHOSTTY_KEY_F16: GhosttyKey = 136;
pub const GHOSTTY_KEY_F17: GhosttyKey = 137;
pub const GHOSTTY_KEY_F18: GhosttyKey = 138;
pub const GHOSTTY_KEY_F19: GhosttyKey = 139;
pub const GHOSTTY_KEY_F2: GhosttyKey = 122;
pub const GHOSTTY_KEY_F20: GhosttyKey = 140;
pub const GHOSTTY_KEY_F21: GhosttyKey = 141;
pub const GHOSTTY_KEY_F22: GhosttyKey = 142;
pub const GHOSTTY_KEY_F23: GhosttyKey = 143;
pub const GHOSTTY_KEY_F24: GhosttyKey = 144;
pub const GHOSTTY_KEY_F25: GhosttyKey = 145;
pub const GHOSTTY_KEY_F3: GhosttyKey = 123;
pub const GHOSTTY_KEY_F4: GhosttyKey = 124;
pub const GHOSTTY_KEY_F5: GhosttyKey = 125;
pub const GHOSTTY_KEY_F6: GhosttyKey = 126;
pub const GHOSTTY_KEY_F7: GhosttyKey = 127;
pub const GHOSTTY_KEY_F8: GhosttyKey = 128;
pub const GHOSTTY_KEY_F9: GhosttyKey = 129;
pub const GHOSTTY_KEY_FN: GhosttyKey = 146;
pub const GHOSTTY_KEY_FN_LOCK: GhosttyKey = 147;
pub const GHOSTTY_KEY_G: GhosttyKey = 26;
pub const GHOSTTY_KEY_H: GhosttyKey = 27;
pub const GHOSTTY_KEY_HELP: GhosttyKey = 70;
pub const GHOSTTY_KEY_HOME: GhosttyKey = 71;
pub const GHOSTTY_KEY_I: GhosttyKey = 28;
pub const GHOSTTY_KEY_INSERT: GhosttyKey = 72;
pub const GHOSTTY_KEY_INTL_BACKSLASH: GhosttyKey = 17;
pub const GHOSTTY_KEY_INTL_RO: GhosttyKey = 18;
pub const GHOSTTY_KEY_INTL_YEN: GhosttyKey = 19;
pub const GHOSTTY_KEY_J: GhosttyKey = 29;
pub const GHOSTTY_KEY_K: GhosttyKey = 30;
pub const GHOSTTY_KEY_KANA_MODE: GhosttyKey = 66;
pub const GHOSTTY_KEY_L: GhosttyKey = 31;
pub const GHOSTTY_KEY_LAUNCH_APP_1: GhosttyKey = 159;
pub const GHOSTTY_KEY_LAUNCH_APP_2: GhosttyKey = 160;
pub const GHOSTTY_KEY_LAUNCH_MAIL: GhosttyKey = 161;
pub const GHOSTTY_KEY_M: GhosttyKey = 32;
pub const GHOSTTY_KEY_MAX_VALUE: GhosttyKey = c_int::MAX;
pub const GHOSTTY_KEY_MEDIA_PLAY_PAUSE: GhosttyKey = 162;
pub const GHOSTTY_KEY_MEDIA_SELECT: GhosttyKey = 163;
pub const GHOSTTY_KEY_MEDIA_STOP: GhosttyKey = 164;
pub const GHOSTTY_KEY_MEDIA_TRACK_NEXT: GhosttyKey = 165;
pub const GHOSTTY_KEY_MEDIA_TRACK_PREVIOUS: GhosttyKey = 166;
pub const GHOSTTY_KEY_META_LEFT: GhosttyKey = 59;
pub const GHOSTTY_KEY_META_RIGHT: GhosttyKey = 60;
pub const GHOSTTY_KEY_MINUS: GhosttyKey = 46;
pub const GHOSTTY_KEY_N: GhosttyKey = 33;
pub const GHOSTTY_KEY_NON_CONVERT: GhosttyKey = 67;
pub const GHOSTTY_KEY_NUMPAD_0: GhosttyKey = 80;
pub const GHOSTTY_KEY_NUMPAD_1: GhosttyKey = 81;
pub const GHOSTTY_KEY_NUMPAD_2: GhosttyKey = 82;
pub const GHOSTTY_KEY_NUMPAD_3: GhosttyKey = 83;
pub const GHOSTTY_KEY_NUMPAD_4: GhosttyKey = 84;
pub const GHOSTTY_KEY_NUMPAD_5: GhosttyKey = 85;
pub const GHOSTTY_KEY_NUMPAD_6: GhosttyKey = 86;
pub const GHOSTTY_KEY_NUMPAD_7: GhosttyKey = 87;
pub const GHOSTTY_KEY_NUMPAD_8: GhosttyKey = 88;
pub const GHOSTTY_KEY_NUMPAD_9: GhosttyKey = 89;
pub const GHOSTTY_KEY_NUMPAD_ADD: GhosttyKey = 90;
pub const GHOSTTY_KEY_NUMPAD_BACKSPACE: GhosttyKey = 91;
pub const GHOSTTY_KEY_NUMPAD_BEGIN: GhosttyKey = 113;
pub const GHOSTTY_KEY_NUMPAD_CLEAR: GhosttyKey = 92;
pub const GHOSTTY_KEY_NUMPAD_CLEAR_ENTRY: GhosttyKey = 93;
pub const GHOSTTY_KEY_NUMPAD_COMMA: GhosttyKey = 94;
pub const GHOSTTY_KEY_NUMPAD_DECIMAL: GhosttyKey = 95;
pub const GHOSTTY_KEY_NUMPAD_DELETE: GhosttyKey = 117;
pub const GHOSTTY_KEY_NUMPAD_DIVIDE: GhosttyKey = 96;
pub const GHOSTTY_KEY_NUMPAD_DOWN: GhosttyKey = 110;
pub const GHOSTTY_KEY_NUMPAD_END: GhosttyKey = 115;
pub const GHOSTTY_KEY_NUMPAD_ENTER: GhosttyKey = 97;
pub const GHOSTTY_KEY_NUMPAD_EQUAL: GhosttyKey = 98;
pub const GHOSTTY_KEY_NUMPAD_HOME: GhosttyKey = 114;
pub const GHOSTTY_KEY_NUMPAD_INSERT: GhosttyKey = 116;
pub const GHOSTTY_KEY_NUMPAD_LEFT: GhosttyKey = 112;
pub const GHOSTTY_KEY_NUMPAD_MEMORY_ADD: GhosttyKey = 99;
pub const GHOSTTY_KEY_NUMPAD_MEMORY_CLEAR: GhosttyKey = 100;
pub const GHOSTTY_KEY_NUMPAD_MEMORY_RECALL: GhosttyKey = 101;
pub const GHOSTTY_KEY_NUMPAD_MEMORY_STORE: GhosttyKey = 102;
pub const GHOSTTY_KEY_NUMPAD_MEMORY_SUBTRACT: GhosttyKey = 103;
pub const GHOSTTY_KEY_NUMPAD_MULTIPLY: GhosttyKey = 104;
pub const GHOSTTY_KEY_NUMPAD_PAGE_DOWN: GhosttyKey = 119;
pub const GHOSTTY_KEY_NUMPAD_PAGE_UP: GhosttyKey = 118;
pub const GHOSTTY_KEY_NUMPAD_PAREN_LEFT: GhosttyKey = 105;
pub const GHOSTTY_KEY_NUMPAD_PAREN_RIGHT: GhosttyKey = 106;
pub const GHOSTTY_KEY_NUMPAD_RIGHT: GhosttyKey = 111;
pub const GHOSTTY_KEY_NUMPAD_SEPARATOR: GhosttyKey = 108;
pub const GHOSTTY_KEY_NUMPAD_SUBTRACT: GhosttyKey = 107;
pub const GHOSTTY_KEY_NUMPAD_UP: GhosttyKey = 109;
pub const GHOSTTY_KEY_NUM_LOCK: GhosttyKey = 79;
pub const GHOSTTY_KEY_O: GhosttyKey = 34;
pub const GHOSTTY_KEY_P: GhosttyKey = 35;
pub const GHOSTTY_KEY_PAGE_DOWN: GhosttyKey = 73;
pub const GHOSTTY_KEY_PAGE_UP: GhosttyKey = 74;
pub const GHOSTTY_KEY_PASTE: GhosttyKey = 175;
pub const GHOSTTY_KEY_PAUSE: GhosttyKey = 150;
pub const GHOSTTY_KEY_PERIOD: GhosttyKey = 47;
pub const GHOSTTY_KEY_POWER: GhosttyKey = 167;
pub const GHOSTTY_KEY_PRINT_SCREEN: GhosttyKey = 148;
pub const GHOSTTY_KEY_Q: GhosttyKey = 36;
pub const GHOSTTY_KEY_QUOTE: GhosttyKey = 48;
pub const GHOSTTY_KEY_R: GhosttyKey = 37;
pub const GHOSTTY_KEY_S: GhosttyKey = 38;
pub const GHOSTTY_KEY_SCROLL_LOCK: GhosttyKey = 149;
pub const GHOSTTY_KEY_SEMICOLON: GhosttyKey = 49;
pub const GHOSTTY_KEY_SHIFT_LEFT: GhosttyKey = 61;
pub const GHOSTTY_KEY_SHIFT_RIGHT: GhosttyKey = 62;
pub const GHOSTTY_KEY_SLASH: GhosttyKey = 50;
pub const GHOSTTY_KEY_SLEEP: GhosttyKey = 168;
pub const GHOSTTY_KEY_SPACE: GhosttyKey = 63;
pub const GHOSTTY_KEY_T: GhosttyKey = 39;
pub const GHOSTTY_KEY_TAB: GhosttyKey = 64;
pub const GHOSTTY_KEY_U: GhosttyKey = 40;
pub const GHOSTTY_KEY_UNIDENTIFIED: GhosttyKey = 0;
pub const GHOSTTY_KEY_V: GhosttyKey = 41;
pub const GHOSTTY_KEY_W: GhosttyKey = 42;
pub const GHOSTTY_KEY_WAKE_UP: GhosttyKey = 172;
pub const GHOSTTY_KEY_X: GhosttyKey = 43;
pub const GHOSTTY_KEY_Y: GhosttyKey = 44;
pub const GHOSTTY_KEY_Z: GhosttyKey = 45;
pub const GHOSTTY_KITTY_GRAPHICS_DATA_GENERATION: GhosttyKittyGraphicsData = 2;
pub const GHOSTTY_KITTY_GRAPHICS_DATA_INVALID: GhosttyKittyGraphicsData = 0;
pub const GHOSTTY_KITTY_GRAPHICS_DATA_MAX_VALUE: GhosttyKittyGraphicsData = c_int::MAX;
pub const GHOSTTY_KITTY_GRAPHICS_DATA_PLACEMENT_ITERATOR: GhosttyKittyGraphicsData = 1;
pub const GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_COLUMNS: GhosttyKittyGraphicsPlacementData = 10;
pub const GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_IMAGE_ID: GhosttyKittyGraphicsPlacementData = 1;
pub const GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_INVALID: GhosttyKittyGraphicsPlacementData = 0;
pub const GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_IS_VIRTUAL: GhosttyKittyGraphicsPlacementData = 3;
pub const GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_MAX_VALUE: GhosttyKittyGraphicsPlacementData = c_int::MAX;
pub const GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_PLACEMENT_ID: GhosttyKittyGraphicsPlacementData = 2;
pub const GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_ROWS: GhosttyKittyGraphicsPlacementData = 11;
pub const GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_SOURCE_HEIGHT: GhosttyKittyGraphicsPlacementData = 9;
pub const GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_SOURCE_WIDTH: GhosttyKittyGraphicsPlacementData = 8;
pub const GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_SOURCE_X: GhosttyKittyGraphicsPlacementData = 6;
pub const GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_SOURCE_Y: GhosttyKittyGraphicsPlacementData = 7;
pub const GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_X_OFFSET: GhosttyKittyGraphicsPlacementData = 4;
pub const GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_Y_OFFSET: GhosttyKittyGraphicsPlacementData = 5;
pub const GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_Z: GhosttyKittyGraphicsPlacementData = 12;
pub const GHOSTTY_KITTY_GRAPHICS_PLACEMENT_ITERATOR_OPTION_LAYER: GhosttyKittyGraphicsPlacementIteratorOption = 0;
pub const GHOSTTY_KITTY_GRAPHICS_PLACEMENT_ITERATOR_OPTION_MAX_VALUE: GhosttyKittyGraphicsPlacementIteratorOption = c_int::MAX;
pub const GHOSTTY_KITTY_IMAGE_COMPRESSION_MAX_VALUE: GhosttyKittyImageCompression = c_int::MAX;
pub const GHOSTTY_KITTY_IMAGE_COMPRESSION_NONE: GhosttyKittyImageCompression = 0;
pub const GHOSTTY_KITTY_IMAGE_COMPRESSION_ZLIB_DEFLATE: GhosttyKittyImageCompression = 1;
pub const GHOSTTY_KITTY_IMAGE_DATA_COMPRESSION: GhosttyKittyGraphicsImageData = 6;
pub const GHOSTTY_KITTY_IMAGE_DATA_DATA_LEN: GhosttyKittyGraphicsImageData = 8;
pub const GHOSTTY_KITTY_IMAGE_DATA_DATA_PTR: GhosttyKittyGraphicsImageData = 7;
pub const GHOSTTY_KITTY_IMAGE_DATA_FORMAT: GhosttyKittyGraphicsImageData = 5;
pub const GHOSTTY_KITTY_IMAGE_DATA_GENERATION: GhosttyKittyGraphicsImageData = 9;
pub const GHOSTTY_KITTY_IMAGE_DATA_HEIGHT: GhosttyKittyGraphicsImageData = 4;
pub const GHOSTTY_KITTY_IMAGE_DATA_ID: GhosttyKittyGraphicsImageData = 1;
pub const GHOSTTY_KITTY_IMAGE_DATA_INVALID: GhosttyKittyGraphicsImageData = 0;
pub const GHOSTTY_KITTY_IMAGE_DATA_MAX_VALUE: GhosttyKittyGraphicsImageData = c_int::MAX;
pub const GHOSTTY_KITTY_IMAGE_DATA_NUMBER: GhosttyKittyGraphicsImageData = 2;
pub const GHOSTTY_KITTY_IMAGE_DATA_WIDTH: GhosttyKittyGraphicsImageData = 3;
pub const GHOSTTY_KITTY_IMAGE_FORMAT_GRAY: GhosttyKittyImageFormat = 4;
pub const GHOSTTY_KITTY_IMAGE_FORMAT_GRAY_ALPHA: GhosttyKittyImageFormat = 3;
pub const GHOSTTY_KITTY_IMAGE_FORMAT_MAX_VALUE: GhosttyKittyImageFormat = c_int::MAX;
pub const GHOSTTY_KITTY_IMAGE_FORMAT_PNG: GhosttyKittyImageFormat = 2;
pub const GHOSTTY_KITTY_IMAGE_FORMAT_RGB: GhosttyKittyImageFormat = 0;
pub const GHOSTTY_KITTY_IMAGE_FORMAT_RGBA: GhosttyKittyImageFormat = 1;
pub const GHOSTTY_KITTY_KEY_DISABLED: c_int = 0;
pub const GHOSTTY_KITTY_KEY_DISAMBIGUATE: c_int = 1 << 0;
pub const GHOSTTY_KITTY_KEY_REPORT_ALL: c_int = 1 << 3;
pub const GHOSTTY_KITTY_KEY_REPORT_ALTERNATES: c_int = 1 << 2;
pub const GHOSTTY_KITTY_KEY_REPORT_ASSOCIATED: c_int = 1 << 4;
pub const GHOSTTY_KITTY_KEY_REPORT_EVENTS: c_int = 1 << 1;
pub const GHOSTTY_KITTY_PLACEMENT_LAYER_ABOVE_TEXT: GhosttyKittyPlacementLayer = 3;
pub const GHOSTTY_KITTY_PLACEMENT_LAYER_ALL: GhosttyKittyPlacementLayer = 0;
pub const GHOSTTY_KITTY_PLACEMENT_LAYER_BELOW_BG: GhosttyKittyPlacementLayer = 1;
pub const GHOSTTY_KITTY_PLACEMENT_LAYER_BELOW_TEXT: GhosttyKittyPlacementLayer = 2;
pub const GHOSTTY_KITTY_PLACEMENT_LAYER_MAX_VALUE: GhosttyKittyPlacementLayer = c_int::MAX;
pub const GHOSTTY_LIMIT_EXCEEDED: GhosttyResult = -6;
pub const GHOSTTY_MODE_REPORT_MAX_VALUE: GhosttyModeReportState = c_int::MAX;
pub const GHOSTTY_MODE_REPORT_NOT_RECOGNIZED: GhosttyModeReportState = 0;
pub const GHOSTTY_MODE_REPORT_PERMANENTLY_RESET: GhosttyModeReportState = 4;
pub const GHOSTTY_MODE_REPORT_PERMANENTLY_SET: GhosttyModeReportState = 3;
pub const GHOSTTY_MODE_REPORT_RESET: GhosttyModeReportState = 2;
pub const GHOSTTY_MODE_REPORT_SET: GhosttyModeReportState = 1;
pub const GHOSTTY_MODS_ALT: c_int = 1 << 2;
pub const GHOSTTY_MODS_ALT_SIDE: c_int = 1 << 8;
pub const GHOSTTY_MODS_CAPS_LOCK: c_int = 1 << 4;
pub const GHOSTTY_MODS_CTRL: c_int = 1 << 1;
pub const GHOSTTY_MODS_CTRL_SIDE: c_int = 1 << 7;
pub const GHOSTTY_MODS_NUM_LOCK: c_int = 1 << 5;
pub const GHOSTTY_MODS_SHIFT: c_int = 1 << 0;
pub const GHOSTTY_MODS_SHIFT_SIDE: c_int = 1 << 6;
pub const GHOSTTY_MODS_SUPER: c_int = 1 << 3;
pub const GHOSTTY_MODS_SUPER_SIDE: c_int = 1 << 9;
pub const GHOSTTY_MOUSE_ACTION_MAX_VALUE: GhosttyMouseAction = c_int::MAX;
pub const GHOSTTY_MOUSE_ACTION_MOTION: GhosttyMouseAction = 2;
pub const GHOSTTY_MOUSE_ACTION_PRESS: GhosttyMouseAction = 0;
pub const GHOSTTY_MOUSE_ACTION_RELEASE: GhosttyMouseAction = 1;
pub const GHOSTTY_MOUSE_BUTTON_EIGHT: GhosttyMouseButton = 8;
pub const GHOSTTY_MOUSE_BUTTON_ELEVEN: GhosttyMouseButton = 11;
pub const GHOSTTY_MOUSE_BUTTON_FIVE: GhosttyMouseButton = 5;
pub const GHOSTTY_MOUSE_BUTTON_FOUR: GhosttyMouseButton = 4;
pub const GHOSTTY_MOUSE_BUTTON_LEFT: GhosttyMouseButton = 1;
pub const GHOSTTY_MOUSE_BUTTON_MAX_VALUE: GhosttyMouseButton = c_int::MAX;
pub const GHOSTTY_MOUSE_BUTTON_MIDDLE: GhosttyMouseButton = 3;
pub const GHOSTTY_MOUSE_BUTTON_NINE: GhosttyMouseButton = 9;
pub const GHOSTTY_MOUSE_BUTTON_RIGHT: GhosttyMouseButton = 2;
pub const GHOSTTY_MOUSE_BUTTON_SEVEN: GhosttyMouseButton = 7;
pub const GHOSTTY_MOUSE_BUTTON_SIX: GhosttyMouseButton = 6;
pub const GHOSTTY_MOUSE_BUTTON_TEN: GhosttyMouseButton = 10;
pub const GHOSTTY_MOUSE_BUTTON_UNKNOWN: GhosttyMouseButton = 0;
pub const GHOSTTY_MOUSE_ENCODER_OPT_ANY_BUTTON_PRESSED: GhosttyMouseEncoderOption = 3;
pub const GHOSTTY_MOUSE_ENCODER_OPT_EVENT: GhosttyMouseEncoderOption = 0;
pub const GHOSTTY_MOUSE_ENCODER_OPT_FORMAT: GhosttyMouseEncoderOption = 1;
pub const GHOSTTY_MOUSE_ENCODER_OPT_MAX_VALUE: GhosttyMouseEncoderOption = c_int::MAX;
pub const GHOSTTY_MOUSE_ENCODER_OPT_SIZE: GhosttyMouseEncoderOption = 2;
pub const GHOSTTY_MOUSE_ENCODER_OPT_TRACK_LAST_CELL: GhosttyMouseEncoderOption = 4;
pub const GHOSTTY_MOUSE_FORMAT_MAX_VALUE: GhosttyMouseFormat = c_int::MAX;
pub const GHOSTTY_MOUSE_FORMAT_SGR: GhosttyMouseFormat = 2;
pub const GHOSTTY_MOUSE_FORMAT_SGR_PIXELS: GhosttyMouseFormat = 4;
pub const GHOSTTY_MOUSE_FORMAT_URXVT: GhosttyMouseFormat = 3;
pub const GHOSTTY_MOUSE_FORMAT_UTF8: GhosttyMouseFormat = 1;
pub const GHOSTTY_MOUSE_FORMAT_X10: GhosttyMouseFormat = 0;
pub const GHOSTTY_MOUSE_TRACKING_ANY: GhosttyMouseTrackingMode = 4;
pub const GHOSTTY_MOUSE_TRACKING_BUTTON: GhosttyMouseTrackingMode = 3;
pub const GHOSTTY_MOUSE_TRACKING_MAX_VALUE: GhosttyMouseTrackingMode = c_int::MAX;
pub const GHOSTTY_MOUSE_TRACKING_NONE: GhosttyMouseTrackingMode = 0;
pub const GHOSTTY_MOUSE_TRACKING_NORMAL: GhosttyMouseTrackingMode = 2;
pub const GHOSTTY_MOUSE_TRACKING_X10: GhosttyMouseTrackingMode = 1;
pub const GHOSTTY_NO_VALUE: GhosttyResult = -4;
pub const GHOSTTY_OPTIMIZE_DEBUG: GhosttyOptimizeMode = 0;
pub const GHOSTTY_OPTIMIZE_MODE_MAX_VALUE: GhosttyOptimizeMode = c_int::MAX;
pub const GHOSTTY_OPTIMIZE_RELEASE_FAST: GhosttyOptimizeMode = 3;
pub const GHOSTTY_OPTIMIZE_RELEASE_SAFE: GhosttyOptimizeMode = 1;
pub const GHOSTTY_OPTIMIZE_RELEASE_SMALL: GhosttyOptimizeMode = 2;
pub const GHOSTTY_OPTION_AS_ALT_FALSE: GhosttyOptionAsAlt = 0;
pub const GHOSTTY_OPTION_AS_ALT_LEFT: GhosttyOptionAsAlt = 2;
pub const GHOSTTY_OPTION_AS_ALT_MAX_VALUE: GhosttyOptionAsAlt = c_int::MAX;
pub const GHOSTTY_OPTION_AS_ALT_RIGHT: GhosttyOptionAsAlt = 3;
pub const GHOSTTY_OPTION_AS_ALT_TRUE: GhosttyOptionAsAlt = 1;
pub const GHOSTTY_OSC_COMMAND_CHANGE_WINDOW_ICON: GhosttyOscCommandType = 2;
pub const GHOSTTY_OSC_COMMAND_CHANGE_WINDOW_TITLE: GhosttyOscCommandType = 1;
pub const GHOSTTY_OSC_COMMAND_CLIPBOARD_CONTENTS: GhosttyOscCommandType = 4;
pub const GHOSTTY_OSC_COMMAND_COLOR_OPERATION: GhosttyOscCommandType = 7;
pub const GHOSTTY_OSC_COMMAND_CONEMU_CHANGE_TAB_TITLE: GhosttyOscCommandType = 14;
pub const GHOSTTY_OSC_COMMAND_CONEMU_COMMENT: GhosttyOscCommandType = 21;
pub const GHOSTTY_OSC_COMMAND_CONEMU_GUIMACRO: GhosttyOscCommandType = 17;
pub const GHOSTTY_OSC_COMMAND_CONEMU_OUTPUT_ENVIRONMENT_VARIABLE: GhosttyOscCommandType = 19;
pub const GHOSTTY_OSC_COMMAND_CONEMU_PROGRESS_REPORT: GhosttyOscCommandType = 15;
pub const GHOSTTY_OSC_COMMAND_CONEMU_RUN_PROCESS: GhosttyOscCommandType = 18;
pub const GHOSTTY_OSC_COMMAND_CONEMU_SHOW_MESSAGE_BOX: GhosttyOscCommandType = 13;
pub const GHOSTTY_OSC_COMMAND_CONEMU_SLEEP: GhosttyOscCommandType = 12;
pub const GHOSTTY_OSC_COMMAND_CONEMU_WAIT_INPUT: GhosttyOscCommandType = 16;
pub const GHOSTTY_OSC_COMMAND_CONEMU_XTERM_EMULATION: GhosttyOscCommandType = 20;
pub const GHOSTTY_OSC_COMMAND_CONTEXT_SIGNAL: GhosttyOscCommandType = 25;
pub const GHOSTTY_OSC_COMMAND_HYPERLINK_END: GhosttyOscCommandType = 11;
pub const GHOSTTY_OSC_COMMAND_HYPERLINK_START: GhosttyOscCommandType = 10;
pub const GHOSTTY_OSC_COMMAND_INVALID: GhosttyOscCommandType = 0;
pub const GHOSTTY_OSC_COMMAND_KITTY_CLIPBOARD_PROTOCOL: GhosttyOscCommandType = 23;
pub const GHOSTTY_OSC_COMMAND_KITTY_COLOR_PROTOCOL: GhosttyOscCommandType = 8;
pub const GHOSTTY_OSC_COMMAND_KITTY_DESKTOP_NOTIFICATION: GhosttyOscCommandType = 26;
pub const GHOSTTY_OSC_COMMAND_KITTY_DND_PROTOCOL: GhosttyOscCommandType = 24;
pub const GHOSTTY_OSC_COMMAND_KITTY_TEXT_SIZING: GhosttyOscCommandType = 22;
pub const GHOSTTY_OSC_COMMAND_MOUSE_SHAPE: GhosttyOscCommandType = 6;
pub const GHOSTTY_OSC_COMMAND_REPORT_PWD: GhosttyOscCommandType = 5;
pub const GHOSTTY_OSC_COMMAND_SEMANTIC_PROMPT: GhosttyOscCommandType = 3;
pub const GHOSTTY_OSC_COMMAND_SHOW_DESKTOP_NOTIFICATION: GhosttyOscCommandType = 9;
pub const GHOSTTY_OSC_COMMAND_TYPE_MAX_VALUE: GhosttyOscCommandType = c_int::MAX;
pub const GHOSTTY_OSC_DATA_CHANGE_WINDOW_TITLE_STR: GhosttyOscCommandData = 1;
pub const GHOSTTY_OSC_DATA_INVALID: GhosttyOscCommandData = 0;
pub const GHOSTTY_OSC_DATA_MAX_VALUE: GhosttyOscCommandData = c_int::MAX;
pub const GHOSTTY_OUT_OF_MEMORY: GhosttyResult = -1;
pub const GHOSTTY_OUT_OF_SPACE: GhosttyResult = -3;
pub const GHOSTTY_PASTE_SOURCE_CLIPBOARD: GhosttyPasteSource = 0;
pub const GHOSTTY_PASTE_SOURCE_MAX_VALUE: GhosttyPasteSource = c_int::MAX;
pub const GHOSTTY_PASTE_SOURCE_TEXT: GhosttyPasteSource = 1;
pub const GHOSTTY_POINT_TAG_ACTIVE: GhosttyPointTag = 0;
pub const GHOSTTY_POINT_TAG_HISTORY: GhosttyPointTag = 3;
pub const GHOSTTY_POINT_TAG_MAX_VALUE: GhosttyPointTag = c_int::MAX;
pub const GHOSTTY_POINT_TAG_SCREEN: GhosttyPointTag = 2;
pub const GHOSTTY_POINT_TAG_VIEWPORT: GhosttyPointTag = 1;
pub const GHOSTTY_REJECTED: GhosttyResult = -7;
pub const GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BAR: GhosttyRenderStateCursorVisualStyle = 0;
pub const GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK: GhosttyRenderStateCursorVisualStyle = 1;
pub const GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK_HOLLOW: GhosttyRenderStateCursorVisualStyle = 3;
pub const GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_MAX_VALUE: GhosttyRenderStateCursorVisualStyle = c_int::MAX;
pub const GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_UNDERLINE: GhosttyRenderStateCursorVisualStyle = 2;
pub const GHOSTTY_RENDER_STATE_DATA_COLORS: GhosttyRenderStateData = 19;
pub const GHOSTTY_RENDER_STATE_DATA_COLOR_BACKGROUND: GhosttyRenderStateData = 5;
pub const GHOSTTY_RENDER_STATE_DATA_COLOR_CURSOR: GhosttyRenderStateData = 7;
pub const GHOSTTY_RENDER_STATE_DATA_COLOR_CURSOR_HAS_VALUE: GhosttyRenderStateData = 8;
pub const GHOSTTY_RENDER_STATE_DATA_COLOR_FOREGROUND: GhosttyRenderStateData = 6;
pub const GHOSTTY_RENDER_STATE_DATA_COLOR_PALETTE: GhosttyRenderStateData = 9;
pub const GHOSTTY_RENDER_STATE_DATA_COLS: GhosttyRenderStateData = 1;
pub const GHOSTTY_RENDER_STATE_DATA_CURSOR: GhosttyRenderStateData = 18;
pub const GHOSTTY_RENDER_STATE_DATA_CURSOR_BLINKING: GhosttyRenderStateData = 12;
pub const GHOSTTY_RENDER_STATE_DATA_CURSOR_PASSWORD_INPUT: GhosttyRenderStateData = 13;
pub const GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_HAS_VALUE: GhosttyRenderStateData = 14;
pub const GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_WIDE_TAIL: GhosttyRenderStateData = 17;
pub const GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_X: GhosttyRenderStateData = 15;
pub const GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_Y: GhosttyRenderStateData = 16;
pub const GHOSTTY_RENDER_STATE_DATA_CURSOR_VISIBLE: GhosttyRenderStateData = 11;
pub const GHOSTTY_RENDER_STATE_DATA_CURSOR_VISUAL_STYLE: GhosttyRenderStateData = 10;
pub const GHOSTTY_RENDER_STATE_DATA_DIRTY: GhosttyRenderStateData = 3;
pub const GHOSTTY_RENDER_STATE_DATA_INVALID: GhosttyRenderStateData = 0;
pub const GHOSTTY_RENDER_STATE_DATA_MAX_VALUE: GhosttyRenderStateData = c_int::MAX;
pub const GHOSTTY_RENDER_STATE_DATA_ROWS: GhosttyRenderStateData = 2;
pub const GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR: GhosttyRenderStateData = 4;
pub const GHOSTTY_RENDER_STATE_DIRTY_FALSE: GhosttyRenderStateDirty = 0;
pub const GHOSTTY_RENDER_STATE_DIRTY_FULL: GhosttyRenderStateDirty = 2;
pub const GHOSTTY_RENDER_STATE_DIRTY_MAX_VALUE: GhosttyRenderStateDirty = c_int::MAX;
pub const GHOSTTY_RENDER_STATE_DIRTY_PARTIAL: GhosttyRenderStateDirty = 1;
pub const GHOSTTY_RENDER_STATE_OPTION_DIRTY: GhosttyRenderStateOption = 0;
pub const GHOSTTY_RENDER_STATE_OPTION_MAX_VALUE: GhosttyRenderStateOption = c_int::MAX;
pub const GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_BG_COLOR: GhosttyRenderStateRowCellsData = 5;
pub const GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_FG_COLOR: GhosttyRenderStateRowCellsData = 6;
pub const GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF: GhosttyRenderStateRowCellsData = 4;
pub const GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN: GhosttyRenderStateRowCellsData = 3;
pub const GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_UTF8: GhosttyRenderStateRowCellsData = 9;
pub const GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_HAS_STYLING: GhosttyRenderStateRowCellsData = 8;
pub const GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_INVALID: GhosttyRenderStateRowCellsData = 0;
pub const GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_MAX_VALUE: GhosttyRenderStateRowCellsData = c_int::MAX;
pub const GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW: GhosttyRenderStateRowCellsData = 1;
pub const GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_SELECTED: GhosttyRenderStateRowCellsData = 7;
pub const GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE: GhosttyRenderStateRowCellsData = 2;
pub const GHOSTTY_RENDER_STATE_ROW_DATA_CELLS: GhosttyRenderStateRowData = 3;
pub const GHOSTTY_RENDER_STATE_ROW_DATA_CELLS_RAW: GhosttyRenderStateRowData = 5;
pub const GHOSTTY_RENDER_STATE_ROW_DATA_DIRTY: GhosttyRenderStateRowData = 1;
pub const GHOSTTY_RENDER_STATE_ROW_DATA_INVALID: GhosttyRenderStateRowData = 0;
pub const GHOSTTY_RENDER_STATE_ROW_DATA_MAX_VALUE: GhosttyRenderStateRowData = c_int::MAX;
pub const GHOSTTY_RENDER_STATE_ROW_DATA_RAW: GhosttyRenderStateRowData = 2;
pub const GHOSTTY_RENDER_STATE_ROW_DATA_SELECTION: GhosttyRenderStateRowData = 4;
pub const GHOSTTY_RENDER_STATE_ROW_OPTION_DIRTY: GhosttyRenderStateRowOption = 0;
pub const GHOSTTY_RENDER_STATE_ROW_OPTION_MAX_VALUE: GhosttyRenderStateRowOption = c_int::MAX;
pub const GHOSTTY_RESULT_MAX_VALUE: GhosttyResult = c_int::MAX;
pub const GHOSTTY_ROW_DATA_DIRTY: GhosttyRowData = 8;
pub const GHOSTTY_ROW_DATA_GRAPHEME: GhosttyRowData = 3;
pub const GHOSTTY_ROW_DATA_HYPERLINK: GhosttyRowData = 5;
pub const GHOSTTY_ROW_DATA_INVALID: GhosttyRowData = 0;
pub const GHOSTTY_ROW_DATA_KITTY_VIRTUAL_PLACEHOLDER: GhosttyRowData = 7;
pub const GHOSTTY_ROW_DATA_MAX_VALUE: GhosttyRowData = c_int::MAX;
pub const GHOSTTY_ROW_DATA_SEMANTIC_PROMPT: GhosttyRowData = 6;
pub const GHOSTTY_ROW_DATA_STYLED: GhosttyRowData = 4;
pub const GHOSTTY_ROW_DATA_WRAP: GhosttyRowData = 1;
pub const GHOSTTY_ROW_DATA_WRAP_CONTINUATION: GhosttyRowData = 2;
pub const GHOSTTY_ROW_SEMANTIC_MAX_VALUE: GhosttyRowSemanticPrompt = c_int::MAX;
pub const GHOSTTY_ROW_SEMANTIC_NONE: GhosttyRowSemanticPrompt = 0;
pub const GHOSTTY_ROW_SEMANTIC_PROMPT: GhosttyRowSemanticPrompt = 1;
pub const GHOSTTY_ROW_SEMANTIC_PROMPT_CONTINUATION: GhosttyRowSemanticPrompt = 2;
pub const GHOSTTY_SCROLL_VIEWPORT_BOTTOM: GhosttyTerminalScrollViewportTag = 1;
pub const GHOSTTY_SCROLL_VIEWPORT_DELTA: GhosttyTerminalScrollViewportTag = 2;
pub const GHOSTTY_SCROLL_VIEWPORT_MAX_VALUE: GhosttyTerminalScrollViewportTag = c_int::MAX;
pub const GHOSTTY_SCROLL_VIEWPORT_ROW: GhosttyTerminalScrollViewportTag = 3;
pub const GHOSTTY_SCROLL_VIEWPORT_TOP: GhosttyTerminalScrollViewportTag = 0;
pub const GHOSTTY_SEARCH_DATA_MATCHES: GhosttySearchData = 5;
pub const GHOSTTY_SEARCH_DATA_MAX_VALUE: GhosttySearchData = c_int::MAX;
pub const GHOSTTY_SEARCH_DATA_NEEDLE: GhosttySearchData = 1;
pub const GHOSTTY_SEARCH_DATA_SELECTED_INDEX: GhosttySearchData = 3;
pub const GHOSTTY_SEARCH_DATA_SELECTED_MATCH: GhosttySearchData = 4;
pub const GHOSTTY_SEARCH_DATA_SELECT_SCROLL: GhosttySearchData = 7;
pub const GHOSTTY_SEARCH_DATA_STATUS: GhosttySearchData = 0;
pub const GHOSTTY_SEARCH_DATA_TOTAL_MATCHES: GhosttySearchData = 2;
pub const GHOSTTY_SEARCH_DATA_VIEWPORT_MATCHES: GhosttySearchData = 6;
pub const GHOSTTY_SEARCH_OPT_MAX_VALUE: GhosttySearchOption = c_int::MAX;
pub const GHOSTTY_SEARCH_OPT_NEEDLE: GhosttySearchOption = 0;
pub const GHOSTTY_SEARCH_OPT_SELECT_NEXT: GhosttySearchOption = 1;
pub const GHOSTTY_SEARCH_OPT_SELECT_PREV: GhosttySearchOption = 2;
pub const GHOSTTY_SEARCH_OPT_SELECT_SCROLL: GhosttySearchOption = 3;
pub const GHOSTTY_SEARCH_SCROLL_IF_NEEDED: GhosttySearchScroll = 0;
pub const GHOSTTY_SEARCH_SCROLL_MAX_VALUE: GhosttySearchScroll = c_int::MAX;
pub const GHOSTTY_SEARCH_SCROLL_NONE: GhosttySearchScroll = 1;
pub const GHOSTTY_SEARCH_STATUS_COMPLETE: GhosttySearchStatus = 2;
pub const GHOSTTY_SEARCH_STATUS_FEED_REQUIRED: GhosttySearchStatus = 1;
pub const GHOSTTY_SEARCH_STATUS_MAX_VALUE: GhosttySearchStatus = c_int::MAX;
pub const GHOSTTY_SEARCH_STATUS_RUNNING: GhosttySearchStatus = 0;
pub const GHOSTTY_SELECTION_ADJUST_BEGINNING_OF_LINE: GhosttySelectionAdjust = 8;
pub const GHOSTTY_SELECTION_ADJUST_DOWN: GhosttySelectionAdjust = 3;
pub const GHOSTTY_SELECTION_ADJUST_END: GhosttySelectionAdjust = 5;
pub const GHOSTTY_SELECTION_ADJUST_END_OF_LINE: GhosttySelectionAdjust = 9;
pub const GHOSTTY_SELECTION_ADJUST_HOME: GhosttySelectionAdjust = 4;
pub const GHOSTTY_SELECTION_ADJUST_LEFT: GhosttySelectionAdjust = 0;
pub const GHOSTTY_SELECTION_ADJUST_MAX_VALUE: GhosttySelectionAdjust = c_int::MAX;
pub const GHOSTTY_SELECTION_ADJUST_PAGE_DOWN: GhosttySelectionAdjust = 7;
pub const GHOSTTY_SELECTION_ADJUST_PAGE_UP: GhosttySelectionAdjust = 6;
pub const GHOSTTY_SELECTION_ADJUST_RIGHT: GhosttySelectionAdjust = 1;
pub const GHOSTTY_SELECTION_ADJUST_UP: GhosttySelectionAdjust = 2;
pub const GHOSTTY_SELECTION_GESTURE_AUTOSCROLL_DOWN: GhosttySelectionGestureAutoscroll = 2;
pub const GHOSTTY_SELECTION_GESTURE_AUTOSCROLL_MAX_VALUE: GhosttySelectionGestureAutoscroll = c_int::MAX;
pub const GHOSTTY_SELECTION_GESTURE_AUTOSCROLL_NONE: GhosttySelectionGestureAutoscroll = 0;
pub const GHOSTTY_SELECTION_GESTURE_AUTOSCROLL_UP: GhosttySelectionGestureAutoscroll = 1;
pub const GHOSTTY_SELECTION_GESTURE_BEHAVIOR_CELL: GhosttySelectionGestureBehavior = 0;
pub const GHOSTTY_SELECTION_GESTURE_BEHAVIOR_LINE: GhosttySelectionGestureBehavior = 2;
pub const GHOSTTY_SELECTION_GESTURE_BEHAVIOR_MAX_VALUE: GhosttySelectionGestureBehavior = c_int::MAX;
pub const GHOSTTY_SELECTION_GESTURE_BEHAVIOR_OUTPUT: GhosttySelectionGestureBehavior = 3;
pub const GHOSTTY_SELECTION_GESTURE_BEHAVIOR_WORD: GhosttySelectionGestureBehavior = 1;
pub const GHOSTTY_SELECTION_GESTURE_DATA_ANCHOR: GhosttySelectionGestureData = 4;
pub const GHOSTTY_SELECTION_GESTURE_DATA_AUTOSCROLL: GhosttySelectionGestureData = 2;
pub const GHOSTTY_SELECTION_GESTURE_DATA_BEHAVIOR: GhosttySelectionGestureData = 3;
pub const GHOSTTY_SELECTION_GESTURE_DATA_CLICK_COUNT: GhosttySelectionGestureData = 0;
pub const GHOSTTY_SELECTION_GESTURE_DATA_DRAGGED: GhosttySelectionGestureData = 1;
pub const GHOSTTY_SELECTION_GESTURE_DATA_MAX_VALUE: GhosttySelectionGestureData = c_int::MAX;
pub const GHOSTTY_SELECTION_GESTURE_EVENT_OPT_BEHAVIORS: GhosttySelectionGestureEventOption = 6;
pub const GHOSTTY_SELECTION_GESTURE_EVENT_OPT_GEOMETRY: GhosttySelectionGestureEventOption = 8;
pub const GHOSTTY_SELECTION_GESTURE_EVENT_OPT_MAX_VALUE: GhosttySelectionGestureEventOption = c_int::MAX;
pub const GHOSTTY_SELECTION_GESTURE_EVENT_OPT_POSITION: GhosttySelectionGestureEventOption = 1;
pub const GHOSTTY_SELECTION_GESTURE_EVENT_OPT_RECTANGLE: GhosttySelectionGestureEventOption = 7;
pub const GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF: GhosttySelectionGestureEventOption = 0;
pub const GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REPEAT_DISTANCE: GhosttySelectionGestureEventOption = 2;
pub const GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REPEAT_INTERVAL_NS: GhosttySelectionGestureEventOption = 4;
pub const GHOSTTY_SELECTION_GESTURE_EVENT_OPT_TIME_NS: GhosttySelectionGestureEventOption = 3;
pub const GHOSTTY_SELECTION_GESTURE_EVENT_OPT_VIEWPORT: GhosttySelectionGestureEventOption = 9;
pub const GHOSTTY_SELECTION_GESTURE_EVENT_OPT_WORD_BOUNDARY_CODEPOINTS: GhosttySelectionGestureEventOption = 5;
pub const GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_AUTOSCROLL_TICK: GhosttySelectionGestureEventType = 3;
pub const GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_DEEP_PRESS: GhosttySelectionGestureEventType = 4;
pub const GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_DRAG: GhosttySelectionGestureEventType = 2;
pub const GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_MAX_VALUE: GhosttySelectionGestureEventType = c_int::MAX;
pub const GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_PRESS: GhosttySelectionGestureEventType = 0;
pub const GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_RELEASE: GhosttySelectionGestureEventType = 1;
pub const GHOSTTY_SELECTION_ORDER_FORWARD: GhosttySelectionOrder = 0;
pub const GHOSTTY_SELECTION_ORDER_MAX_VALUE: GhosttySelectionOrder = c_int::MAX;
pub const GHOSTTY_SELECTION_ORDER_MIRRORED_FORWARD: GhosttySelectionOrder = 2;
pub const GHOSTTY_SELECTION_ORDER_MIRRORED_REVERSE: GhosttySelectionOrder = 3;
pub const GHOSTTY_SELECTION_ORDER_REVERSE: GhosttySelectionOrder = 1;
pub const GHOSTTY_SGR_ATTR_BG_256: GhosttySgrAttributeTag = 29;
pub const GHOSTTY_SGR_ATTR_BG_8: GhosttySgrAttributeTag = 23;
pub const GHOSTTY_SGR_ATTR_BLINK: GhosttySgrAttributeTag = 13;
pub const GHOSTTY_SGR_ATTR_BOLD: GhosttySgrAttributeTag = 2;
pub const GHOSTTY_SGR_ATTR_BRIGHT_BG_8: GhosttySgrAttributeTag = 27;
pub const GHOSTTY_SGR_ATTR_BRIGHT_FG_8: GhosttySgrAttributeTag = 28;
pub const GHOSTTY_SGR_ATTR_DIRECT_COLOR_BG: GhosttySgrAttributeTag = 22;
pub const GHOSTTY_SGR_ATTR_DIRECT_COLOR_FG: GhosttySgrAttributeTag = 21;
pub const GHOSTTY_SGR_ATTR_FAINT: GhosttySgrAttributeTag = 6;
pub const GHOSTTY_SGR_ATTR_FG_256: GhosttySgrAttributeTag = 30;
pub const GHOSTTY_SGR_ATTR_FG_8: GhosttySgrAttributeTag = 24;
pub const GHOSTTY_SGR_ATTR_INVERSE: GhosttySgrAttributeTag = 15;
pub const GHOSTTY_SGR_ATTR_INVISIBLE: GhosttySgrAttributeTag = 17;
pub const GHOSTTY_SGR_ATTR_ITALIC: GhosttySgrAttributeTag = 4;
pub const GHOSTTY_SGR_ATTR_MAX_VALUE: GhosttySgrAttributeTag = c_int::MAX;
pub const GHOSTTY_SGR_ATTR_OVERLINE: GhosttySgrAttributeTag = 11;
pub const GHOSTTY_SGR_ATTR_RESET_BG: GhosttySgrAttributeTag = 26;
pub const GHOSTTY_SGR_ATTR_RESET_BLINK: GhosttySgrAttributeTag = 14;
pub const GHOSTTY_SGR_ATTR_RESET_BOLD: GhosttySgrAttributeTag = 3;
pub const GHOSTTY_SGR_ATTR_RESET_FG: GhosttySgrAttributeTag = 25;
pub const GHOSTTY_SGR_ATTR_RESET_INVERSE: GhosttySgrAttributeTag = 16;
pub const GHOSTTY_SGR_ATTR_RESET_INVISIBLE: GhosttySgrAttributeTag = 18;
pub const GHOSTTY_SGR_ATTR_RESET_ITALIC: GhosttySgrAttributeTag = 5;
pub const GHOSTTY_SGR_ATTR_RESET_OVERLINE: GhosttySgrAttributeTag = 12;
pub const GHOSTTY_SGR_ATTR_RESET_STRIKETHROUGH: GhosttySgrAttributeTag = 20;
pub const GHOSTTY_SGR_ATTR_RESET_UNDERLINE_COLOR: GhosttySgrAttributeTag = 10;
pub const GHOSTTY_SGR_ATTR_STRIKETHROUGH: GhosttySgrAttributeTag = 19;
pub const GHOSTTY_SGR_ATTR_UNDERLINE: GhosttySgrAttributeTag = 7;
pub const GHOSTTY_SGR_ATTR_UNDERLINE_COLOR: GhosttySgrAttributeTag = 8;
pub const GHOSTTY_SGR_ATTR_UNDERLINE_COLOR_256: GhosttySgrAttributeTag = 9;
pub const GHOSTTY_SGR_ATTR_UNKNOWN: GhosttySgrAttributeTag = 1;
pub const GHOSTTY_SGR_ATTR_UNSET: GhosttySgrAttributeTag = 0;
pub const GHOSTTY_SGR_UNDERLINE_CURLY: GhosttySgrUnderline = 3;
pub const GHOSTTY_SGR_UNDERLINE_DASHED: GhosttySgrUnderline = 5;
pub const GHOSTTY_SGR_UNDERLINE_DOTTED: GhosttySgrUnderline = 4;
pub const GHOSTTY_SGR_UNDERLINE_DOUBLE: GhosttySgrUnderline = 2;
pub const GHOSTTY_SGR_UNDERLINE_MAX_VALUE: GhosttySgrUnderline = c_int::MAX;
pub const GHOSTTY_SGR_UNDERLINE_NONE: GhosttySgrUnderline = 0;
pub const GHOSTTY_SGR_UNDERLINE_SINGLE: GhosttySgrUnderline = 1;
pub const GHOSTTY_SIZE_REPORT_CSI_14_T: GhosttySizeReportStyle = 1;
pub const GHOSTTY_SIZE_REPORT_CSI_16_T: GhosttySizeReportStyle = 2;
pub const GHOSTTY_SIZE_REPORT_CSI_18_T: GhosttySizeReportStyle = 3;
pub const GHOSTTY_SIZE_REPORT_MODE_2048: GhosttySizeReportStyle = 0;
pub const GHOSTTY_SIZE_REPORT_STYLE_MAX_VALUE: GhosttySizeReportStyle = c_int::MAX;
pub const GHOSTTY_SNAPSHOT_DECODER_DATA_HISTORY_ROWS_ALTERNATE: GhosttySnapshotDecoderData = 4;
pub const GHOSTTY_SNAPSHOT_DECODER_DATA_HISTORY_ROWS_PRIMARY: GhosttySnapshotDecoderData = 3;
pub const GHOSTTY_SNAPSHOT_DECODER_DATA_INVALID: GhosttySnapshotDecoderData = 0;
pub const GHOSTTY_SNAPSHOT_DECODER_DATA_MAX_CONTINUATION_BYTES: GhosttySnapshotDecoderData = 1;
pub const GHOSTTY_SNAPSHOT_DECODER_DATA_MAX_VALUE: GhosttySnapshotDecoderData = c_int::MAX;
pub const GHOSTTY_SNAPSHOT_DECODER_DATA_PROGRESS_REMAINING: GhosttySnapshotDecoderData = 7;
pub const GHOSTTY_SNAPSHOT_DECODER_DATA_PROGRESS_ROWS: GhosttySnapshotDecoderData = 6;
pub const GHOSTTY_SNAPSHOT_DECODER_DATA_PROGRESS_SCREEN: GhosttySnapshotDecoderData = 5;
pub const GHOSTTY_SNAPSHOT_DECODER_DATA_RETAIN_CONTINUATION: GhosttySnapshotDecoderData = 8;
pub const GHOSTTY_SNAPSHOT_DECODER_DATA_SOURCE_OFFSET: GhosttySnapshotDecoderData = 2;
pub const GHOSTTY_SNAPSHOT_DECODER_OPT_MAX_CONTINUATION_BYTES: GhosttySnapshotDecoderOption = 0;
pub const GHOSTTY_SNAPSHOT_DECODER_OPT_MAX_VALUE: GhosttySnapshotDecoderOption = c_int::MAX;
pub const GHOSTTY_SNAPSHOT_DECODER_OPT_RETAIN_CONTINUATION: GhosttySnapshotDecoderOption = 1;
pub const GHOSTTY_STYLE_COLOR_NONE: GhosttyStyleColorTag = 0;
pub const GHOSTTY_STYLE_COLOR_PALETTE: GhosttyStyleColorTag = 1;
pub const GHOSTTY_STYLE_COLOR_RGB: GhosttyStyleColorTag = 2;
pub const GHOSTTY_STYLE_COLOR_TAG_MAX_VALUE: GhosttyStyleColorTag = c_int::MAX;
pub const GHOSTTY_SUCCESS: GhosttyResult = 0;
pub const GHOSTTY_SYS_LOG_LEVEL_DEBUG: GhosttySysLogLevel = 3;
pub const GHOSTTY_SYS_LOG_LEVEL_ERROR: GhosttySysLogLevel = 0;
pub const GHOSTTY_SYS_LOG_LEVEL_INFO: GhosttySysLogLevel = 2;
pub const GHOSTTY_SYS_LOG_LEVEL_MAX_VALUE: GhosttySysLogLevel = c_int::MAX;
pub const GHOSTTY_SYS_LOG_LEVEL_WARNING: GhosttySysLogLevel = 1;
pub const GHOSTTY_SYS_OPT_DECODE_PNG: GhosttySysOption = 1;
pub const GHOSTTY_SYS_OPT_LOG: GhosttySysOption = 2;
pub const GHOSTTY_SYS_OPT_MAX_VALUE: GhosttySysOption = c_int::MAX;
pub const GHOSTTY_SYS_OPT_RANDOM_SECURE: GhosttySysOption = 3;
pub const GHOSTTY_SYS_OPT_USERDATA: GhosttySysOption = 0;
pub const GHOSTTY_TERMINAL_COMPRESSION_MODE_FULL: GhosttyTerminalCompressionMode = 1;
pub const GHOSTTY_TERMINAL_COMPRESSION_MODE_INCREMENTAL: GhosttyTerminalCompressionMode = 0;
pub const GHOSTTY_TERMINAL_COMPRESSION_MODE_MAX_VALUE: GhosttyTerminalCompressionMode = c_int::MAX;
pub const GHOSTTY_TERMINAL_COMPRESSION_RESULT_COMPLETE: GhosttyTerminalCompressionResult = 2;
pub const GHOSTTY_TERMINAL_COMPRESSION_RESULT_MAX_VALUE: GhosttyTerminalCompressionResult = c_int::MAX;
pub const GHOSTTY_TERMINAL_COMPRESSION_RESULT_PENDING: GhosttyTerminalCompressionResult = 1;
pub const GHOSTTY_TERMINAL_COMPRESSION_RESULT_UNSUPPORTED: GhosttyTerminalCompressionResult = 0;
pub const GHOSTTY_TERMINAL_CURSOR_STYLE_BAR: GhosttyTerminalCursorStyle = 0;
pub const GHOSTTY_TERMINAL_CURSOR_STYLE_BLOCK: GhosttyTerminalCursorStyle = 1;
pub const GHOSTTY_TERMINAL_CURSOR_STYLE_BLOCK_HOLLOW: GhosttyTerminalCursorStyle = 3;
pub const GHOSTTY_TERMINAL_CURSOR_STYLE_MAX_VALUE: GhosttyTerminalCursorStyle = c_int::MAX;
pub const GHOSTTY_TERMINAL_CURSOR_STYLE_UNDERLINE: GhosttyTerminalCursorStyle = 2;
pub const GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN: GhosttyTerminalData = 6;
pub const GHOSTTY_TERMINAL_DATA_CLIPBOARD_WRITE_MAX_BYTES: GhosttyTerminalData = 40;
pub const GHOSTTY_TERMINAL_DATA_COLOR_BACKGROUND: GhosttyTerminalData = 19;
pub const GHOSTTY_TERMINAL_DATA_COLOR_BACKGROUND_DEFAULT: GhosttyTerminalData = 23;
pub const GHOSTTY_TERMINAL_DATA_COLOR_CURSOR: GhosttyTerminalData = 20;
pub const GHOSTTY_TERMINAL_DATA_COLOR_CURSOR_DEFAULT: GhosttyTerminalData = 24;
pub const GHOSTTY_TERMINAL_DATA_COLOR_FOREGROUND: GhosttyTerminalData = 18;
pub const GHOSTTY_TERMINAL_DATA_COLOR_FOREGROUND_DEFAULT: GhosttyTerminalData = 22;
pub const GHOSTTY_TERMINAL_DATA_COLOR_PALETTE: GhosttyTerminalData = 21;
pub const GHOSTTY_TERMINAL_DATA_COLOR_PALETTE_DEFAULT: GhosttyTerminalData = 25;
pub const GHOSTTY_TERMINAL_DATA_COLS: GhosttyTerminalData = 1;
pub const GHOSTTY_TERMINAL_DATA_CONTINUATION_MAX_BYTES: GhosttyTerminalData = 36;
pub const GHOSTTY_TERMINAL_DATA_CURSOR_AT_PROMPT: GhosttyTerminalData = 39;
pub const GHOSTTY_TERMINAL_DATA_CURSOR_PENDING_WRAP: GhosttyTerminalData = 5;
pub const GHOSTTY_TERMINAL_DATA_CURSOR_STYLE: GhosttyTerminalData = 10;
pub const GHOSTTY_TERMINAL_DATA_CURSOR_VISIBLE: GhosttyTerminalData = 7;
pub const GHOSTTY_TERMINAL_DATA_CURSOR_X: GhosttyTerminalData = 3;
pub const GHOSTTY_TERMINAL_DATA_CURSOR_Y: GhosttyTerminalData = 4;
pub const GHOSTTY_TERMINAL_DATA_HEIGHT_PX: GhosttyTerminalData = 17;
pub const GHOSTTY_TERMINAL_DATA_INVALID: GhosttyTerminalData = 0;
pub const GHOSTTY_TERMINAL_DATA_KITTY_GRAPHICS: GhosttyTerminalData = 30;
pub const GHOSTTY_TERMINAL_DATA_KITTY_IMAGE_MEDIUM_FILE: GhosttyTerminalData = 27;
pub const GHOSTTY_TERMINAL_DATA_KITTY_IMAGE_MEDIUM_SHARED_MEM: GhosttyTerminalData = 29;
pub const GHOSTTY_TERMINAL_DATA_KITTY_IMAGE_MEDIUM_TEMP_FILE: GhosttyTerminalData = 28;
pub const GHOSTTY_TERMINAL_DATA_KITTY_IMAGE_STORAGE_LIMIT: GhosttyTerminalData = 26;
pub const GHOSTTY_TERMINAL_DATA_KITTY_KEYBOARD_FLAGS: GhosttyTerminalData = 8;
pub const GHOSTTY_TERMINAL_DATA_MAX_VALUE: GhosttyTerminalData = c_int::MAX;
pub const GHOSTTY_TERMINAL_DATA_MODE: GhosttyTerminalData = 37;
pub const GHOSTTY_TERMINAL_DATA_MOUSE_TRACKING: GhosttyTerminalData = 11;
pub const GHOSTTY_TERMINAL_DATA_PWD: GhosttyTerminalData = 13;
pub const GHOSTTY_TERMINAL_DATA_ROWS: GhosttyTerminalData = 2;
pub const GHOSTTY_TERMINAL_DATA_SCROLLBACK_MAX_BYTES: GhosttyTerminalData = 34;
pub const GHOSTTY_TERMINAL_DATA_SCROLLBACK_MAX_LINES: GhosttyTerminalData = 35;
pub const GHOSTTY_TERMINAL_DATA_SCROLLBACK_ROWS: GhosttyTerminalData = 15;
pub const GHOSTTY_TERMINAL_DATA_SCROLLBAR: GhosttyTerminalData = 9;
pub const GHOSTTY_TERMINAL_DATA_SELECTION: GhosttyTerminalData = 31;
pub const GHOSTTY_TERMINAL_DATA_TITLE: GhosttyTerminalData = 12;
pub const GHOSTTY_TERMINAL_DATA_TOTAL_ROWS: GhosttyTerminalData = 14;
pub const GHOSTTY_TERMINAL_DATA_VIEWPORT_ACTIVE: GhosttyTerminalData = 32;
pub const GHOSTTY_TERMINAL_DATA_VT_GROUND: GhosttyTerminalData = 38;
pub const GHOSTTY_TERMINAL_DATA_VT_PROCESSING_ERROR: GhosttyTerminalData = 33;
pub const GHOSTTY_TERMINAL_DATA_WIDTH_PX: GhosttyTerminalData = 16;
pub const GHOSTTY_TERMINAL_OPT_APC_MAX_BYTES: GhosttyTerminalOption = 19;
pub const GHOSTTY_TERMINAL_OPT_APC_MAX_BYTES_KITTY: GhosttyTerminalOption = 20;
pub const GHOSTTY_TERMINAL_OPT_BELL: GhosttyTerminalOption = 2;
pub const GHOSTTY_TERMINAL_OPT_CLIPBOARD_READ: GhosttyTerminalOption = 38;
pub const GHOSTTY_TERMINAL_OPT_CLIPBOARD_WRITE: GhosttyTerminalOption = 26;
pub const GHOSTTY_TERMINAL_OPT_CLIPBOARD_WRITE_MAX_BYTES: GhosttyTerminalOption = 39;
pub const GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND: GhosttyTerminalOption = 12;
pub const GHOSTTY_TERMINAL_OPT_COLOR_CURSOR: GhosttyTerminalOption = 13;
pub const GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND: GhosttyTerminalOption = 11;
pub const GHOSTTY_TERMINAL_OPT_COLOR_PALETTE: GhosttyTerminalOption = 14;
pub const GHOSTTY_TERMINAL_OPT_COLOR_SCHEME: GhosttyTerminalOption = 7;
pub const GHOSTTY_TERMINAL_OPT_CONTINUATION_MAX_BYTES: GhosttyTerminalOption = 31;
pub const GHOSTTY_TERMINAL_OPT_DEFAULT_CURSOR_BLINK: GhosttyTerminalOption = 23;
pub const GHOSTTY_TERMINAL_OPT_DEFAULT_CURSOR_STYLE: GhosttyTerminalOption = 22;
pub const GHOSTTY_TERMINAL_OPT_DESKTOP_NOTIFICATION: GhosttyTerminalOption = 29;
pub const GHOSTTY_TERMINAL_OPT_DEVICE_ATTRIBUTES: GhosttyTerminalOption = 8;
pub const GHOSTTY_TERMINAL_OPT_ENQUIRY: GhosttyTerminalOption = 3;
pub const GHOSTTY_TERMINAL_OPT_GLYPH_PROTOCOL: GhosttyTerminalOption = 24;
pub const GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_MEDIUM_FILE: GhosttyTerminalOption = 16;
pub const GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_MEDIUM_SHARED_MEM: GhosttyTerminalOption = 18;
pub const GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_MEDIUM_TEMP_FILE: GhosttyTerminalOption = 17;
pub const GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_STORAGE_LIMIT: GhosttyTerminalOption = 15;
pub const GHOSTTY_TERMINAL_OPT_MAX_VALUE: GhosttyTerminalOption = c_int::MAX;
pub const GHOSTTY_TERMINAL_OPT_MODE: GhosttyTerminalOption = 34;
pub const GHOSTTY_TERMINAL_OPT_MODE_DEFAULT: GhosttyTerminalOption = 33;
pub const GHOSTTY_TERMINAL_OPT_PROGRESS_REPORT: GhosttyTerminalOption = 30;
pub const GHOSTTY_TERMINAL_OPT_PWD: GhosttyTerminalOption = 10;
pub const GHOSTTY_TERMINAL_OPT_PWD_CHANGED: GhosttyTerminalOption = 25;
pub const GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_BYTES: GhosttyTerminalOption = 27;
pub const GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_LINES: GhosttyTerminalOption = 28;
pub const GHOSTTY_TERMINAL_OPT_SELECTION: GhosttyTerminalOption = 21;
pub const GHOSTTY_TERMINAL_OPT_SIZE: GhosttyTerminalOption = 6;
pub const GHOSTTY_TERMINAL_OPT_TERMINFO_NAME: GhosttyTerminalOption = 37;
pub const GHOSTTY_TERMINAL_OPT_TITLE: GhosttyTerminalOption = 9;
pub const GHOSTTY_TERMINAL_OPT_TITLE_CHANGED: GhosttyTerminalOption = 5;
pub const GHOSTTY_TERMINAL_OPT_TITLE_REPORT: GhosttyTerminalOption = 32;
pub const GHOSTTY_TERMINAL_OPT_UNKNOWN_MAX_BYTES: GhosttyTerminalOption = 36;
pub const GHOSTTY_TERMINAL_OPT_UNKNOWN_SEQUENCE: GhosttyTerminalOption = 35;
pub const GHOSTTY_TERMINAL_OPT_USERDATA: GhosttyTerminalOption = 0;
pub const GHOSTTY_TERMINAL_OPT_WRITE_PTY: GhosttyTerminalOption = 1;
pub const GHOSTTY_TERMINAL_OPT_XTVERSION: GhosttyTerminalOption = 4;
pub const GHOSTTY_TERMINAL_PROGRESS_STATE_ERROR: GhosttyTerminalProgressState = 2;
pub const GHOSTTY_TERMINAL_PROGRESS_STATE_INDETERMINATE: GhosttyTerminalProgressState = 3;
pub const GHOSTTY_TERMINAL_PROGRESS_STATE_MAX_VALUE: GhosttyTerminalProgressState = c_int::MAX;
pub const GHOSTTY_TERMINAL_PROGRESS_STATE_PAUSE: GhosttyTerminalProgressState = 4;
pub const GHOSTTY_TERMINAL_PROGRESS_STATE_REMOVE: GhosttyTerminalProgressState = 0;
pub const GHOSTTY_TERMINAL_PROGRESS_STATE_SET: GhosttyTerminalProgressState = 1;
pub const GHOSTTY_TERMINAL_SCREEN_ALTERNATE: GhosttyTerminalScreen = 1;
pub const GHOSTTY_TERMINAL_SCREEN_MAX_VALUE: GhosttyTerminalScreen = c_int::MAX;
pub const GHOSTTY_TERMINAL_SCREEN_PRIMARY: GhosttyTerminalScreen = 0;
pub const GHOSTTY_TERMINAL_UNKNOWN_SEQUENCE_APC: GhosttyTerminalUnknownSequenceTag = 0;
pub const GHOSTTY_TERMINAL_UNKNOWN_SEQUENCE_MAX_VALUE: GhosttyTerminalUnknownSequenceTag = c_int::MAX;

// ---- Types -------------------------------------------------------------

/// C struct `GhosttyAllocator` from `include/ghostty/vt/allocator.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyAllocator {
    pub ctx: *mut c_void,
    pub vtable: *const GhosttyAllocatorVtable,
}
/// C struct `GhosttyAllocatorVtable` from `include/ghostty/vt/allocator.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyAllocatorVtable {
    pub alloc: Option<unsafe extern "C" fn(*mut c_void, usize, u8, usize) -> *mut c_void>,
    pub resize: Option<unsafe extern "C" fn(*mut c_void, *mut c_void, usize, u8, usize, usize) -> bool>,
    pub remap: Option<unsafe extern "C" fn(*mut c_void, *mut c_void, usize, u8, usize, usize) -> *mut c_void>,
    pub free: Option<unsafe extern "C" fn(*mut c_void, *mut c_void, usize, u8, usize)>,
}
/// C struct `GhosttyBuffer` from `include/ghostty/vt/types.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyBuffer {
    pub ptr: *mut u8,
    pub cap: usize,
    pub len: usize,
}
/// C enum `GhosttyBuildInfo` from `include/ghostty/vt/build_info.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyBuildInfo = c_int;
pub type GhosttyCell = u64;
/// C enum `GhosttyCellContentTag` from `include/ghostty/vt/screen.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyCellContentTag = c_int;
/// C enum `GhosttyCellData` from `include/ghostty/vt/screen.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyCellData = c_int;
/// C enum `GhosttyCellSemanticContent` from `include/ghostty/vt/screen.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyCellSemanticContent = c_int;
/// C enum `GhosttyCellWide` from `include/ghostty/vt/screen.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyCellWide = c_int;
/// C struct `GhosttyCellsView` from `include/ghostty/vt/screen.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyCellsView {
    pub ptr: *const GhosttyCell,
    pub len: usize,
}
/// C struct `GhosttyClipboardContent` from `include/ghostty/vt/terminal.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyClipboardContent {
    pub mime: GhosttyString,
    pub data: GhosttyString,
}
/// C enum `GhosttyClipboardLocation` from `include/ghostty/vt/terminal.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyClipboardLocation = c_int;
/// C struct `GhosttyClipboardRead` from `include/ghostty/vt/terminal.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyClipboardRead {
    pub size: usize,
    pub location: GhosttyClipboardLocation,
    pub mimes: *const GhosttyString,
    pub mimes_len: usize,
    pub list: bool,
    pub name: GhosttyString,
    pub granted: bool,
    pub can_remember: bool,
    pub ctx: *const c_void,
    pub reply: GhosttyClipboardReadReplyFn,
}
/// C struct `GhosttyClipboardReadReply` from `include/ghostty/vt/terminal.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyClipboardReadReply {
    pub size: usize,
    pub result: GhosttyClipboardReadResult,
    pub contents: *const GhosttyClipboardContent,
    pub contents_len: usize,
    pub available: *const GhosttyString,
    pub available_len: usize,
    pub remember: bool,
}
/// C enum `GhosttyClipboardReadResult` from `include/ghostty/vt/terminal.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyClipboardReadResult = c_int;
/// C struct `GhosttyClipboardWrite` from `include/ghostty/vt/terminal.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyClipboardWrite {
    pub size: usize,
    pub location: GhosttyClipboardLocation,
    pub contents: *const GhosttyClipboardContent,
    pub contents_len: usize,
    pub name: GhosttyString,
    pub granted: bool,
    pub can_remember: bool,
    pub ctx: *const c_void,
    pub reply: GhosttyClipboardWriteReplyFn,
}
/// C struct `GhosttyClipboardWriteReply` from `include/ghostty/vt/terminal.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyClipboardWriteReply {
    pub size: usize,
    pub result: GhosttyClipboardWriteResult,
    pub remember: bool,
}
/// C enum `GhosttyClipboardWriteResult` from `include/ghostty/vt/terminal.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyClipboardWriteResult = c_int;
/// C struct `GhosttyCodepoints` from `include/ghostty/vt/types.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyCodepoints {
    pub ptr: *const u32,
    pub len: usize,
}
pub type GhosttyColorPaletteIndex = u8;
/// C struct `GhosttyColorPaletteMask` from `include/ghostty/vt/color.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyColorPaletteMask {
    pub bits: [u64; 4],
}
/// C struct `GhosttyColorRgb` from `include/ghostty/vt/color.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyColorRgb {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}
/// C enum `GhosttyColorScheme` from `include/ghostty/vt/device.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyColorScheme = c_int;
/// C struct `GhosttyColorX11Entry` from `include/ghostty/vt/color.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyColorX11Entry {
    pub name: *const c_char,
    pub color: GhosttyColorRgb,
}
/// C struct `GhosttyDeviceAttributes` from `include/ghostty/vt/device.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyDeviceAttributes {
    pub primary: GhosttyDeviceAttributesPrimary,
    pub secondary: GhosttyDeviceAttributesSecondary,
    pub tertiary: GhosttyDeviceAttributesTertiary,
}
/// C struct `GhosttyDeviceAttributesPrimary` from `include/ghostty/vt/device.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyDeviceAttributesPrimary {
    pub conformance_level: u16,
    pub features: [u16; 64],
    pub num_features: usize,
}
/// C struct `GhosttyDeviceAttributesSecondary` from `include/ghostty/vt/device.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyDeviceAttributesSecondary {
    pub device_type: u16,
    pub firmware_version: u16,
    pub rom_cartridge: u16,
}
/// C struct `GhosttyDeviceAttributesTertiary` from `include/ghostty/vt/device.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyDeviceAttributesTertiary {
    pub unit_id: u32,
}
/// C enum `GhosttyFocusEvent` from `include/ghostty/vt/focus.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyFocusEvent = c_int;
pub type GhosttyFormatter = *mut GhosttyFormatterImpl;
/// C enum `GhosttyFormatterFormat` from `include/ghostty/vt/types.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyFormatterFormat = c_int;
/// Opaque C type backing the `GhosttyFormatter` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyFormatterImpl {
    _private: [u8; 0],
}
/// C struct `GhosttyFormatterScreenExtra` from `include/ghostty/vt/formatter.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyFormatterScreenExtra {
    pub size: usize,
    pub cursor: bool,
    pub style: bool,
    pub hyperlink: bool,
    pub protection: bool,
    pub kitty_keyboard: bool,
    pub charsets: bool,
}
/// C struct `GhosttyFormatterTerminalExtra` from `include/ghostty/vt/formatter.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyFormatterTerminalExtra {
    pub size: usize,
    pub palette: bool,
    pub modes: bool,
    pub scrolling_region: bool,
    pub tabstops: bool,
    pub pwd: bool,
    pub keyboard: bool,
    pub screen: GhosttyFormatterScreenExtra,
}
/// C struct `GhosttyFormatterTerminalOptions` from `include/ghostty/vt/formatter.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyFormatterTerminalOptions {
    pub size: usize,
    pub emit: GhosttyFormatterFormat,
    pub unwrap: bool,
    pub trim: bool,
    pub extra: GhosttyFormatterTerminalExtra,
    pub selection: *const GhosttySelection,
}
/// C struct `GhosttyGridRef` from `include/ghostty/vt/grid_ref.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyGridRef {
    pub size: usize,
    pub node: *mut c_void,
    pub x: u16,
    pub y: u16,
}
/// C enum `GhosttyKey` from `include/ghostty/vt/key/event.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyKey = c_int;
/// C enum `GhosttyKeyAction` from `include/ghostty/vt/key/event.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyKeyAction = c_int;
pub type GhosttyKeyEncoder = *mut GhosttyKeyEncoderImpl;
/// Opaque C type backing the `GhosttyKeyEncoder` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyKeyEncoderImpl {
    _private: [u8; 0],
}
/// C enum `GhosttyKeyEncoderOption` from `include/ghostty/vt/key/encoder.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyKeyEncoderOption = c_int;
pub type GhosttyKeyEvent = *mut GhosttyKeyEventImpl;
/// Opaque C type backing the `GhosttyKeyEvent` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyKeyEventImpl {
    _private: [u8; 0],
}
pub type GhosttyKittyGraphics = *mut GhosttyKittyGraphicsImpl;
/// C enum `GhosttyKittyGraphicsData` from `include/ghostty/vt/kitty_graphics.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyKittyGraphicsData = c_int;
pub type GhosttyKittyGraphicsImage = *const GhosttyKittyGraphicsImageImpl;
/// C enum `GhosttyKittyGraphicsImageData` from `include/ghostty/vt/kitty_graphics.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyKittyGraphicsImageData = c_int;
/// Opaque C type backing the `GhosttyKittyGraphicsImage` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyKittyGraphicsImageImpl {
    _private: [u8; 0],
}
/// Opaque C type backing the `GhosttyKittyGraphics` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyKittyGraphicsImpl {
    _private: [u8; 0],
}
/// C enum `GhosttyKittyGraphicsPlacementData` from `include/ghostty/vt/kitty_graphics.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyKittyGraphicsPlacementData = c_int;
pub type GhosttyKittyGraphicsPlacementIterator = *mut GhosttyKittyGraphicsPlacementIteratorImpl;
/// Opaque C type backing the `GhosttyKittyGraphicsPlacementIterator` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyKittyGraphicsPlacementIteratorImpl {
    _private: [u8; 0],
}
/// C enum `GhosttyKittyGraphicsPlacementIteratorOption` from `include/ghostty/vt/kitty_graphics.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyKittyGraphicsPlacementIteratorOption = c_int;
/// C struct `GhosttyKittyGraphicsPlacementRenderInfo` from `include/ghostty/vt/kitty_graphics.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyKittyGraphicsPlacementRenderInfo {
    pub size: usize,
    pub pixel_width: u32,
    pub pixel_height: u32,
    pub grid_cols: u32,
    pub grid_rows: u32,
    pub viewport_col: i32,
    pub viewport_row: i32,
    pub viewport_visible: bool,
    pub source_x: u32,
    pub source_y: u32,
    pub source_width: u32,
    pub source_height: u32,
}
/// C enum `GhosttyKittyImageCompression` from `include/ghostty/vt/kitty_graphics.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyKittyImageCompression = c_int;
/// C enum `GhosttyKittyImageFormat` from `include/ghostty/vt/kitty_graphics.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyKittyImageFormat = c_int;
pub type GhosttyKittyKeyFlags = u8;
/// C enum `GhosttyKittyPlacementLayer` from `include/ghostty/vt/kitty_graphics.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyKittyPlacementLayer = c_int;
/// C struct `GhosttyMimeReader` from `include/ghostty/vt/io.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyMimeReader {
    pub read: GhosttyMimeReaderFn,
    pub userdata: *mut c_void,
}
pub type GhosttyMode = u16;
/// C enum `GhosttyModeReportState` from `include/ghostty/vt/modes.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyModeReportState = c_int;
pub type GhosttyMods = u16;
/// C enum `GhosttyMouseAction` from `include/ghostty/vt/mouse/event.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyMouseAction = c_int;
/// C enum `GhosttyMouseButton` from `include/ghostty/vt/mouse/event.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyMouseButton = c_int;
pub type GhosttyMouseEncoder = *mut GhosttyMouseEncoderImpl;
/// Opaque C type backing the `GhosttyMouseEncoder` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyMouseEncoderImpl {
    _private: [u8; 0],
}
/// C enum `GhosttyMouseEncoderOption` from `include/ghostty/vt/mouse/encoder.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyMouseEncoderOption = c_int;
/// C struct `GhosttyMouseEncoderSize` from `include/ghostty/vt/mouse/encoder.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyMouseEncoderSize {
    pub size: usize,
    pub screen_width: u32,
    pub screen_height: u32,
    pub cell_width: u32,
    pub cell_height: u32,
    pub padding_top: u32,
    pub padding_bottom: u32,
    pub padding_right: u32,
    pub padding_left: u32,
}
pub type GhosttyMouseEvent = *mut GhosttyMouseEventImpl;
/// Opaque C type backing the `GhosttyMouseEvent` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyMouseEventImpl {
    _private: [u8; 0],
}
/// C enum `GhosttyMouseFormat` from `include/ghostty/vt/mouse/encoder.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyMouseFormat = c_int;
/// C struct `GhosttyMousePosition` from `include/ghostty/vt/mouse/event.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyMousePosition {
    pub x: f32,
    pub y: f32,
}
/// C enum `GhosttyMouseTrackingMode` from `include/ghostty/vt/mouse/encoder.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyMouseTrackingMode = c_int;
/// C enum `GhosttyOptimizeMode` from `include/ghostty/vt/build_info.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyOptimizeMode = c_int;
/// C enum `GhosttyOptionAsAlt` from `include/ghostty/vt/key/encoder.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyOptionAsAlt = c_int;
pub type GhosttyOscCommand = *mut GhosttyOscCommandImpl;
/// C enum `GhosttyOscCommandData` from `include/ghostty/vt/osc.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyOscCommandData = c_int;
/// Opaque C type backing the `GhosttyOscCommand` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyOscCommandImpl {
    _private: [u8; 0],
}
/// C enum `GhosttyOscCommandType` from `include/ghostty/vt/osc.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyOscCommandType = c_int;
pub type GhosttyOscParser = *mut GhosttyOscParserImpl;
/// Opaque C type backing the `GhosttyOscParser` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyOscParserImpl {
    _private: [u8; 0],
}
/// C struct `GhosttyPaste` from `include/ghostty/vt/paste.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyPaste {
    pub size: usize,
    pub location: GhosttyClipboardLocation,
    pub source: GhosttyPasteSource,
    pub mimes: *const GhosttyString,
    pub mimes_len: usize,
    pub reader: GhosttyMimeReader,
    pub allow_unsafe: bool,
}
/// C enum `GhosttyPasteSource` from `include/ghostty/vt/paste.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyPasteSource = c_int;
/// C struct `GhosttyPoint` from `include/ghostty/vt/point.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyPoint {
    pub tag: GhosttyPointTag,
    pub value: GhosttyPointValue,
}
/// C struct `GhosttyPointCoordinate` from `include/ghostty/vt/point.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyPointCoordinate {
    pub x: u16,
    pub y: u32,
}
/// C enum `GhosttyPointTag` from `include/ghostty/vt/point.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyPointTag = c_int;
/// C union `GhosttyPointValue` from `include/ghostty/vt/point.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub union GhosttyPointValue {
    pub coordinate: GhosttyPointCoordinate,
    pub _padding: [u64; 2],
}
/// C struct `GhosttyReader` from `include/ghostty/vt/io.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyReader {
    pub read: GhosttyReaderFn,
    pub userdata: *mut c_void,
}
pub type GhosttyRenderState = *mut GhosttyRenderStateImpl;
/// C struct `GhosttyRenderStateColors` from `include/ghostty/vt/render.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyRenderStateColors {
    pub size: usize,
    pub background: GhosttyColorRgb,
    pub foreground: GhosttyColorRgb,
    pub cursor: GhosttyColorRgb,
    pub cursor_has_value: bool,
    pub palette: [GhosttyColorRgb; 256],
}
/// C struct `GhosttyRenderStateCursor` from `include/ghostty/vt/render.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyRenderStateCursor {
    pub size: usize,
    pub viewport_has_value: bool,
    pub viewport_x: u16,
    pub viewport_y: u16,
    pub wide_tail: bool,
    pub visible: bool,
    pub blinking: bool,
    pub password_input: bool,
    pub visual_style: GhosttyRenderStateCursorVisualStyle,
}
/// C enum `GhosttyRenderStateCursorVisualStyle` from `include/ghostty/vt/render.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyRenderStateCursorVisualStyle = c_int;
/// C enum `GhosttyRenderStateData` from `include/ghostty/vt/render.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyRenderStateData = c_int;
/// C enum `GhosttyRenderStateDirty` from `include/ghostty/vt/render.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyRenderStateDirty = c_int;
/// Opaque C type backing the `GhosttyRenderState` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyRenderStateImpl {
    _private: [u8; 0],
}
/// C enum `GhosttyRenderStateOption` from `include/ghostty/vt/render.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyRenderStateOption = c_int;
pub type GhosttyRenderStateRowCells = *mut GhosttyRenderStateRowCellsImpl;
/// C enum `GhosttyRenderStateRowCellsData` from `include/ghostty/vt/render.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyRenderStateRowCellsData = c_int;
/// Opaque C type backing the `GhosttyRenderStateRowCells` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyRenderStateRowCellsImpl {
    _private: [u8; 0],
}
/// C enum `GhosttyRenderStateRowData` from `include/ghostty/vt/render.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyRenderStateRowData = c_int;
pub type GhosttyRenderStateRowIterator = *mut GhosttyRenderStateRowIteratorImpl;
/// Opaque C type backing the `GhosttyRenderStateRowIterator` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyRenderStateRowIteratorImpl {
    _private: [u8; 0],
}
/// C enum `GhosttyRenderStateRowOption` from `include/ghostty/vt/render.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyRenderStateRowOption = c_int;
/// C struct `GhosttyRenderStateRowSelection` from `include/ghostty/vt/render.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyRenderStateRowSelection {
    pub size: usize,
    pub start_x: u16,
    pub end_x: u16,
}
/// C enum `GhosttyResult` from `include/ghostty/vt/types.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyResult = c_int;
pub type GhosttyRow = u64;
/// C enum `GhosttyRowData` from `include/ghostty/vt/screen.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyRowData = c_int;
/// C enum `GhosttyRowSemanticPrompt` from `include/ghostty/vt/screen.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyRowSemanticPrompt = c_int;
pub type GhosttySearch = *mut GhosttySearchImpl;
/// C enum `GhosttySearchData` from `include/ghostty/vt/search.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttySearchData = c_int;
/// Opaque C type backing the `GhosttySearch` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttySearchImpl {
    _private: [u8; 0],
}
/// C enum `GhosttySearchOption` from `include/ghostty/vt/search.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttySearchOption = c_int;
/// C enum `GhosttySearchScroll` from `include/ghostty/vt/search.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttySearchScroll = c_int;
/// C enum `GhosttySearchStatus` from `include/ghostty/vt/search.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttySearchStatus = c_int;
/// C struct `GhosttySelection` from `include/ghostty/vt/selection.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttySelection {
    pub size: usize,
    pub start: GhosttyGridRef,
    pub end: GhosttyGridRef,
    pub rectangle: bool,
}
/// C enum `GhosttySelectionAdjust` from `include/ghostty/vt/selection.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttySelectionAdjust = c_int;
/// C struct `GhosttySelectionBuffer` from `include/ghostty/vt/selection.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttySelectionBuffer {
    pub ptr: *mut GhosttySelection,
    pub cap: usize,
    pub len: usize,
}
pub type GhosttySelectionGesture = *mut GhosttySelectionGestureImpl;
/// C enum `GhosttySelectionGestureAutoscroll` from `include/ghostty/vt/selection.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttySelectionGestureAutoscroll = c_int;
/// C enum `GhosttySelectionGestureBehavior` from `include/ghostty/vt/selection.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttySelectionGestureBehavior = c_int;
/// C struct `GhosttySelectionGestureBehaviors` from `include/ghostty/vt/selection.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttySelectionGestureBehaviors {
    pub single_click: GhosttySelectionGestureBehavior,
    pub double_click: GhosttySelectionGestureBehavior,
    pub triple_click: GhosttySelectionGestureBehavior,
}
/// C enum `GhosttySelectionGestureData` from `include/ghostty/vt/selection.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttySelectionGestureData = c_int;
pub type GhosttySelectionGestureEvent = *mut GhosttySelectionGestureEventImpl;
/// Opaque C type backing the `GhosttySelectionGestureEvent` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttySelectionGestureEventImpl {
    _private: [u8; 0],
}
/// C enum `GhosttySelectionGestureEventOption` from `include/ghostty/vt/selection.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttySelectionGestureEventOption = c_int;
/// C enum `GhosttySelectionGestureEventType` from `include/ghostty/vt/selection.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttySelectionGestureEventType = c_int;
/// C struct `GhosttySelectionGestureGeometry` from `include/ghostty/vt/selection.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttySelectionGestureGeometry {
    pub columns: u32,
    pub cell_width: u32,
    pub padding_left: u32,
    pub screen_height: u32,
}
/// Opaque C type backing the `GhosttySelectionGesture` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttySelectionGestureImpl {
    _private: [u8; 0],
}
/// C enum `GhosttySelectionOrder` from `include/ghostty/vt/selection.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttySelectionOrder = c_int;
/// C struct `GhosttySgrAttribute` from `include/ghostty/vt/sgr.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttySgrAttribute {
    pub tag: GhosttySgrAttributeTag,
    pub value: GhosttySgrAttributeValue,
}
/// C enum `GhosttySgrAttributeTag` from `include/ghostty/vt/sgr.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttySgrAttributeTag = c_int;
/// C union `GhosttySgrAttributeValue` from `include/ghostty/vt/sgr.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub union GhosttySgrAttributeValue {
    pub unknown: GhosttySgrUnknown,
    pub underline: GhosttySgrUnderline,
    pub underline_color: GhosttyColorRgb,
    pub underline_color_256: GhosttyColorPaletteIndex,
    pub direct_color_fg: GhosttyColorRgb,
    pub direct_color_bg: GhosttyColorRgb,
    pub bg_8: GhosttyColorPaletteIndex,
    pub fg_8: GhosttyColorPaletteIndex,
    pub bright_bg_8: GhosttyColorPaletteIndex,
    pub bright_fg_8: GhosttyColorPaletteIndex,
    pub bg_256: GhosttyColorPaletteIndex,
    pub fg_256: GhosttyColorPaletteIndex,
    pub _padding: [u64; 8],
}
pub type GhosttySgrParser = *mut GhosttySgrParserImpl;
/// Opaque C type backing the `GhosttySgrParser` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttySgrParserImpl {
    _private: [u8; 0],
}
/// C enum `GhosttySgrUnderline` from `include/ghostty/vt/sgr.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttySgrUnderline = c_int;
/// C struct `GhosttySgrUnknown` from `include/ghostty/vt/sgr.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttySgrUnknown {
    pub full_ptr: *const u16,
    pub full_len: usize,
    pub partial_ptr: *const u16,
    pub partial_len: usize,
}
/// C struct `GhosttySizeReportSize` from `include/ghostty/vt/size_report.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttySizeReportSize {
    pub rows: u16,
    pub columns: u16,
    pub cell_width: u32,
    pub cell_height: u32,
}
/// C enum `GhosttySizeReportStyle` from `include/ghostty/vt/size_report.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttySizeReportStyle = c_int;
pub type GhosttySnapshotDecoder = *mut GhosttySnapshotDecoderImpl;
/// C enum `GhosttySnapshotDecoderData` from `include/ghostty/vt/snapshot.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttySnapshotDecoderData = c_int;
/// Opaque C type backing the `GhosttySnapshotDecoder` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttySnapshotDecoderImpl {
    _private: [u8; 0],
}
/// C enum `GhosttySnapshotDecoderOption` from `include/ghostty/vt/snapshot.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttySnapshotDecoderOption = c_int;
/// C struct `GhosttyString` from `include/ghostty/vt/types.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyString {
    pub ptr: *const u8,
    pub len: usize,
}
/// C struct `GhosttyStyle` from `include/ghostty/vt/style.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyStyle {
    pub size: usize,
    pub fg_color: GhosttyStyleColor,
    pub bg_color: GhosttyStyleColor,
    pub underline_color: GhosttyStyleColor,
    pub bold: bool,
    pub italic: bool,
    pub faint: bool,
    pub blink: bool,
    pub inverse: bool,
    pub invisible: bool,
    pub strikethrough: bool,
    pub overline: bool,
    pub underline: c_int,
}
/// C struct `GhosttyStyleColor` from `include/ghostty/vt/style.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyStyleColor {
    pub tag: GhosttyStyleColorTag,
    pub value: GhosttyStyleColorValue,
}
/// C enum `GhosttyStyleColorTag` from `include/ghostty/vt/style.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyStyleColorTag = c_int;
/// C union `GhosttyStyleColorValue` from `include/ghostty/vt/style.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub union GhosttyStyleColorValue {
    pub palette: GhosttyColorPaletteIndex,
    pub rgb: GhosttyColorRgb,
    pub _padding: u64,
}
pub type GhosttyStyleId = u16;
/// C struct `GhosttySurfacePosition` from `include/ghostty/vt/types.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttySurfacePosition {
    pub x: f64,
    pub y: f64,
}
/// C struct `GhosttySysImage` from `include/ghostty/vt/sys.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttySysImage {
    pub width: u32,
    pub height: u32,
    pub data: *mut u8,
    pub data_len: usize,
}
/// C enum `GhosttySysLogLevel` from `include/ghostty/vt/sys.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttySysLogLevel = c_int;
/// C enum `GhosttySysOption` from `include/ghostty/vt/sys.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttySysOption = c_int;
pub type GhosttyTerminal = *mut GhosttyTerminalImpl;
/// C enum `GhosttyTerminalCompressionMode` from `include/ghostty/vt/terminal.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyTerminalCompressionMode = c_int;
/// C enum `GhosttyTerminalCompressionResult` from `include/ghostty/vt/terminal.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyTerminalCompressionResult = c_int;
/// C enum `GhosttyTerminalCursorStyle` from `include/ghostty/vt/terminal.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyTerminalCursorStyle = c_int;
/// C enum `GhosttyTerminalData` from `include/ghostty/vt/terminal.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyTerminalData = c_int;
/// C struct `GhosttyTerminalDesktopNotification` from `include/ghostty/vt/terminal.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyTerminalDesktopNotification {
    pub size: usize,
    pub title: GhosttyString,
    pub body: GhosttyString,
}
/// Opaque C type backing the `GhosttyTerminal` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyTerminalImpl {
    _private: [u8; 0],
}
/// C struct `GhosttyTerminalModeConfig` from `include/ghostty/vt/terminal.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyTerminalModeConfig {
    pub mode: GhosttyMode,
    pub value: bool,
}
/// C enum `GhosttyTerminalOption` from `include/ghostty/vt/terminal.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyTerminalOption = c_int;
/// C struct `GhosttyTerminalProgressReport` from `include/ghostty/vt/terminal.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyTerminalProgressReport {
    pub size: usize,
    pub state: GhosttyTerminalProgressState,
    pub progress: i8,
}
/// C enum `GhosttyTerminalProgressState` from `include/ghostty/vt/terminal.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyTerminalProgressState = c_int;
/// C enum `GhosttyTerminalScreen` from `include/ghostty/vt/terminal.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyTerminalScreen = c_int;
/// C struct `GhosttyTerminalScrollViewport` from `include/ghostty/vt/terminal.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyTerminalScrollViewport {
    pub tag: GhosttyTerminalScrollViewportTag,
    pub value: GhosttyTerminalScrollViewportValue,
}
/// C enum `GhosttyTerminalScrollViewportTag` from `include/ghostty/vt/terminal.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyTerminalScrollViewportTag = c_int;
/// C union `GhosttyTerminalScrollViewportValue` from `include/ghostty/vt/terminal.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub union GhosttyTerminalScrollViewportValue {
    pub delta: isize,
    pub row: usize,
    pub _padding: [u64; 2],
}
/// C struct `GhosttyTerminalScrollbar` from `include/ghostty/vt/terminal.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyTerminalScrollbar {
    pub total: u64,
    pub offset: u64,
    pub len: u64,
}
/// C struct `GhosttyTerminalSelectLineOptions` from `include/ghostty/vt/selection.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyTerminalSelectLineOptions {
    pub size: usize,
    pub r#ref: GhosttyGridRef,
    pub whitespace: *const u32,
    pub whitespace_len: usize,
    pub semantic_prompt_boundary: bool,
}
/// C struct `GhosttyTerminalSelectWordBetweenOptions` from `include/ghostty/vt/selection.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyTerminalSelectWordBetweenOptions {
    pub size: usize,
    pub start: GhosttyGridRef,
    pub end: GhosttyGridRef,
    pub boundary_codepoints: *const u32,
    pub boundary_codepoints_len: usize,
}
/// C struct `GhosttyTerminalSelectWordOptions` from `include/ghostty/vt/selection.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyTerminalSelectWordOptions {
    pub size: usize,
    pub r#ref: GhosttyGridRef,
    pub boundary_codepoints: *const u32,
    pub boundary_codepoints_len: usize,
}
/// C struct `GhosttyTerminalSelectionFormatOptions` from `include/ghostty/vt/selection.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyTerminalSelectionFormatOptions {
    pub size: usize,
    pub emit: GhosttyFormatterFormat,
    pub unwrap: bool,
    pub trim: bool,
    pub selection: *const GhosttySelection,
}
/// C struct `GhosttyTerminalUnknownSequence` from `include/ghostty/vt/terminal.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyTerminalUnknownSequence {
    pub tag: GhosttyTerminalUnknownSequenceTag,
    pub value: GhosttyTerminalUnknownSequenceValue,
}
/// C enum `GhosttyTerminalUnknownSequenceTag` from `include/ghostty/vt/terminal.h` (int-backed, per the libghostty-vt ABI).
pub type GhosttyTerminalUnknownSequenceTag = c_int;
/// C union `GhosttyTerminalUnknownSequenceValue` from `include/ghostty/vt/terminal.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub union GhosttyTerminalUnknownSequenceValue {
    pub apc: GhosttyTerminalUnknownStringSequence,
    pub _padding: [u64; 16],
}
/// C struct `GhosttyTerminalUnknownStringSequence` from `include/ghostty/vt/terminal.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyTerminalUnknownStringSequence {
    pub truncated: bool,
    pub content: GhosttyString,
}
pub type GhosttyTrackedGridRef = *mut GhosttyTrackedGridRefImpl;
/// Opaque C type backing the `GhosttyTrackedGridRef` handle.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyTrackedGridRefImpl {
    _private: [u8; 0],
}
/// C struct `GhosttyWriter` from `include/ghostty/vt/io.h`.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct GhosttyWriter {
    pub write: GhosttyWriterFn,
    pub userdata: *mut c_void,
}

// ---- Callback types ----------------------------------------------------

pub type GhosttyClipboardReadReplyFn = Option<unsafe extern "C" fn(*const GhosttyClipboardRead, *const GhosttyClipboardReadReply)>;
pub type GhosttyClipboardWriteReplyFn = Option<unsafe extern "C" fn(*const GhosttyClipboardWrite, *const GhosttyClipboardWriteReply)>;
pub type GhosttyMimeReaderFn = Option<unsafe extern "C" fn(*mut c_void, GhosttyString, GhosttyWriter) -> bool>;
pub type GhosttyReaderFn = Option<unsafe extern "C" fn(*mut c_void, *mut u8, usize, *mut usize) -> bool>;
pub type GhosttySysDecodePngFn = Option<unsafe extern "C" fn(*mut c_void, *const GhosttyAllocator, *const u8, usize, *mut GhosttySysImage) -> bool>;
pub type GhosttySysLogFn = Option<unsafe extern "C" fn(*mut c_void, GhosttySysLogLevel, *const u8, usize, *const u8, usize)>;
pub type GhosttySysRandomSecureFn = Option<unsafe extern "C" fn(*mut c_void, *mut u8, usize) -> bool>;
pub type GhosttyTerminalBellFn = Option<unsafe extern "C" fn(GhosttyTerminal, *mut c_void)>;
pub type GhosttyTerminalClipboardReadFn = Option<unsafe extern "C" fn(GhosttyTerminal, *mut c_void, *const GhosttyClipboardRead)>;
pub type GhosttyTerminalClipboardWriteFn = Option<unsafe extern "C" fn(GhosttyTerminal, *mut c_void, *const GhosttyClipboardWrite)>;
pub type GhosttyTerminalColorSchemeFn = Option<unsafe extern "C" fn(GhosttyTerminal, *mut c_void, *mut GhosttyColorScheme) -> bool>;
pub type GhosttyTerminalDesktopNotificationFn = Option<unsafe extern "C" fn(GhosttyTerminal, *mut c_void, *const GhosttyTerminalDesktopNotification)>;
pub type GhosttyTerminalDeviceAttributesFn = Option<unsafe extern "C" fn(GhosttyTerminal, *mut c_void, *mut GhosttyDeviceAttributes) -> bool>;
pub type GhosttyTerminalEnquiryFn = Option<unsafe extern "C" fn(GhosttyTerminal, *mut c_void) -> GhosttyString>;
pub type GhosttyTerminalProgressReportFn = Option<unsafe extern "C" fn(GhosttyTerminal, *mut c_void, *const GhosttyTerminalProgressReport)>;
pub type GhosttyTerminalPwdChangedFn = Option<unsafe extern "C" fn(GhosttyTerminal, *mut c_void)>;
pub type GhosttyTerminalSizeFn = Option<unsafe extern "C" fn(GhosttyTerminal, *mut c_void, *mut GhosttySizeReportSize) -> bool>;
pub type GhosttyTerminalTitleChangedFn = Option<unsafe extern "C" fn(GhosttyTerminal, *mut c_void)>;
pub type GhosttyTerminalUnknownSequenceFn = Option<unsafe extern "C" fn(GhosttyTerminal, *mut c_void, *const GhosttyTerminalUnknownSequence)>;
pub type GhosttyTerminalWritePtyFn = Option<unsafe extern "C" fn(GhosttyTerminal, *mut c_void, *const u8, usize)>;
pub type GhosttyTerminalXtversionFn = Option<unsafe extern "C" fn(GhosttyTerminal, *mut c_void) -> GhosttyString>;
pub type GhosttyWriterFn = Option<unsafe extern "C" fn(*mut c_void, *const u8, usize) -> bool>;

// ---- Exported functions ------------------------------------------------

extern "C" {
    pub fn ghostty_alloc(allocator: *const GhosttyAllocator, len: usize) -> *mut u8;
    pub fn ghostty_build_info(data: GhosttyBuildInfo, out: *mut c_void) -> GhosttyResult;
    pub fn ghostty_cell_get(cell: GhosttyCell, data: GhosttyCellData, out: *mut c_void) -> GhosttyResult;
    pub fn ghostty_cell_get_multi(cell: GhosttyCell, count: usize, keys: *const GhosttyCellData, values: *mut *mut c_void, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_color_contrast(a: *const GhosttyColorRgb, b: *const GhosttyColorRgb) -> f64;
    pub fn ghostty_color_luminance(color: *const GhosttyColorRgb) -> f64;
    pub fn ghostty_color_palette_default(out: *mut GhosttyColorRgb);
    pub fn ghostty_color_palette_generate(base: *const GhosttyColorRgb, skip: *const GhosttyColorPaletteMask, bg: *const GhosttyColorRgb, fg: *const GhosttyColorRgb, harmonious: bool, out: *mut GhosttyColorRgb);
    pub fn ghostty_color_parse(value: *const c_char, len: usize, out: *mut GhosttyColorRgb) -> GhosttyResult;
    pub fn ghostty_color_parse_palette_entry(value: *const c_char, len: usize, out_index: *mut u8, out_rgb: *mut GhosttyColorRgb) -> GhosttyResult;
    pub fn ghostty_color_parse_x11(name: *const c_char, len: usize, out: *mut GhosttyColorRgb) -> GhosttyResult;
    pub fn ghostty_color_perceived_luminance(color: *const GhosttyColorRgb) -> f64;
    pub fn ghostty_color_rgb_get(color: *const GhosttyColorRgb, r: *mut u8, g: *mut u8, b: *mut u8);
    pub fn ghostty_color_scheme_report_encode(scheme: GhosttyColorScheme, buf: *mut c_char, buf_len: usize, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_color_x11_name_count() -> usize;
    pub fn ghostty_color_x11_names() -> *const GhosttyColorX11Entry;
    pub fn ghostty_focus_encode(event: GhosttyFocusEvent, buf: *mut c_char, buf_len: usize, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_formatter_format(formatter: GhosttyFormatter, writer: GhosttyWriter) -> GhosttyResult;
    pub fn ghostty_formatter_format_alloc(formatter: GhosttyFormatter, allocator: *const GhosttyAllocator, out_ptr: *mut *mut u8, out_len: *mut usize) -> GhosttyResult;
    pub fn ghostty_formatter_format_buf(formatter: GhosttyFormatter, buf: *mut u8, buf_len: usize, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_formatter_free(formatter: GhosttyFormatter);
    pub fn ghostty_formatter_terminal_new(allocator: *const GhosttyAllocator, formatter: *mut GhosttyFormatter, terminal: GhosttyTerminal, options: GhosttyFormatterTerminalOptions) -> GhosttyResult;
    pub fn ghostty_free(allocator: *const GhosttyAllocator, ptr: *mut u8, len: usize);
    pub fn ghostty_grid_ref_cell(r#ref: *const GhosttyGridRef, out_cell: *mut GhosttyCell) -> GhosttyResult;
    pub fn ghostty_grid_ref_graphemes(r#ref: *const GhosttyGridRef, buf: *mut u32, buf_len: usize, out_len: *mut usize) -> GhosttyResult;
    pub fn ghostty_grid_ref_hyperlink_uri(r#ref: *const GhosttyGridRef, buf: *mut u8, buf_len: usize, out_len: *mut usize) -> GhosttyResult;
    pub fn ghostty_grid_ref_row(r#ref: *const GhosttyGridRef, out_row: *mut GhosttyRow) -> GhosttyResult;
    pub fn ghostty_grid_ref_style(r#ref: *const GhosttyGridRef, out_style: *mut GhosttyStyle) -> GhosttyResult;
    pub fn ghostty_key_encoder_encode(encoder: GhosttyKeyEncoder, event: GhosttyKeyEvent, out_buf: *mut c_char, out_buf_size: usize, out_len: *mut usize) -> GhosttyResult;
    pub fn ghostty_key_encoder_free(encoder: GhosttyKeyEncoder);
    pub fn ghostty_key_encoder_new(allocator: *const GhosttyAllocator, encoder: *mut GhosttyKeyEncoder) -> GhosttyResult;
    pub fn ghostty_key_encoder_setopt(encoder: GhosttyKeyEncoder, option: GhosttyKeyEncoderOption, value: *const c_void);
    pub fn ghostty_key_encoder_setopt_from_terminal(encoder: GhosttyKeyEncoder, terminal: GhosttyTerminal);
    pub fn ghostty_key_event_free(event: GhosttyKeyEvent);
    pub fn ghostty_key_event_get_action(event: GhosttyKeyEvent) -> GhosttyKeyAction;
    pub fn ghostty_key_event_get_composing(event: GhosttyKeyEvent) -> bool;
    pub fn ghostty_key_event_get_consumed_mods(event: GhosttyKeyEvent) -> GhosttyMods;
    pub fn ghostty_key_event_get_key(event: GhosttyKeyEvent) -> GhosttyKey;
    pub fn ghostty_key_event_get_mods(event: GhosttyKeyEvent) -> GhosttyMods;
    pub fn ghostty_key_event_get_unshifted_codepoint(event: GhosttyKeyEvent) -> u32;
    pub fn ghostty_key_event_get_utf8(event: GhosttyKeyEvent, len: *mut usize) -> *const c_char;
    pub fn ghostty_key_event_new(allocator: *const GhosttyAllocator, event: *mut GhosttyKeyEvent) -> GhosttyResult;
    pub fn ghostty_key_event_set_action(event: GhosttyKeyEvent, action: GhosttyKeyAction);
    pub fn ghostty_key_event_set_composing(event: GhosttyKeyEvent, composing: bool);
    pub fn ghostty_key_event_set_consumed_mods(event: GhosttyKeyEvent, consumed_mods: GhosttyMods);
    pub fn ghostty_key_event_set_key(event: GhosttyKeyEvent, key: GhosttyKey);
    pub fn ghostty_key_event_set_mods(event: GhosttyKeyEvent, mods: GhosttyMods);
    pub fn ghostty_key_event_set_unshifted_codepoint(event: GhosttyKeyEvent, codepoint: u32);
    pub fn ghostty_key_event_set_utf8(event: GhosttyKeyEvent, utf8: *const c_char, len: usize);
    pub fn ghostty_kitty_graphics_get(graphics: GhosttyKittyGraphics, data: GhosttyKittyGraphicsData, out: *mut c_void) -> GhosttyResult;
    pub fn ghostty_kitty_graphics_image(graphics: GhosttyKittyGraphics, image_id: u32) -> GhosttyKittyGraphicsImage;
    pub fn ghostty_kitty_graphics_image_get(image: GhosttyKittyGraphicsImage, data: GhosttyKittyGraphicsImageData, out: *mut c_void) -> GhosttyResult;
    pub fn ghostty_kitty_graphics_image_get_multi(image: GhosttyKittyGraphicsImage, count: usize, keys: *const GhosttyKittyGraphicsImageData, values: *mut *mut c_void, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_kitty_graphics_placement_get(iterator: GhosttyKittyGraphicsPlacementIterator, data: GhosttyKittyGraphicsPlacementData, out: *mut c_void) -> GhosttyResult;
    pub fn ghostty_kitty_graphics_placement_get_multi(iterator: GhosttyKittyGraphicsPlacementIterator, count: usize, keys: *const GhosttyKittyGraphicsPlacementData, values: *mut *mut c_void, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_kitty_graphics_placement_grid_size(iterator: GhosttyKittyGraphicsPlacementIterator, image: GhosttyKittyGraphicsImage, terminal: GhosttyTerminal, out_cols: *mut u32, out_rows: *mut u32) -> GhosttyResult;
    pub fn ghostty_kitty_graphics_placement_iterator_free(iterator: GhosttyKittyGraphicsPlacementIterator);
    pub fn ghostty_kitty_graphics_placement_iterator_new(allocator: *const GhosttyAllocator, out_iterator: *mut GhosttyKittyGraphicsPlacementIterator) -> GhosttyResult;
    pub fn ghostty_kitty_graphics_placement_iterator_set(iterator: GhosttyKittyGraphicsPlacementIterator, option: GhosttyKittyGraphicsPlacementIteratorOption, value: *const c_void) -> GhosttyResult;
    pub fn ghostty_kitty_graphics_placement_next(iterator: GhosttyKittyGraphicsPlacementIterator) -> bool;
    pub fn ghostty_kitty_graphics_placement_pixel_size(iterator: GhosttyKittyGraphicsPlacementIterator, image: GhosttyKittyGraphicsImage, terminal: GhosttyTerminal, out_width: *mut u32, out_height: *mut u32) -> GhosttyResult;
    pub fn ghostty_kitty_graphics_placement_rect(iterator: GhosttyKittyGraphicsPlacementIterator, image: GhosttyKittyGraphicsImage, terminal: GhosttyTerminal, out_selection: *mut GhosttySelection) -> GhosttyResult;
    pub fn ghostty_kitty_graphics_placement_render_info(iterator: GhosttyKittyGraphicsPlacementIterator, image: GhosttyKittyGraphicsImage, terminal: GhosttyTerminal, out_info: *mut GhosttyKittyGraphicsPlacementRenderInfo) -> GhosttyResult;
    pub fn ghostty_kitty_graphics_placement_source_rect(iterator: GhosttyKittyGraphicsPlacementIterator, image: GhosttyKittyGraphicsImage, out_x: *mut u32, out_y: *mut u32, out_width: *mut u32, out_height: *mut u32) -> GhosttyResult;
    pub fn ghostty_kitty_graphics_placement_viewport_pos(iterator: GhosttyKittyGraphicsPlacementIterator, image: GhosttyKittyGraphicsImage, terminal: GhosttyTerminal, out_col: *mut i32, out_row: *mut i32) -> GhosttyResult;
    pub fn ghostty_mode_report_encode(mode: GhosttyMode, state: GhosttyModeReportState, buf: *mut c_char, buf_len: usize, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_mouse_encoder_encode(encoder: GhosttyMouseEncoder, event: GhosttyMouseEvent, out_buf: *mut c_char, out_buf_size: usize, out_len: *mut usize) -> GhosttyResult;
    pub fn ghostty_mouse_encoder_free(encoder: GhosttyMouseEncoder);
    pub fn ghostty_mouse_encoder_new(allocator: *const GhosttyAllocator, encoder: *mut GhosttyMouseEncoder) -> GhosttyResult;
    pub fn ghostty_mouse_encoder_reset(encoder: GhosttyMouseEncoder);
    pub fn ghostty_mouse_encoder_setopt(encoder: GhosttyMouseEncoder, option: GhosttyMouseEncoderOption, value: *const c_void);
    pub fn ghostty_mouse_encoder_setopt_from_terminal(encoder: GhosttyMouseEncoder, terminal: GhosttyTerminal);
    pub fn ghostty_mouse_event_clear_button(event: GhosttyMouseEvent);
    pub fn ghostty_mouse_event_free(event: GhosttyMouseEvent);
    pub fn ghostty_mouse_event_get_action(event: GhosttyMouseEvent) -> GhosttyMouseAction;
    pub fn ghostty_mouse_event_get_button(event: GhosttyMouseEvent, out_button: *mut GhosttyMouseButton) -> bool;
    pub fn ghostty_mouse_event_get_mods(event: GhosttyMouseEvent) -> GhosttyMods;
    pub fn ghostty_mouse_event_get_position(event: GhosttyMouseEvent) -> GhosttyMousePosition;
    pub fn ghostty_mouse_event_new(allocator: *const GhosttyAllocator, event: *mut GhosttyMouseEvent) -> GhosttyResult;
    pub fn ghostty_mouse_event_set_action(event: GhosttyMouseEvent, action: GhosttyMouseAction);
    pub fn ghostty_mouse_event_set_button(event: GhosttyMouseEvent, button: GhosttyMouseButton);
    pub fn ghostty_mouse_event_set_mods(event: GhosttyMouseEvent, mods: GhosttyMods);
    pub fn ghostty_mouse_event_set_position(event: GhosttyMouseEvent, position: GhosttyMousePosition);
    pub fn ghostty_osc_command_data(command: GhosttyOscCommand, data: GhosttyOscCommandData, out: *mut c_void) -> bool;
    pub fn ghostty_osc_command_type(command: GhosttyOscCommand) -> GhosttyOscCommandType;
    pub fn ghostty_osc_end(parser: GhosttyOscParser, terminator: u8) -> GhosttyOscCommand;
    pub fn ghostty_osc_free(parser: GhosttyOscParser);
    pub fn ghostty_osc_new(allocator: *const GhosttyAllocator, parser: *mut GhosttyOscParser) -> GhosttyResult;
    pub fn ghostty_osc_next(parser: GhosttyOscParser, byte: u8);
    pub fn ghostty_osc_reset(parser: GhosttyOscParser);
    pub fn ghostty_paste_encode(data: *mut c_char, data_len: usize, bracketed: bool, buf: *mut c_char, buf_len: usize, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_paste_is_safe(data: *const c_char, len: usize) -> bool;
    pub fn ghostty_render_state_begin_update(state: GhosttyRenderState, terminal: GhosttyTerminal) -> GhosttyResult;
    pub fn ghostty_render_state_clean(state: GhosttyRenderState) -> GhosttyResult;
    pub fn ghostty_render_state_end_update(state: GhosttyRenderState) -> GhosttyResult;
    pub fn ghostty_render_state_free(state: GhosttyRenderState);
    pub fn ghostty_render_state_get(state: GhosttyRenderState, data: GhosttyRenderStateData, out: *mut c_void) -> GhosttyResult;
    pub fn ghostty_render_state_get_multi(state: GhosttyRenderState, count: usize, keys: *const GhosttyRenderStateData, values: *mut *mut c_void, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_render_state_new(allocator: *const GhosttyAllocator, state: *mut GhosttyRenderState) -> GhosttyResult;
    pub fn ghostty_render_state_row_cells_free(cells: GhosttyRenderStateRowCells);
    pub fn ghostty_render_state_row_cells_get(cells: GhosttyRenderStateRowCells, data: GhosttyRenderStateRowCellsData, out: *mut c_void) -> GhosttyResult;
    pub fn ghostty_render_state_row_cells_get_multi(cells: GhosttyRenderStateRowCells, count: usize, keys: *const GhosttyRenderStateRowCellsData, values: *mut *mut c_void, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_render_state_row_cells_new(allocator: *const GhosttyAllocator, out_cells: *mut GhosttyRenderStateRowCells) -> GhosttyResult;
    pub fn ghostty_render_state_row_cells_next(cells: GhosttyRenderStateRowCells) -> bool;
    pub fn ghostty_render_state_row_cells_select(cells: GhosttyRenderStateRowCells, x: u16) -> GhosttyResult;
    pub fn ghostty_render_state_row_get(iterator: GhosttyRenderStateRowIterator, data: GhosttyRenderStateRowData, out: *mut c_void) -> GhosttyResult;
    pub fn ghostty_render_state_row_get_multi(iterator: GhosttyRenderStateRowIterator, count: usize, keys: *const GhosttyRenderStateRowData, values: *mut *mut c_void, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_render_state_row_iterator_free(iterator: GhosttyRenderStateRowIterator);
    pub fn ghostty_render_state_row_iterator_new(allocator: *const GhosttyAllocator, out_iterator: *mut GhosttyRenderStateRowIterator) -> GhosttyResult;
    pub fn ghostty_render_state_row_iterator_next(iterator: GhosttyRenderStateRowIterator) -> bool;
    pub fn ghostty_render_state_row_iterator_next_dirty(iterator: GhosttyRenderStateRowIterator, out_y: *mut u16) -> bool;
    pub fn ghostty_render_state_row_set(iterator: GhosttyRenderStateRowIterator, option: GhosttyRenderStateRowOption, value: *const c_void) -> GhosttyResult;
    pub fn ghostty_render_state_set(state: GhosttyRenderState, option: GhosttyRenderStateOption, value: *const c_void) -> GhosttyResult;
    pub fn ghostty_render_state_update(state: GhosttyRenderState, terminal: GhosttyTerminal) -> GhosttyResult;
    pub fn ghostty_row_get(row: GhosttyRow, data: GhosttyRowData, out: *mut c_void) -> GhosttyResult;
    pub fn ghostty_row_get_multi(row: GhosttyRow, count: usize, keys: *const GhosttyRowData, values: *mut *mut c_void, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_search_feed(search: GhosttySearch) -> GhosttyResult;
    pub fn ghostty_search_free(search: GhosttySearch);
    pub fn ghostty_search_get(search: GhosttySearch, data: GhosttySearchData, value: *mut c_void) -> GhosttyResult;
    pub fn ghostty_search_get_multi(search: GhosttySearch, count: usize, keys: *const GhosttySearchData, values: *mut *mut c_void, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_search_new(allocator: *const GhosttyAllocator, out_search: *mut GhosttySearch, terminal: GhosttyTerminal) -> GhosttyResult;
    pub fn ghostty_search_run(search: GhosttySearch) -> GhosttyResult;
    pub fn ghostty_search_set(search: GhosttySearch, option: GhosttySearchOption, value: *const c_void) -> GhosttyResult;
    pub fn ghostty_search_tick(search: GhosttySearch, out_status: *mut GhosttySearchStatus) -> GhosttyResult;
    pub fn ghostty_selection_gesture_event(gesture: GhosttySelectionGesture, terminal: GhosttyTerminal, event: GhosttySelectionGestureEvent, out_selection: *mut GhosttySelection) -> GhosttyResult;
    pub fn ghostty_selection_gesture_event_free(event: GhosttySelectionGestureEvent);
    pub fn ghostty_selection_gesture_event_new(allocator: *const GhosttyAllocator, out_event: *mut GhosttySelectionGestureEvent, r#type: GhosttySelectionGestureEventType) -> GhosttyResult;
    pub fn ghostty_selection_gesture_event_set(event: GhosttySelectionGestureEvent, option: GhosttySelectionGestureEventOption, value: *const c_void) -> GhosttyResult;
    pub fn ghostty_selection_gesture_free(gesture: GhosttySelectionGesture, terminal: GhosttyTerminal);
    pub fn ghostty_selection_gesture_get(gesture: GhosttySelectionGesture, terminal: GhosttyTerminal, data: GhosttySelectionGestureData, value: *mut c_void) -> GhosttyResult;
    pub fn ghostty_selection_gesture_get_multi(gesture: GhosttySelectionGesture, terminal: GhosttyTerminal, count: usize, keys: *const GhosttySelectionGestureData, values: *mut *mut c_void, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_selection_gesture_new(allocator: *const GhosttyAllocator, out_gesture: *mut GhosttySelectionGesture) -> GhosttyResult;
    pub fn ghostty_selection_gesture_reset(gesture: GhosttySelectionGesture, terminal: GhosttyTerminal);
    pub fn ghostty_sgr_attribute_tag(attr: GhosttySgrAttribute) -> GhosttySgrAttributeTag;
    pub fn ghostty_sgr_attribute_value(attr: *mut GhosttySgrAttribute) -> *mut GhosttySgrAttributeValue;
    pub fn ghostty_sgr_free(parser: GhosttySgrParser);
    pub fn ghostty_sgr_new(allocator: *const GhosttyAllocator, parser: *mut GhosttySgrParser) -> GhosttyResult;
    pub fn ghostty_sgr_next(parser: GhosttySgrParser, attr: *mut GhosttySgrAttribute) -> bool;
    pub fn ghostty_sgr_reset(parser: GhosttySgrParser);
    pub fn ghostty_sgr_set_params(parser: GhosttySgrParser, params: *const u16, separators: *const c_char, len: usize) -> GhosttyResult;
    pub fn ghostty_sgr_unknown_full(unknown: GhosttySgrUnknown, ptr: *const *const u16) -> usize;
    pub fn ghostty_sgr_unknown_partial(unknown: GhosttySgrUnknown, ptr: *const *const u16) -> usize;
    pub fn ghostty_size_report_encode(style: GhosttySizeReportStyle, size: GhosttySizeReportSize, buf: *mut c_char, buf_len: usize, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_snapshot_decoder_decode(decoder: GhosttySnapshotDecoder, terminal: *mut GhosttyTerminal) -> GhosttyResult;
    pub fn ghostty_snapshot_decoder_free(decoder: GhosttySnapshotDecoder);
    pub fn ghostty_snapshot_decoder_get(decoder: GhosttySnapshotDecoder, data: GhosttySnapshotDecoderData, out: *mut c_void) -> GhosttyResult;
    pub fn ghostty_snapshot_decoder_get_multi(decoder: GhosttySnapshotDecoder, count: usize, keys: *const GhosttySnapshotDecoderData, values: *mut *mut c_void, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_snapshot_decoder_new(allocator: *const GhosttyAllocator, decoder: *mut GhosttySnapshotDecoder, reader: GhosttyReader) -> GhosttyResult;
    pub fn ghostty_snapshot_decoder_new_buf(allocator: *const GhosttyAllocator, decoder: *mut GhosttySnapshotDecoder, ptr: *const u8, len: usize) -> GhosttyResult;
    pub fn ghostty_snapshot_decoder_next(decoder: GhosttySnapshotDecoder) -> GhosttyResult;
    pub fn ghostty_snapshot_decoder_ready(decoder: GhosttySnapshotDecoder, terminal: *mut GhosttyTerminal) -> GhosttyResult;
    pub fn ghostty_snapshot_decoder_set(decoder: GhosttySnapshotDecoder, option: GhosttySnapshotDecoderOption, value: *const c_void) -> GhosttyResult;
    pub fn ghostty_snapshot_encode(terminal: GhosttyTerminal, writer: GhosttyWriter) -> GhosttyResult;
    pub fn ghostty_snapshot_encode_alloc(terminal: GhosttyTerminal, allocator: *const GhosttyAllocator, out_ptr: *mut *mut u8, out_len: *mut usize) -> GhosttyResult;
    pub fn ghostty_snapshot_encode_buf(terminal: GhosttyTerminal, buf: *mut u8, buf_len: usize, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_style_default(style: *mut GhosttyStyle);
    pub fn ghostty_style_is_default(style: *const GhosttyStyle) -> bool;
    pub fn ghostty_sys_log_stderr(userdata: *mut c_void, level: GhosttySysLogLevel, scope: *const u8, scope_len: usize, message: *const u8, message_len: usize);
    pub fn ghostty_sys_set(option: GhosttySysOption, value: *const c_void) -> GhosttyResult;
    pub fn ghostty_terminal_compress(terminal: GhosttyTerminal, mode: GhosttyTerminalCompressionMode, out_result: *mut GhosttyTerminalCompressionResult) -> GhosttyResult;
    pub fn ghostty_terminal_compression_activity(terminal: GhosttyTerminal, out_activity: *mut u64) -> GhosttyResult;
    pub fn ghostty_terminal_continuation_alloc(terminal: GhosttyTerminal, allocator: *const GhosttyAllocator, out_ptr: *mut *mut u8, out_len: *mut usize) -> GhosttyResult;
    pub fn ghostty_terminal_continuation_buf(terminal: GhosttyTerminal, buf: *mut u8, buf_len: usize, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_terminal_continuation_write(terminal: GhosttyTerminal, writer: GhosttyWriter) -> GhosttyResult;
    pub fn ghostty_terminal_free(terminal: GhosttyTerminal);
    pub fn ghostty_terminal_get(terminal: GhosttyTerminal, data: GhosttyTerminalData, out: *mut c_void) -> GhosttyResult;
    pub fn ghostty_terminal_get_multi(terminal: GhosttyTerminal, count: usize, keys: *const GhosttyTerminalData, values: *mut *mut c_void, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_terminal_grid_ref(terminal: GhosttyTerminal, point: GhosttyPoint, out_ref: *mut GhosttyGridRef) -> GhosttyResult;
    pub fn ghostty_terminal_grid_ref_track(terminal: GhosttyTerminal, point: GhosttyPoint, out_ref: *mut GhosttyTrackedGridRef) -> GhosttyResult;
    pub fn ghostty_terminal_new(allocator: *const GhosttyAllocator, terminal: *mut GhosttyTerminal, cols: u16, rows: u16) -> GhosttyResult;
    pub fn ghostty_terminal_paste(terminal: GhosttyTerminal, paste: *const GhosttyPaste, out_written: *mut bool) -> GhosttyResult;
    pub fn ghostty_terminal_point_from_grid_ref(terminal: GhosttyTerminal, r#ref: *const GhosttyGridRef, tag: GhosttyPointTag, out: *mut GhosttyPointCoordinate) -> GhosttyResult;
    pub fn ghostty_terminal_reset(terminal: GhosttyTerminal);
    pub fn ghostty_terminal_resize(terminal: GhosttyTerminal, cols: u16, rows: u16, cell_width_px: u32, cell_height_px: u32) -> GhosttyResult;
    pub fn ghostty_terminal_scroll_viewport(terminal: GhosttyTerminal, behavior: GhosttyTerminalScrollViewport);
    pub fn ghostty_terminal_select_all(terminal: GhosttyTerminal, out_selection: *mut GhosttySelection) -> GhosttyResult;
    pub fn ghostty_terminal_select_line(terminal: GhosttyTerminal, options: *const GhosttyTerminalSelectLineOptions, out_selection: *mut GhosttySelection) -> GhosttyResult;
    pub fn ghostty_terminal_select_output(terminal: GhosttyTerminal, r#ref: GhosttyGridRef, out_selection: *mut GhosttySelection) -> GhosttyResult;
    pub fn ghostty_terminal_select_word(terminal: GhosttyTerminal, options: *const GhosttyTerminalSelectWordOptions, out_selection: *mut GhosttySelection) -> GhosttyResult;
    pub fn ghostty_terminal_select_word_between(terminal: GhosttyTerminal, options: *const GhosttyTerminalSelectWordBetweenOptions, out_selection: *mut GhosttySelection) -> GhosttyResult;
    pub fn ghostty_terminal_selection_adjust(terminal: GhosttyTerminal, selection: *mut GhosttySelection, adjustment: GhosttySelectionAdjust) -> GhosttyResult;
    pub fn ghostty_terminal_selection_contains(terminal: GhosttyTerminal, selection: *const GhosttySelection, point: GhosttyPoint, out_contains: *mut bool) -> GhosttyResult;
    pub fn ghostty_terminal_selection_equal(terminal: GhosttyTerminal, a: *const GhosttySelection, b: *const GhosttySelection, out_equal: *mut bool) -> GhosttyResult;
    pub fn ghostty_terminal_selection_format_alloc(terminal: GhosttyTerminal, allocator: *const GhosttyAllocator, options: GhosttyTerminalSelectionFormatOptions, out_ptr: *mut *mut u8, out_len: *mut usize) -> GhosttyResult;
    pub fn ghostty_terminal_selection_format_buf(terminal: GhosttyTerminal, options: GhosttyTerminalSelectionFormatOptions, buf: *mut u8, buf_len: usize, out_written: *mut usize) -> GhosttyResult;
    pub fn ghostty_terminal_selection_order(terminal: GhosttyTerminal, selection: *const GhosttySelection, out_order: *mut GhosttySelectionOrder) -> GhosttyResult;
    pub fn ghostty_terminal_selection_ordered(terminal: GhosttyTerminal, selection: *const GhosttySelection, desired: GhosttySelectionOrder, out_selection: *mut GhosttySelection) -> GhosttyResult;
    pub fn ghostty_terminal_set(terminal: GhosttyTerminal, option: GhosttyTerminalOption, value: *const c_void) -> GhosttyResult;
    pub fn ghostty_terminal_vt_write(terminal: GhosttyTerminal, data: *const u8, len: usize);
    pub fn ghostty_terminal_vt_write_until_ground(terminal: GhosttyTerminal, data: *const u8, len: usize, out_consumed: *mut usize) -> GhosttyResult;
    pub fn ghostty_tracked_grid_ref_free(r#ref: GhosttyTrackedGridRef);
    pub fn ghostty_tracked_grid_ref_has_value(r#ref: GhosttyTrackedGridRef) -> bool;
    pub fn ghostty_tracked_grid_ref_point(r#ref: GhosttyTrackedGridRef, tag: GhosttyPointTag, out_point: *mut GhosttyPointCoordinate) -> GhosttyResult;
    pub fn ghostty_tracked_grid_ref_set(r#ref: GhosttyTrackedGridRef, terminal: GhosttyTerminal, point: GhosttyPoint) -> GhosttyResult;
    pub fn ghostty_tracked_grid_ref_snapshot(r#ref: GhosttyTrackedGridRef, out_ref: *mut GhosttyGridRef) -> GhosttyResult;
    pub fn ghostty_type_json() -> *const c_char;
    pub fn ghostty_unicode_codepoint_width(cp: u32) -> u8;
    pub fn ghostty_unicode_grapheme_width(cps: *const u32, len: usize, width: *mut u8) -> usize;
}

// ---- SKIPPED -----------------------------------------------------------

// Items the generator could not represent as Rust declarations:

//   - declared only under `#ifdef __wasm__`: include/ghostty/vt/wasm.h: ghostty_wasm_alloc
//   - declared only under `#ifdef __wasm__`: include/ghostty/vt/wasm.h: ghostty_wasm_alloc_opaque
//   - declared only under `#ifdef __wasm__`: include/ghostty/vt/wasm.h: ghostty_wasm_free
//   - declared only under `#ifdef __wasm__`: include/ghostty/vt/wasm.h: ghostty_wasm_free_opaque
//   - declared only under `#ifdef __wasm__`: include/ghostty/vt/wasm.h: ghostty_wasm_take_opaque

