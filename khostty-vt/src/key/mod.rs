//! Key event encoding.
//!
//! [`KeyEncoder`] mirrors `GhosttyKeyEncoder`: it turns a [`KeyEvent`] into the
//! escape sequence a program under the terminal expects. Both legacy encoding and
//! the Kitty keyboard protocol are supported; which one is used depends on the
//! encoder's options, and [`KeyEncoder::sync_from_terminal`] is how a real
//! embedder keeps those options in step with the modes the program set.
//!
//! # Why the event and the encoder are separate types
//!
//! The C API separates "what the user pressed" ([`KeyEvent`], an owned handle) from
//! "how this terminal wants it encoded" ([`KeyEncoder`], also owned). Upstream
//! notes that one event can be reused across encodes by mutating its properties.
//! That is preserved here: [`KeyEncoder::encode`] takes `&KeyEvent` and never
//! consumes it, and [`KeyEvent`]'s setters take `&mut self`.
//!
//! # Key codes
//!
//! All 177 `GHOSTTY_KEY_*` codes are available as `crate::ffi::GHOSTTY_KEY_*`,
//! each already typed as a `GhosttyKey`. [`Key`] wraps them with `From`/`Into`
//! so they can be passed straight to [`KeyEvent::set_key`], and carries associated
//! constants for the codes an encoder caller reaches for most often.

pub mod types;

pub use types::{Key, KeyAction, Mods, OptionAsAlt};

use crate::error::{GhosttyError, Result};
use crate::ffi;
use crate::sys::Allocator;
use crate::terminal::Terminal;
use core::ffi::c_void;
use core::marker::PhantomData;
use core::ptr;

/// One key event.
///
/// Owns a `GhosttyKeyEvent` and frees it in `Drop`. Reusable across encodes: set
/// new properties and encode again rather than allocating a fresh event, which is
/// the pattern upstream documents.
pub struct KeyEvent {
    raw: ffi::GhosttyKeyEvent,
    _not_thread_safe: PhantomData<*mut ()>,
}

impl KeyEvent {
    /// Allocate a key event.
    ///
    /// # Errors
    ///
    /// [`GhosttyError::OutOfMemory`] if the allocation fails,
    /// [`GhosttyError::NullHandle`] if the library reports success without a
    /// handle.
    pub fn new() -> Result<Self> {
        let mut raw: ffi::GhosttyKeyEvent = ptr::null_mut();
        // SAFETY: NULL selects the library's default allocator and `&mut raw` is a
        // valid out-parameter.
        let code = unsafe { ffi::ghostty_key_event_new(ptr::null(), &mut raw) };
        GhosttyError::from_result(code)?;
        if raw.is_null() {
            return Err(GhosttyError::NullHandle);
        }
        Ok(KeyEvent {
            raw,
            _not_thread_safe: PhantomData,
        })
    }

    /// Set what the user did.
    pub fn set_action(&mut self, action: KeyAction) {
        // SAFETY: `self.raw` is live; the value is a plain int.
        unsafe { ffi::ghostty_key_event_set_action(self.raw, action.to_raw()) };
    }

    /// What the user did.
    pub fn action(&self) -> KeyAction {
        // SAFETY: `self.raw` is live.
        KeyAction::from_raw(unsafe { ffi::ghostty_key_event_get_action(self.raw) })
    }

    /// Set which key.
    pub fn set_key(&mut self, key: Key) {
        // SAFETY: `self.raw` is live; the value is a plain int.
        unsafe { ffi::ghostty_key_event_set_key(self.raw, key.0) };
    }

    /// Which key.
    pub fn key(&self) -> Key {
        // SAFETY: `self.raw` is live.
        Key(unsafe { ffi::ghostty_key_event_get_key(self.raw) })
    }

    /// Set the modifiers held when the key was pressed.
    pub fn set_mods(&mut self, mods: Mods) {
        // SAFETY: `self.raw` is live; the value is a plain integer.
        unsafe { ffi::ghostty_key_event_set_mods(self.raw, mods.0) };
    }

    /// The modifiers held when the key was pressed.
    pub fn mods(&self) -> Mods {
        // SAFETY: `self.raw` is live.
        Mods(unsafe { ffi::ghostty_key_event_get_mods(self.raw) })
    }

    /// Set the modifiers the platform already consumed for this event.
    ///
    /// The Kitty protocol reports these so the program can tell which modifiers
    /// produced the text from which are still meaningful as input.
    pub fn set_consumed_mods(&mut self, mods: Mods) {
        // SAFETY: `self.raw` is live; the value is a plain integer.
        unsafe { ffi::ghostty_key_event_set_consumed_mods(self.raw, mods.0) };
    }

    /// The modifiers the platform already consumed.
    pub fn consumed_mods(&self) -> Mods {
        // SAFETY: `self.raw` is live.
        Mods(unsafe { ffi::ghostty_key_event_get_consumed_mods(self.raw) })
    }

    /// Set whether the event is part of an in-progress composition.
    pub fn set_composing(&mut self, composing: bool) {
        // SAFETY: `self.raw` is live; the value is a one-byte bool.
        unsafe { ffi::ghostty_key_event_set_composing(self.raw, composing) };
    }

    /// Whether the event is part of an in-progress composition.
    pub fn composing(&self) -> bool {
        // SAFETY: `self.raw` is live.
        unsafe { ffi::ghostty_key_event_get_composing(self.raw) }
    }

    /// Set the text this key produced.
    ///
    /// The library copies the bytes, which is why the getter below can hand back a
    /// pointer into the event's own storage.
    pub fn set_utf8(&mut self, utf8: &str) {
        // SAFETY: `self.raw` is live and the library copies `len` bytes from
        // `utf8`, which is valid for this call.
        unsafe { ffi::ghostty_key_event_set_utf8(self.raw, utf8.as_ptr().cast(), utf8.len()) };
    }

    /// The text this key produced.
    pub fn utf8(&self) -> Option<String> {
        let mut len: usize = 0;
        // SAFETY: `self.raw` is live and `&mut len` is a valid out-parameter.
        let ptr = unsafe { ffi::ghostty_key_event_get_utf8(self.raw, &mut len) };
        if ptr.is_null() || len == 0 {
            return None;
        }
        // SAFETY: the returned pointer addresses `len` bytes owned by the event,
        // which stays alive for this call; the copy happens immediately.
        let bytes = unsafe { core::slice::from_raw_parts(ptr.cast::<u8>(), len) };
        Some(String::from_utf8_lossy(bytes).into_owned())
    }

    /// Set the codepoint this key produces when Shift is not applied.
    ///
    /// The Kitty protocol uses it so a shifted key can report both the character
    /// typed and the underlying unshifted codepoint.
    pub fn set_unshifted_codepoint(&mut self, codepoint: u32) {
        // SAFETY: `self.raw` is live; the value is a plain integer.
        unsafe { ffi::ghostty_key_event_set_unshifted_codepoint(self.raw, codepoint) };
    }

    /// The unshifted codepoint, or zero when unset.
    pub fn unshifted_codepoint(&self) -> u32 {
        // SAFETY: `self.raw` is live.
        unsafe { ffi::ghostty_key_event_get_unshifted_codepoint(self.raw) }
    }

    /// Raw handle, for passing to sibling C APIs.
    pub fn as_raw(&self) -> ffi::GhosttyKeyEvent {
        self.raw
    }
}

impl Drop for KeyEvent {
    fn drop(&mut self) {
        if self.raw.is_null() {
            return;
        }
        // SAFETY: `self.raw` is a live handle owned solely by `self`.
        unsafe { ffi::ghostty_key_event_free(self.raw) };
        self.raw = ptr::null_mut();
    }
}

/// Encodes key events into terminal escape sequences.
///
/// Dropping this value calls `ghostty_key_encoder_free`.
pub struct KeyEncoder {
    raw: ffi::GhosttyKeyEncoder,
    _not_thread_safe: PhantomData<*mut ()>,
}

impl KeyEncoder {
    /// Allocate a key encoder with the library's default options.
    ///
    /// # Errors
    ///
    /// [`GhosttyError::OutOfMemory`] if the allocation fails,
    /// [`GhosttyError::NullHandle`] if the library reports success without a
    /// handle.
    pub fn new() -> Result<Self> {
        Self::with_allocator(Allocator::default())
    }

    /// Allocate a key encoder using a specific allocator.
    ///
    /// # Errors
    ///
    /// As [`KeyEncoder::new`].
    pub fn with_allocator(allocator: Allocator) -> Result<Self> {
        let mut raw: ffi::GhosttyKeyEncoder = ptr::null_mut();
        // SAFETY: `allocator.as_ptr()` is NULL or a live allocator, and `&mut raw`
        // is a valid out-parameter.
        let code = unsafe { ffi::ghostty_key_encoder_new(allocator.as_ptr(), &mut raw) };
        GhosttyError::from_result(code)?;
        if raw.is_null() {
            return Err(GhosttyError::NullHandle);
        }
        Ok(KeyEncoder {
            raw,
            _not_thread_safe: PhantomData,
        })
    }

    /// Copy the encoder options implied by `terminal`'s current modes.
    ///
    /// This is how cursor-key application mode, the Kitty keyboard flags, and the
    /// rest reach the encoder. The C call returns `void` and reports nothing, so a
    /// stale terminal simply yields default options.
    pub fn sync_from_terminal(&mut self, terminal: &Terminal) {
        // SAFETY: `self.raw` is live and `terminal.as_raw()` is live for this call.
        unsafe { ffi::ghostty_key_encoder_setopt_from_terminal(self.raw, terminal.as_raw()) };
    }

    /// Set whether cursor keys use application mode (DEC mode 1).
    pub fn set_cursor_key_application(&mut self, enabled: bool) {
        self.set_bool(ffi::GHOSTTY_KEY_ENCODER_OPT_CURSOR_KEY_APPLICATION, enabled);
    }

    /// Set whether the keypad uses application mode.
    pub fn set_keypad_key_application(&mut self, enabled: bool) {
        self.set_bool(ffi::GHOSTTY_KEY_ENCODER_OPT_KEYPAD_KEY_APPLICATION, enabled);
    }

    /// Set whether the keypad is ignored while Num Lock is on.
    pub fn set_ignore_keypad_with_numlock(&mut self, ignore: bool) {
        self.set_bool(
            ffi::GHOSTTY_KEY_ENCODER_OPT_IGNORE_KEYPAD_WITH_NUMLOCK,
            ignore,
        );
    }

    /// Set whether Alt emits an ESC prefix.
    pub fn set_alt_esc_prefix(&mut self, enabled: bool) {
        self.set_bool(ffi::GHOSTTY_KEY_ENCODER_OPT_ALT_ESC_PREFIX, enabled);
    }

    /// Set whether `modifyOtherKeys` state 2 is reported.
    pub fn set_modify_other_keys_state_2(&mut self, enabled: bool) {
        self.set_bool(
            ffi::GHOSTTY_KEY_ENCODER_OPT_MODIFY_OTHER_KEYS_STATE_2,
            enabled,
        );
    }

    /// Set the Kitty keyboard protocol flags bitmask.
    pub fn set_kitty_flags(&mut self, flags: u8) {
        // SAFETY: `self.raw` is live; the option's value is a
        // `GhosttyKittyKeyFlags`, which is a `uint8_t`.
        unsafe {
            ffi::ghostty_key_encoder_setopt(
                self.raw,
                ffi::GHOSTTY_KEY_ENCODER_OPT_KITTY_FLAGS,
                (&flags as *const u8).cast::<c_void>(),
            );
        }
    }

    /// Set how the macOS Option key is treated.
    pub fn set_option_as_alt(&mut self, setting: OptionAsAlt) {
        let value = setting.to_raw();
        // SAFETY: `self.raw` is live and `value` matches the option's documented
        // `GhosttyOptionAsAlt` type.
        unsafe {
            ffi::ghostty_key_encoder_setopt(
                self.raw,
                ffi::GHOSTTY_KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT,
                (&value as *const ffi::GhosttyOptionAsAlt).cast::<c_void>(),
            );
        }
    }

    /// Set whether the backarrow key sends Backspace or Delete.
    pub fn set_backarrow_key_mode(&mut self, enabled: bool) {
        self.set_bool(ffi::GHOSTTY_KEY_ENCODER_OPT_BACKARROW_KEY_MODE, enabled);
    }

    /// Encode `event` into the sequence this terminal expects.
    ///
    /// Uses the documented two-pass buffer protocol: a null buffer with zero
    /// capacity asks for the required length, then a correctly sized buffer
    /// receives the bytes. The result is truncated to the number of bytes the
    /// library reports, so uninitialised tail bytes can never reach safe code.
    ///
    /// # Errors
    ///
    /// Anything other than the expected `OUT_OF_SPACE` size query.
    pub fn encode(&self, event: &KeyEvent) -> Result<Vec<u8>> {
        crate::sys::encode_with_buffer(|buf, cap, written| {
            // SAFETY: `self.raw` and `event.raw` are live; `buf`/`cap` are the
            // caller's buffer (NULL/0 is the documented size query) and `written`
            // is a valid out-parameter. The C parameter is `char*`, which is the
            // same size and alignment as `u8`.
            unsafe {
                ffi::ghostty_key_encoder_encode(self.raw, event.raw, buf.cast(), cap, written)
            }
        })
    }

    /// Raw handle, for passing to sibling C APIs.
    pub fn as_raw(&self) -> ffi::GhosttyKeyEncoder {
        self.raw
    }

    fn set_bool(&mut self, option: ffi::GhosttyKeyEncoderOption, value: bool) {
        let value = u8::from(value);
        // SAFETY: `self.raw` is live and the option's documented value type is
        // `bool`, which is one byte.
        unsafe {
            ffi::ghostty_key_encoder_setopt(
                self.raw,
                option,
                (&value as *const u8).cast::<c_void>(),
            );
        }
    }
}

impl Drop for KeyEncoder {
    fn drop(&mut self) {
        if self.raw.is_null() {
            return;
        }
        // SAFETY: `self.raw` is a live handle owned solely by `self`.
        unsafe { ffi::ghostty_key_encoder_free(self.raw) };
        self.raw = ptr::null_mut();
    }
}
