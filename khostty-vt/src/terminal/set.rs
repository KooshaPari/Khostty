//! Option setters for [`Terminal`], wrapping `ghostty_terminal_set`.
//!
//! The C API passes every option's value as a `const void*`, whose pointee type
//! depends on the option. Two families are exposed here:
//!
//! * **Value options** hold scalars or POD structs, so the value can be created
//!   on the stack and its address handed over for the duration of the call.
//! * **String options** are the exception worth stating explicitly: the header
//!   says the bytes "are copied into the terminal", so a borrow of the caller's
//!   `&str` is sufficient and no lifetime is attached to the terminal.
//!
//! Callback ("effect") options are registered through
//! [`Terminal::set_write_pty`] and [`Terminal::set_bell`] in the parent module
//! instead, because they need owned closure storage on the Rust side.

use super::{CursorStyle, Terminal};
use crate::color::Color;
use crate::error::{GhosttyError, Result};
use crate::ffi;

impl Terminal {
    /// Set the terminal title directly, bypassing `OSC 0`/`OSC 2`.
    ///
    /// The bytes are copied into the terminal.
    pub fn set_title(&mut self, title: &str) -> Result<()> {
        self.set_string(ffi::GHOSTTY_TERMINAL_OPT_TITLE, title)
    }

    /// Set the working directory directly, bypassing `OSC 7`.
    ///
    /// The bytes are copied into the terminal.
    pub fn set_pwd(&mut self, pwd: &str) -> Result<()> {
        self.set_string(ffi::GHOSTTY_TERMINAL_OPT_PWD, pwd)
    }

    /// Set the terminfo name reported for an `XTGETTCAP TN` query, for example
    /// `xterm-256color`.
    ///
    /// # Errors
    ///
    /// [`GhosttyError::InvalidValue`] for a name longer than 128 bytes, which
    /// the upstream implementation rejects.
    pub fn set_terminfo_name(&mut self, name: &str) -> Result<()> {
        self.set_string(ffi::GHOSTTY_TERMINAL_OPT_TERMINFO_NAME, name)
    }

    /// Set the default `DECSCUSR` cursor style used before the program changes
    /// it.
    pub fn set_default_cursor_style(&mut self, style: CursorStyle) -> Result<()> {
        let value = style.to_raw();
        self.set_value(ffi::GHOSTTY_TERMINAL_OPT_DEFAULT_CURSOR_STYLE, &value)
    }

    /// Set whether the cursor blinks by default.
    pub fn set_default_cursor_blink(&mut self, blink: bool) -> Result<()> {
        let value = u8::from(blink);
        self.set_value(ffi::GHOSTTY_TERMINAL_OPT_DEFAULT_CURSOR_BLINK, &value)
    }

    /// Set the foreground colour.
    pub fn set_foreground(&mut self, color: Color) -> Result<()> {
        self.set_color(ffi::GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND, color)
    }

    /// Set the background colour.
    pub fn set_background(&mut self, color: Color) -> Result<()> {
        self.set_color(ffi::GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND, color)
    }

    /// Set the cursor colour.
    pub fn set_cursor_color(&mut self, color: Color) -> Result<()> {
        self.set_color(ffi::GHOSTTY_TERMINAL_OPT_COLOR_CURSOR, color)
    }

    /// Replace the 256-entry palette.
    pub fn set_palette(&mut self, palette: &[Color; 256]) -> Result<()> {
        let value: [ffi::GhosttyColorRgb; 256] = palette.map(Color::to_ffi);
        self.set_value(ffi::GHOSTTY_TERMINAL_OPT_COLOR_PALETTE, &value)
    }

    /// Cap the scrollback at `lines` physical lines.
    ///
    /// Approximate by construction: libghostty prunes at page granularity, so
    /// the effective limit is usually somewhat higher.
    pub fn set_scrollback_max_lines(&mut self, lines: usize) -> Result<()> {
        self.set_value(ffi::GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_LINES, &lines)
    }

    /// Cap the scrollback at `bytes` of retained page storage.
    pub fn set_scrollback_max_bytes(&mut self, bytes: usize) -> Result<()> {
        self.set_value(ffi::GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_BYTES, &bytes)
    }

    /// Cap how many bytes of pending continuation output the terminal retains.
    pub fn set_continuation_max_bytes(&mut self, bytes: usize) -> Result<()> {
        self.set_value(ffi::GHOSTTY_TERMINAL_OPT_CONTINUATION_MAX_BYTES, &bytes)
    }

    /// Cap how many bytes of an unrecognised APC-style sequence are retained
    /// for the unknown-sequence effect.
    pub fn set_unknown_sequence_max_bytes(&mut self, bytes: usize) -> Result<()> {
        self.set_value(ffi::GHOSTTY_TERMINAL_OPT_UNKNOWN_MAX_BYTES, &bytes)
    }

    /// Cap how much decoded Kitty graphics image storage the terminal keeps.
    pub fn set_kitty_image_storage_limit(&mut self, bytes: u64) -> Result<()> {
        self.set_value(ffi::GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_STORAGE_LIMIT, &bytes)
    }

    /// Enable or disable reporting of the terminal title through the title
    /// report sequence.
    pub fn set_title_report(&mut self, enabled: bool) -> Result<()> {
        let value = u8::from(enabled);
        self.set_value(ffi::GHOSTTY_TERMINAL_OPT_TITLE_REPORT, &value)
    }

    /// Enable or disable the glyph protocol.
    pub fn set_glyph_protocol(&mut self, enabled: bool) -> Result<()> {
        let value = u8::from(enabled);
        self.set_value(ffi::GHOSTTY_TERMINAL_OPT_GLYPH_PROTOCOL, &value)
    }

    /// Cap the size of an `APC` sequence the parser will buffer.
    pub fn set_apc_max_bytes(&mut self, bytes: usize) -> Result<()> {
        self.set_value(ffi::GHOSTTY_TERMINAL_OPT_APC_MAX_BYTES, &bytes)
    }

    /// Cap the size of a Kitty graphics `APC` sequence the parser will buffer.
    pub fn set_apc_max_bytes_kitty(&mut self, bytes: usize) -> Result<()> {
        self.set_value(ffi::GHOSTTY_TERMINAL_OPT_APC_MAX_BYTES_KITTY, &bytes)
    }

    // ---- Private plumbing --------------------------------------------------

    /// Hand a pointer to a POD value to `ghostty_terminal_set`.
    fn set_value<T>(&mut self, option: ffi::GhosttyTerminalOption, value: &T) -> Result<()> {
        // SAFETY: `self.raw` is live, and `value` points at a `T` whose layout
        // matches what `include/ghostty/vt/terminal.h` documents for `option`.
        let code = unsafe {
            ffi::ghostty_terminal_set(
                self.raw,
                option,
                (value as *const T).cast::<core::ffi::c_void>(),
            )
        };
        GhosttyError::from_result(code)
    }

    fn set_color(&mut self, option: ffi::GhosttyTerminalOption, color: Color) -> Result<()> {
        let value = color.to_ffi();
        self.set_value(option, &value)
    }

    /// Set a `GhosttyString` option.
    ///
    /// The library copies the bytes, so borrowing the caller's `&str` for the
    /// duration of the call is enough and no lifetime ties the string to the
    /// terminal.
    fn set_string(&mut self, option: ffi::GhosttyTerminalOption, value: &str) -> Result<()> {
        let borrowed = ffi::GhosttyString {
            ptr: value.as_ptr(),
            len: value.len(),
        };
        self.set_value(option, &borrowed)
    }
}
