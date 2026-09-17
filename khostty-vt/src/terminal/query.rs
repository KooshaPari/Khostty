//! Read accessors for [`Terminal`], wrapping `ghostty_terminal_get`.
//!
//! Every accessor pairs a `GHOSTTY_TERMINAL_DATA_*` key with the Rust type the
//! header documents as that key's "Output type". The pairs are listed in
//! `include/ghostty/vt/terminal.h`; `tests/abi_layout.rs` independently checks
//! that each C type this module marshals has the size and alignment the C
//! compiler reports.
//!
//! Two conventions come from the C API and are reflected here:
//!
//! * `GHOSTTY_NO_VALUE` means "this was never set", not "something failed". For
//!   string-valued keys that becomes `Ok(None)`.
//! * Borrowed pointers (`GhosttyString`) are only valid until the next mutating
//!   call on the terminal, so every accessor copies out immediately.

use super::Terminal;
use crate::color::Color;
use crate::error::{GhosttyError, Result};
use crate::ffi;
use crate::style::Style;
use core::ffi::c_void;
use core::ptr;

impl Terminal {
    // ---- Geometry ----------------------------------------------------------

    /// Number of columns.
    pub fn cols(&self) -> Result<u16> {
        self.get_u16(ffi::GHOSTTY_TERMINAL_DATA_COLS)
    }

    /// Number of rows in the active area.
    pub fn rows(&self) -> Result<u16> {
        self.get_u16(ffi::GHOSTTY_TERMINAL_DATA_ROWS)
    }

    /// Pixel size of the terminal surface, as last reported to
    /// [`Terminal::resize`].
    pub fn size_px(&self) -> Result<(u32, u32)> {
        Ok((
            self.get_u32(ffi::GHOSTTY_TERMINAL_DATA_WIDTH_PX)?,
            self.get_u32(ffi::GHOSTTY_TERMINAL_DATA_HEIGHT_PX)?,
        ))
    }

    /// Total rows in the active screen, including scrollback.
    pub fn total_rows(&self) -> Result<usize> {
        self.get_usize(ffi::GHOSTTY_TERMINAL_DATA_TOTAL_ROWS)
    }

    /// Rows currently held in scrollback.
    pub fn scrollback_rows(&self) -> Result<usize> {
        self.get_usize(ffi::GHOSTTY_TERMINAL_DATA_SCROLLBACK_ROWS)
    }

    // ---- Cursor ------------------------------------------------------------

    /// Cursor column within the active area, 0-indexed.
    pub fn cursor_x(&self) -> Result<u16> {
        self.get_u16(ffi::GHOSTTY_TERMINAL_DATA_CURSOR_X)
    }

    /// Cursor row within the active area, 0-indexed.
    pub fn cursor_y(&self) -> Result<u16> {
        self.get_u16(ffi::GHOSTTY_TERMINAL_DATA_CURSOR_Y)
    }

    /// Cursor position as `(x, y)`, both 0-indexed.
    pub fn cursor_position(&self) -> Result<(u16, u16)> {
        let mut out = [0u16; 2];
        let keys = [
            ffi::GHOSTTY_TERMINAL_DATA_CURSOR_X,
            ffi::GHOSTTY_TERMINAL_DATA_CURSOR_Y,
        ];
        let mut values: [*mut c_void; 2] = [
            (&mut out[0] as *mut u16).cast(),
            (&mut out[1] as *mut u16).cast(),
        ];
        let mut written: usize = 0;
        // SAFETY: `self.raw` is live; `keys` and `values` are parallel arrays of
        // length 2; every `values[i]` points at a `u16` slot that matches
        // `keys[i]`'s documented output type; `&mut written` is a valid
        // out-parameter.
        let code = unsafe {
            ffi::ghostty_terminal_get_multi(
                self.raw,
                keys.len(),
                keys.as_ptr(),
                values.as_mut_ptr(),
                &mut written,
            )
        };
        GhosttyError::from_result(code)?;
        if written != keys.len() {
            // A short write leaves at least one slot untouched, so reading both
            // would read uninitialised memory.
            return Err(GhosttyError::Unknown {
                code: written as i32,
            });
        }
        Ok((out[0], out[1]))
    }

    /// Whether the next printed character will soft-wrap.
    pub fn cursor_pending_wrap(&self) -> Result<bool> {
        self.get_bool(ffi::GHOSTTY_TERMINAL_DATA_CURSOR_PENDING_WRAP)
    }

    /// Whether the cursor is visible given the current terminal modes.
    pub fn cursor_visible(&self) -> Result<bool> {
        self.get_bool(ffi::GHOSTTY_TERMINAL_DATA_CURSOR_VISIBLE)
    }

    /// Whether the cursor sits at a shell prompt according to semantic prompt
    /// markers (`OSC 133`).
    pub fn cursor_at_prompt(&self) -> Result<bool> {
        self.get_bool(ffi::GHOSTTY_TERMINAL_DATA_CURSOR_AT_PROMPT)
    }

    /// The SGR style that will be applied to newly printed characters.
    ///
    /// This is `GHOSTTY_TERMINAL_DATA_CURSOR_STYLE`, whose documented output
    /// type is a whole `GhosttyStyle` struct. It is *not* the `DECSCUSR` cursor
    /// shape; that is configured with
    /// [`Terminal::set_default_cursor_style`] and read back from the render
    /// state.
    pub fn cursor_sgr_style(&self) -> Result<Style> {
        let raw: ffi::GhosttyStyle = self.get_value(ffi::GHOSTTY_TERMINAL_DATA_CURSOR_STYLE)?;
        let (style, declared_size) = Style::from_ffi(raw);
        if declared_size != core::mem::size_of::<ffi::GhosttyStyle>() {
            // The library disagrees with this crate about the struct layout,
            // which means the binding is stale. Refuse the value rather than
            // hand back fields read at the wrong offsets.
            return Err(GhosttyError::InvalidValue);
        }
        Ok(style)
    }

    // ---- Screens and modes -------------------------------------------------

    /// Which screen is active.
    pub fn active_screen(&self) -> Result<super::Screen> {
        Ok(super::Screen::from_raw(
            self.get_i32(ffi::GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN)?,
        ))
    }

    /// Whether any mouse tracking mode is enabled.
    pub fn mouse_tracking(&self) -> Result<bool> {
        self.get_bool(ffi::GHOSTTY_TERMINAL_DATA_MOUSE_TRACKING)
    }

    /// Current Kitty keyboard protocol flags.
    pub fn kitty_keyboard_flags(&self) -> Result<u8> {
        self.get_u8(ffi::GHOSTTY_TERMINAL_DATA_KITTY_KEYBOARD_FLAGS)
    }

    /// Whether the parser is at ground state, i.e. no sequence is partially
    /// consumed.
    pub fn vt_ground(&self) -> Result<bool> {
        self.get_bool(ffi::GHOSTTY_TERMINAL_DATA_VT_GROUND)
    }

    /// Whether a VT processing error has been recorded.
    pub fn has_vt_processing_error(&self) -> Result<bool> {
        self.get_bool(ffi::GHOSTTY_TERMINAL_DATA_VT_PROCESSING_ERROR)
    }

    /// Whether the viewport is pinned to the active area rather than parked in
    /// scrollback.
    pub fn viewport_active(&self) -> Result<bool> {
        self.get_bool(ffi::GHOSTTY_TERMINAL_DATA_VIEWPORT_ACTIVE)
    }

    // ---- Text --------------------------------------------------------------

    /// The terminal title set by `OSC 0` or `OSC 2`, if any has been set.
    ///
    /// Returns `Ok(None)` for `GHOSTTY_NO_VALUE`, which is the documented "no
    /// title yet" answer rather than an error.
    pub fn title(&self) -> Result<Option<String>> {
        self.get_string(ffi::GHOSTTY_TERMINAL_DATA_TITLE)
    }

    /// The working directory reported by `OSC 7` and friends, if any.
    pub fn pwd(&self) -> Result<Option<String>> {
        self.get_string(ffi::GHOSTTY_TERMINAL_DATA_PWD)
    }

    // ---- Colours -----------------------------------------------------------

    /// The foreground colour, if one has been set.
    ///
    /// The C contract reports `GHOSTTY_NO_VALUE` when nothing has set it, which
    /// is the state of a fresh terminal rather than an error, so it maps to
    /// `Ok(None)`. Use [`Terminal::default_foreground`] for the value ignoring any
    /// program override, and the render state's colours when a renderer needs a
    /// value that is always present.
    pub fn foreground(&self) -> Result<Option<Color>> {
        self.get_optional_color(ffi::GHOSTTY_TERMINAL_DATA_COLOR_FOREGROUND)
    }

    /// The background colour, if one has been set.
    ///
    /// See [`Terminal::foreground`] for the `None` case.
    pub fn background(&self) -> Result<Option<Color>> {
        self.get_optional_color(ffi::GHOSTTY_TERMINAL_DATA_COLOR_BACKGROUND)
    }

    /// The cursor colour, if one has been set.
    ///
    /// See [`Terminal::foreground`] for the `None` case.
    pub fn cursor_color(&self) -> Result<Option<Color>> {
        self.get_optional_color(ffi::GHOSTTY_TERMINAL_DATA_COLOR_CURSOR)
    }

    /// The foreground colour ignoring any program override, if configured.
    ///
    /// This is what a renderer treats as the theme default.
    pub fn default_foreground(&self) -> Result<Option<Color>> {
        self.get_optional_color(ffi::GHOSTTY_TERMINAL_DATA_COLOR_FOREGROUND_DEFAULT)
    }

    /// The background colour ignoring any program override, if configured.
    pub fn default_background(&self) -> Result<Option<Color>> {
        self.get_optional_color(ffi::GHOSTTY_TERMINAL_DATA_COLOR_BACKGROUND_DEFAULT)
    }

    /// The cursor colour ignoring any program override, if configured.
    pub fn default_cursor_color(&self) -> Result<Option<Color>> {
        self.get_optional_color(ffi::GHOSTTY_TERMINAL_DATA_COLOR_CURSOR_DEFAULT)
    }

    /// The active 256-entry palette.
    pub fn palette(&self) -> Result<[Color; 256]> {
        Ok(self
            .get_value::<[ffi::GhosttyColorRgb; 256]>(ffi::GHOSTTY_TERMINAL_DATA_COLOR_PALETTE)?
            .map(Color::from_ffi))
    }

    /// The default 256-entry palette, before any program modified it.
    pub fn default_palette(&self) -> Result<[Color; 256]> {
        Ok(self
            .get_value::<[ffi::GhosttyColorRgb; 256]>(
                ffi::GHOSTTY_TERMINAL_DATA_COLOR_PALETTE_DEFAULT,
            )?
            .map(Color::from_ffi))
    }

    // ---- Scrollback --------------------------------------------------------

    /// Scrollback geometry, for drawing a scrollbar.
    pub fn scrollbar(&self) -> Result<super::Scrollbar> {
        let raw: ffi::GhosttyTerminalScrollbar =
            self.get_value(ffi::GHOSTTY_TERMINAL_DATA_SCROLLBAR)?;
        Ok(super::Scrollbar {
            total: raw.total,
            offset: raw.offset,
            len: raw.len,
        })
    }

    /// The configured scrollback byte cap.
    pub fn scrollback_max_bytes(&self) -> Result<usize> {
        self.get_usize(ffi::GHOSTTY_TERMINAL_DATA_SCROLLBACK_MAX_BYTES)
    }

    /// The configured scrollback line cap.
    pub fn scrollback_max_lines(&self) -> Result<usize> {
        self.get_usize(ffi::GHOSTTY_TERMINAL_DATA_SCROLLBACK_MAX_LINES)
    }

    /// Opaque activity token, bumped whenever compression-relevant state
    /// changes. Feed it to an idle timer to decide when to compress.
    pub fn compression_activity(&self) -> Result<u64> {
        let mut activity: u64 = 0;
        // SAFETY: `self.raw` is live and `&mut activity` is a valid
        // out-parameter for a `uint64_t`.
        let code = unsafe { ffi::ghostty_terminal_compression_activity(self.raw, &mut activity) };
        GhosttyError::from_result(code)?;
        Ok(activity)
    }

    // ---- Private marshalling ----------------------------------------------

    /// Read a value of type `T` for `key`.
    ///
    /// Callers pair `key` with the `T` its documented "Output type" names; the
    /// pairs are the single-line calls above.
    fn get_value<T: Copy>(&self, key: ffi::GhosttyTerminalData) -> Result<T> {
        let mut out = core::mem::MaybeUninit::<T>::uninit();
        // SAFETY: `self.raw` is live, and `out` is an uninitialised slot large
        // enough for the `T` that `key` documents.
        let code =
            unsafe { ffi::ghostty_terminal_get(self.raw, key, out.as_mut_ptr().cast::<c_void>()) };
        GhosttyError::from_result(code)?;
        // SAFETY: on success the library fully initialised the slot.
        Ok(unsafe { out.assume_init() })
    }

    fn get_u8(&self, key: ffi::GhosttyTerminalData) -> Result<u8> {
        self.get_value(key)
    }

    fn get_u16(&self, key: ffi::GhosttyTerminalData) -> Result<u16> {
        self.get_value(key)
    }

    fn get_u32(&self, key: ffi::GhosttyTerminalData) -> Result<u32> {
        self.get_value(key)
    }

    fn get_usize(&self, key: ffi::GhosttyTerminalData) -> Result<usize> {
        self.get_value(key)
    }

    fn get_i32(&self, key: ffi::GhosttyTerminalData) -> Result<i32> {
        self.get_value(key)
    }

    /// Read a C `_Bool`.
    ///
    /// The library writes a one-byte `_Bool` holding 0 or 1. It is read as `u8`
    /// and compared so that a non-canonical byte could never become an invalid
    /// Rust `bool`.
    fn get_bool(&self, key: ffi::GhosttyTerminalData) -> Result<bool> {
        Ok(self.get_value::<u8>(key)? != 0)
    }

    /// Read a colour, mapping "not set" to `None`.
    ///
    /// All six colour data keys document `GHOSTTY_NO_VALUE` when nothing has set
    /// them, so that code is a normal answer rather than a failure.
    fn get_optional_color(&self, key: ffi::GhosttyTerminalData) -> Result<Option<Color>> {
        match self.get_value::<ffi::GhosttyColorRgb>(key) {
            Ok(value) => Ok(Some(Color::from_ffi(value))),
            Err(err) if err.is_empty_value() => Ok(None),
            Err(err) => Err(err),
        }
    }

    /// Read a borrowed `GhosttyString` and copy it out.
    fn get_string(&self, key: ffi::GhosttyTerminalData) -> Result<Option<String>> {
        let mut raw = ffi::GhosttyString {
            ptr: ptr::null(),
            len: 0,
        };
        // SAFETY: `self.raw` is live and `&mut raw` is a valid out-parameter for
        // a `GhosttyString`.
        let code = unsafe {
            ffi::ghostty_terminal_get(self.raw, key, (&mut raw as *mut ffi::GhosttyString).cast())
        };
        match GhosttyError::from_result(code) {
            Ok(()) => {}
            Err(err) if err.is_empty_value() => return Ok(None),
            Err(err) => return Err(err),
        }
        if raw.ptr.is_null() || raw.len == 0 {
            return Ok(None);
        }
        // SAFETY: `ptr`/`len` describe readable bytes that the library keeps
        // valid until the next mutating call on this terminal, and the copy
        // happens immediately here.
        let bytes = unsafe { core::slice::from_raw_parts(raw.ptr, raw.len) };
        Ok(Some(String::from_utf8_lossy(bytes).into_owned()))
    }
}
