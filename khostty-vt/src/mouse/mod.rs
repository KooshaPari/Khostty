//! Mouse event encoding.
//!
//! [`MouseEncoder`] mirrors `GhosttyMouseEncoder`. Both a [`MouseEvent`] and the
//! encoder are owned handles, kept separate for the same reason as the key
//! encoder: one event can be reused across encodes by mutating it, and the
//! encoder holds the terminal-derived settings that decide how the event is
//! written.
//!
//! # Why the encoder needs geometry
//!
//! A mouse event carries a *surface* position in pixels, while the wire format
//! mostly carries *cell* coordinates. The encoder therefore needs the cell size
//! and padding, passed through
//! [`MouseEncoder::set_size`] as a [`MouseEncoderSize`], and
//! [`MouseEncoder::sync_from_terminal`] picks up the tracking mode and format the
//! program enabled. A missing or zero cell size makes pixel-derived formats
//! meaningless, so it is a plain requirement rather than something this wrapper
//! can infer.

pub mod types;

pub use types::{
    MouseAction, MouseButton, MouseEncoderSize, MouseFormat, MousePosition, MouseTrackingMode,
};

use crate::error::{GhosttyError, Result};
use crate::ffi;
use crate::key::Mods;
use crate::sys::Allocator;
use crate::terminal::Terminal;
use core::ffi::c_void;
use core::marker::PhantomData;
use core::ptr;

/// One mouse event.
///
/// Owns a `GhosttyMouseEvent` and frees it in `Drop`. Reusable across encodes.
pub struct MouseEvent {
    raw: ffi::GhosttyMouseEvent,
    _not_thread_safe: PhantomData<*mut ()>,
}

impl MouseEvent {
    /// Allocate a mouse event.
    ///
    /// # Errors
    ///
    /// [`GhosttyError::OutOfMemory`] if the allocation fails,
    /// [`GhosttyError::NullHandle`] if the library reports success without a
    /// handle.
    pub fn new() -> Result<Self> {
        let mut raw: ffi::GhosttyMouseEvent = ptr::null_mut();
        // SAFETY: NULL selects the library's default allocator and `&mut raw` is a
        // valid out-parameter.
        let code = unsafe { ffi::ghostty_mouse_event_new(ptr::null(), &mut raw) };
        GhosttyError::from_result(code)?;
        if raw.is_null() {
            return Err(GhosttyError::NullHandle);
        }
        Ok(MouseEvent {
            raw,
            _not_thread_safe: PhantomData,
        })
    }

    /// Set what the user did.
    pub fn set_action(&mut self, action: MouseAction) {
        // SAFETY: `self.raw` is live; the value is a plain int.
        unsafe { ffi::ghostty_mouse_event_set_action(self.raw, action.to_raw()) };
    }

    /// What the user did.
    pub fn action(&self) -> MouseAction {
        // SAFETY: `self.raw` is live.
        MouseAction::from_raw(unsafe { ffi::ghostty_mouse_event_get_action(self.raw) })
    }

    /// Set which button.
    pub fn set_button(&mut self, button: MouseButton) {
        // SAFETY: `self.raw` is live; the value is a plain int.
        unsafe { ffi::ghostty_mouse_event_set_button(self.raw, button.to_raw()) };
    }

    /// Clear the button, as a motion event outside any button press requires.
    pub fn clear_button(&mut self) {
        // SAFETY: `self.raw` is live.
        unsafe { ffi::ghostty_mouse_event_clear_button(self.raw) };
    }

    /// The button, if one is set.
    ///
    /// Returns `Ok(None)` when no button is set, which is the normal state for
    /// motion without a held button.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_mouse_event_get_button` reports other than the unset
    /// case.
    pub fn button(&self) -> Result<Option<MouseButton>> {
        let mut raw: ffi::GhosttyMouseButton = ffi::GHOSTTY_MOUSE_BUTTON_UNKNOWN;
        // SAFETY: `self.raw` is live and `&mut raw` is a valid out-parameter.
        let has_button = unsafe { ffi::ghostty_mouse_event_get_button(self.raw, &mut raw) };
        if !has_button {
            return Ok(None);
        }
        Ok(Some(MouseButton::from_raw(raw)))
    }

    /// Set the modifiers held for this event.
    pub fn set_mods(&mut self, mods: Mods) {
        // SAFETY: `self.raw` is live; the value is a plain integer.
        unsafe { ffi::ghostty_mouse_event_set_mods(self.raw, mods.bits()) };
    }

    /// The modifiers held for this event.
    pub fn mods(&self) -> Mods {
        // SAFETY: `self.raw` is live.
        Mods(unsafe { ffi::ghostty_mouse_event_get_mods(self.raw) })
    }

    /// Set the surface position in pixels.
    pub fn set_position(&mut self, position: MousePosition) {
        // SAFETY: `self.raw` is live; the value is a POD struct passed by value.
        unsafe { ffi::ghostty_mouse_event_set_position(self.raw, position.to_ffi()) };
    }

    /// The surface position in pixels.
    pub fn position(&self) -> MousePosition {
        // SAFETY: `self.raw` is live; the function returns a POD struct by value.
        MousePosition::from_ffi(unsafe { ffi::ghostty_mouse_event_get_position(self.raw) })
    }

    /// Raw handle, for passing to sibling C APIs.
    pub fn as_raw(&self) -> ffi::GhosttyMouseEvent {
        self.raw
    }
}

impl Drop for MouseEvent {
    fn drop(&mut self) {
        if self.raw.is_null() {
            return;
        }
        // SAFETY: `self.raw` is a live handle owned solely by `self`.
        unsafe { ffi::ghostty_mouse_event_free(self.raw) };
        self.raw = ptr::null_mut();
    }
}

/// Encodes mouse events into terminal escape sequences.
///
/// Dropping this value calls `ghostty_mouse_encoder_free`.
pub struct MouseEncoder {
    raw: ffi::GhosttyMouseEncoder,
    _not_thread_safe: PhantomData<*mut ()>,
}

impl MouseEncoder {
    /// Allocate a mouse encoder.
    ///
    /// # Errors
    ///
    /// [`GhosttyError::OutOfMemory`] if the allocation fails,
    /// [`GhosttyError::NullHandle`] if the library reports success without a
    /// handle.
    pub fn new() -> Result<Self> {
        Self::with_allocator(Allocator::default())
    }

    /// Allocate a mouse encoder using a specific allocator.
    ///
    /// # Errors
    ///
    /// As [`MouseEncoder::new`].
    pub fn with_allocator(allocator: Allocator) -> Result<Self> {
        let mut raw: ffi::GhosttyMouseEncoder = ptr::null_mut();
        // SAFETY: `allocator.as_ptr()` is NULL or a live allocator, and `&mut raw`
        // is a valid out-parameter.
        let code = unsafe { ffi::ghostty_mouse_encoder_new(allocator.as_ptr(), &mut raw) };
        GhosttyError::from_result(code)?;
        if raw.is_null() {
            return Err(GhosttyError::NullHandle);
        }
        Ok(MouseEncoder {
            raw,
            _not_thread_safe: PhantomData,
        })
    }

    /// Copy the tracking mode and output format implied by `terminal`'s modes.
    ///
    /// This is how the DECSET mouse modes the program enabled reach the encoder.
    /// The C call returns `void`, so a terminal that enabled nothing yields the
    /// default options.
    pub fn sync_from_terminal(&mut self, terminal: &Terminal) {
        // SAFETY: `self.raw` is live and `terminal.as_raw()` is live for this call.
        unsafe { ffi::ghostty_mouse_encoder_setopt_from_terminal(self.raw, terminal.as_raw()) };
    }

    /// Set the tracking mode directly, instead of deriving it from a terminal.
    pub fn set_tracking_mode(&mut self, mode: MouseTrackingMode) {
        let value = mode.to_raw();
        // SAFETY: `self.raw` is live and `value` matches the option's documented
        // `GhosttyMouseTrackingMode` type.
        unsafe {
            ffi::ghostty_mouse_encoder_setopt(
                self.raw,
                ffi::GHOSTTY_MOUSE_ENCODER_OPT_EVENT,
                (&value as *const ffi::GhosttyMouseTrackingMode).cast::<c_void>(),
            );
        }
    }

    /// Set the output format directly.
    pub fn set_format(&mut self, format: MouseFormat) {
        let value = format.to_raw();
        // SAFETY: `self.raw` is live and `value` matches the option's documented
        // `GhosttyMouseFormat` type.
        unsafe {
            ffi::ghostty_mouse_encoder_setopt(
                self.raw,
                ffi::GHOSTTY_MOUSE_ENCODER_OPT_FORMAT,
                (&value as *const ffi::GhosttyMouseFormat).cast::<c_void>(),
            );
        }
    }

    /// Set the renderer geometry used to map pixels to cells.
    pub fn set_size(&mut self, size: MouseEncoderSize) {
        let value = size.to_ffi();
        // SAFETY: `self.raw` is live and `value` is a sized
        // `GhosttyMouseEncoderSize`, the option's documented type.
        unsafe {
            ffi::ghostty_mouse_encoder_setopt(
                self.raw,
                ffi::GHOSTTY_MOUSE_ENCODER_OPT_SIZE,
                (&value as *const ffi::GhosttyMouseEncoderSize).cast::<c_void>(),
            );
        }
    }

    /// Tell the encoder whether any button is currently held.
    ///
    /// Observed behaviour, from probing the linked library across every format
    /// (X10, UTF-8, SGR, URXVT, SGR-pixels) with button, empty-motion, and drag
    /// events: this flag does not change the encoded bytes. Whether motion is
    /// reported at all is decided by the tracking mode, not by this flag. The
    /// setter is exposed because it is part of the C API and because a future
    /// library revision may give it effect; nothing in this crate depends on it.
    pub fn set_any_button_pressed(&mut self, pressed: bool) {
        self.set_bool(ffi::GHOSTTY_MOUSE_ENCODER_OPT_ANY_BUTTON_PRESSED, pressed);
    }

    /// Set whether motion is deduplicated by last cell.
    pub fn set_track_last_cell(&mut self, track: bool) {
        self.set_bool(ffi::GHOSTTY_MOUSE_ENCODER_OPT_TRACK_LAST_CELL, track);
    }

    /// Reset encoder state that persists between events.
    ///
    /// Used when tracking is restarted, for example after the program toggles a
    /// mouse mode off and on, so stale motion-deduplication state does not
    /// suppress the next report.
    pub fn reset(&mut self) {
        // SAFETY: `self.raw` is live.
        unsafe { ffi::ghostty_mouse_encoder_reset(self.raw) };
    }

    /// Encode `event` into the sequence this terminal expects.
    ///
    /// Uses the documented two-pass buffer protocol: a null buffer with zero
    /// capacity asks for the required length, then a correctly sized buffer
    /// receives the bytes.
    ///
    /// # Errors
    ///
    /// Anything other than the expected `OUT_OF_SPACE` size query.
    pub fn encode(&self, event: &MouseEvent) -> Result<Vec<u8>> {
        crate::sys::encode_with_buffer(|buf, cap, written| {
            // SAFETY: `self.raw` and `event.raw` are live; `buf`/`cap` are the
            // caller's buffer (NULL/0 is the documented size query) and `written`
            // is a valid out-parameter. The C parameter is `char*`, the same size
            // and alignment as `u8`.
            unsafe {
                ffi::ghostty_mouse_encoder_encode(self.raw, event.raw, buf.cast(), cap, written)
            }
        })
    }

    /// Raw handle, for passing to sibling C APIs.
    pub fn as_raw(&self) -> ffi::GhosttyMouseEncoder {
        self.raw
    }

    fn set_bool(&mut self, option: ffi::GhosttyMouseEncoderOption, value: bool) {
        let value = u8::from(value);
        // SAFETY: `self.raw` is live and the option's documented value type is
        // `bool`, one byte.
        unsafe {
            ffi::ghostty_mouse_encoder_setopt(
                self.raw,
                option,
                (&value as *const u8).cast::<c_void>(),
            );
        }
    }
}

impl Drop for MouseEncoder {
    fn drop(&mut self) {
        if self.raw.is_null() {
            return;
        }
        // SAFETY: `self.raw` is a live handle owned solely by `self`.
        unsafe { ffi::ghostty_mouse_encoder_free(self.raw) };
        self.raw = ptr::null_mut();
    }
}
