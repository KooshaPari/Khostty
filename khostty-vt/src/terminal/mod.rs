//! RAII wrapper around `GhosttyTerminal`, the emulator state machine.
//!
//! [`Terminal`] owns a `libghostty-vt` terminal and frees it in `Drop`. VT
//! bytes go in through [`Terminal::vt_write`], terminal state comes out through
//! the typed query methods in [`query`], and terminal-initiated events (this
//! library calls them "effects") are delivered to Rust closures registered with
//! [`Terminal::set_write_pty`] and [`Terminal::set_bell`].
//!
//! # Thread safety
//!
//! `Terminal` is deliberately neither `Send` nor `Sync`. The upstream headers
//! document no locking or thread-affinity guarantees, and several APIs
//! (`ghostty_search_new`, `ghostty_render_state_update`,
//! `ghostty_key_encoder_setopt_from_terminal`) borrow a terminal while operating
//! on it, so concurrent use would be unsound by construction. A caller that
//! needs cross-thread work should own the terminal on one thread and move data,
//! not the handle.
//!
//! # Effects and reentrancy
//!
//! Upstream requires that effect callbacks never re-enter
//! `ghostty_terminal_vt_write` on the same terminal, and that they never
//! unwind into C. Both are handled here: callbacks receive `&[u8]` rather than a
//! handle, so re-entering is not expressible, and a panic is caught at the FFI
//! boundary and discarded.
//!
//! # Layout
//!
//! | Module        | Contents                                            |
//! |---------------|-----------------------------------------------------|
//! | `mod` (here)  | Lifecycle, effects, private plumbing, `Drop`        |
//! | [`types`]     | `Screen`, `CursorStyle`, `Viewport`, `Scrollbar`, ... |
//! | [`query`]     | Read accessors over `ghostty_terminal_get`          |
//! | [`set`]       | Option setters over `ghostty_terminal_set`          |

pub mod query;
pub mod set;
pub mod types;

pub use types::{CompressionMode, CompressionResult, CursorStyle, Screen, Scrollbar, Viewport};

use crate::error::{GhosttyError, Result};
use crate::ffi;
use crate::sys::Allocator;
use core::cell::{Cell, RefCell};
use core::ffi::c_void;
use core::marker::PhantomData;
use core::ptr;

/// Registered `write_pty` closure, boxed and interior-mutable so the FFI
/// trampoline can reach it without holding a `&mut Terminal`.
type WritePtySlot = RefCell<Box<dyn FnMut(&[u8]) + 'static>>;

/// Registered `bell` closure plus the count of bells observed.
struct BellSlot {
    callback: RefCell<Box<dyn FnMut() + 'static>>,
    count: Cell<u64>,
}

/// A `libghostty-vt` terminal.
///
/// Dropping this value calls `ghostty_terminal_free`, which invalidates every
/// borrowed handle derived from it, such as a search, render state, or grid
/// reference.
pub struct Terminal {
    /// The owned C handle.
    raw: ffi::GhosttyTerminal,
    /// Keeps the registered `write_pty` closure alive and gives it a stable
    /// address to hand upstream as userdata.
    write_pty: Option<Box<WritePtySlot>>,
    /// Keeps the registered `bell` closure and its counter alive.
    bell: Option<Box<BellSlot>>,
    /// `GhosttyTerminal` has no documented thread-safety, so opt out of the
    /// auto traits rather than silently claiming them.
    _not_thread_safe: PhantomData<*mut ()>,
}

impl Terminal {
    /// Create a terminal with `cols` columns and `rows` rows.
    ///
    /// # Errors
    ///
    /// [`GhosttyError::OutOfMemory`] if the internal allocation fails, or
    /// [`GhosttyError::NullHandle`] if the library reports success without
    /// producing a handle.
    pub fn new(cols: u16, rows: u16) -> Result<Self> {
        Self::with_allocator(Allocator::default(), cols, rows)
    }

    /// Create a terminal using a specific allocator.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_terminal_new` reports, typically
    /// [`GhosttyError::OutOfMemory`]; [`GhosttyError::NullHandle`] if it
    /// reports success without a handle.
    pub fn with_allocator(allocator: Allocator, cols: u16, rows: u16) -> Result<Self> {
        let mut raw: ffi::GhosttyTerminal = ptr::null_mut();
        // SAFETY: `allocator.as_ptr()` is either NULL (the documented default)
        // or points at an allocator that outlives this call with a complete
        // vtable. `&mut raw` is a valid out-parameter for the handle.
        let code = unsafe { ffi::ghostty_terminal_new(allocator.as_ptr(), &mut raw, cols, rows) };
        GhosttyError::from_result(code)?;
        if raw.is_null() {
            return Err(GhosttyError::NullHandle);
        }
        Ok(Terminal {
            raw,
            write_pty: None,
            bell: None,
            _not_thread_safe: PhantomData,
        })
    }

    /// Take ownership of a terminal handle produced by the library.
    ///
    /// Used by [`crate::snapshot`], where `ghostty_snapshot_decoder_ready` and
    /// `ghostty_snapshot_decoder_decode` hand back a *caller-owned* terminal.
    ///
    /// The handle must be non-null, be owned by nobody else, and never be freed
    /// by another path: the returned `Terminal` frees it in `Drop`.
    pub(crate) fn from_owned_raw(raw: ffi::GhosttyTerminal) -> Result<Self> {
        if raw.is_null() {
            return Err(GhosttyError::NullHandle);
        }
        Ok(Terminal {
            raw,
            write_pty: None,
            bell: None,
            _not_thread_safe: PhantomData,
        })
    }

    /// The raw handle, for handing to sibling APIs that borrow a terminal.
    ///
    /// This is the escape hatch used by [`crate::render`], [`crate::search`],
    /// [`crate::snapshot`] and [`crate::key`]. Reading it is safe; the borrow
    /// checker cannot see through it, so callers must not retain anything
    /// derived from it across a mutating call on this terminal.
    pub fn as_raw(&self) -> ffi::GhosttyTerminal {
        self.raw
    }

    /// Feed VT-encoded bytes into the parser.
    ///
    /// This is the hot path. It cannot fail: `ghostty_terminal_vt_write`
    /// returns `void`. Effect callbacks fire synchronously inside this call, on
    /// the calling thread.
    pub fn vt_write(&mut self, bytes: &[u8]) {
        if bytes.is_empty() {
            return;
        }
        // SAFETY: `self.raw` is live for the lifetime of `self`, and `bytes`
        // describes a readable region that outlives the call.
        unsafe { ffi::ghostty_terminal_vt_write(self.raw, bytes.as_ptr(), bytes.len()) };
    }

    /// Feed bytes until the parser returns to ground state.
    ///
    /// Returns the number of bytes consumed, which is what a caller needs to
    /// resume from a partial escape sequence. Prefer [`Terminal::vt_write`];
    /// this exists for callers that must stop at a sequence boundary.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_terminal_vt_write_until_ground` reports.
    pub fn vt_write_until_ground(&mut self, bytes: &[u8]) -> Result<usize> {
        let mut consumed: usize = 0;
        // SAFETY: `self.raw` is live; `bytes` is readable for the call; and
        // `&mut consumed` is a valid out-parameter.
        let code = unsafe {
            ffi::ghostty_terminal_vt_write_until_ground(
                self.raw,
                bytes.as_ptr(),
                bytes.len(),
                &mut consumed,
            )
        };
        GhosttyError::from_result(code)?;
        Ok(consumed)
    }

    /// Resize the terminal, optionally updating the pixel size.
    ///
    /// Line wrapping and scrollback reflow happen inside this call.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_terminal_resize` reports.
    pub fn resize(
        &mut self,
        cols: u16,
        rows: u16,
        cell_width_px: u32,
        cell_height_px: u32,
    ) -> Result<()> {
        // SAFETY: `self.raw` is live for the duration of the call.
        let code = unsafe {
            ffi::ghostty_terminal_resize(self.raw, cols, rows, cell_width_px, cell_height_px)
        };
        GhosttyError::from_result(code)
    }

    /// Reset the terminal to its initial state.
    ///
    /// Clears the screen, scrollback, and modes. Registered effects stay
    /// registered, which matches the C contract.
    pub fn reset(&mut self) {
        // SAFETY: `self.raw` is live. The function returns `void` and borrows
        // nothing from the caller.
        unsafe { ffi::ghostty_terminal_reset(self.raw) };
    }

    /// Run one scrollback compression pass.
    ///
    /// Compression is caller-driven: libghostty-vt never creates a timer or a
    /// background thread. Pair this with
    /// [`Terminal::compression_activity`], restarting an idle timer whenever the
    /// token changes, and call repeatedly while the result is
    /// [`CompressionResult::Pending`].
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_terminal_compress` reports.
    pub fn compress(&mut self, mode: CompressionMode) -> Result<CompressionResult> {
        let mut out: ffi::GhosttyTerminalCompressionResult = 0;
        // SAFETY: `self.raw` is live and `&mut out` is a valid out-parameter for
        // a `GhosttyTerminalCompressionResult`.
        let code = unsafe { ffi::ghostty_terminal_compress(self.raw, mode.to_raw(), &mut out) };
        GhosttyError::from_result(code)?;
        Ok(CompressionResult::from_raw(out))
    }

    /// Move the viewport.
    pub fn scroll_viewport(&mut self, behavior: Viewport) {
        // SAFETY: `self.raw` is live; the behavior struct is passed by value and
        // copied by the callee.
        unsafe { ffi::ghostty_terminal_scroll_viewport(self.raw, behavior.to_raw()) };
    }

    // ---- Effects -----------------------------------------------------------

    /// Register a callback for bytes the terminal wants written to the pty.
    ///
    /// This is how a query response (`DA`, `DSR`, `DECRQM`, ...) leaves the
    /// emulator and reaches the program under it. Passing `None` unregisters the
    /// effect and drops the closure.
    ///
    /// The closure runs synchronously inside [`Terminal::vt_write`] or
    /// [`Terminal::vt_write_until_ground`], on the calling thread, so it must
    /// not block for long. A panic inside it is caught at the FFI boundary and
    /// discarded. If the closure somehow re-enters this terminal's writes, the
    /// reentrant write is dropped instead of aliasing the closure.
    pub fn set_write_pty<F>(&mut self, callback: Option<F>)
    where
        F: FnMut(&[u8]) + 'static,
    {
        // Unregister before dropping the old closure so the library can never
        // reach storage that is being torn down.
        self.clear_effect(ffi::GHOSTTY_TERMINAL_OPT_WRITE_PTY);
        self.write_pty = None;

        let Some(callback) = callback else {
            return;
        };

        let slot: Box<WritePtySlot> = Box::new(RefCell::new(Box::new(callback)));
        // `Box` gives the slot a stable address, so moving the `Option` that
        // owns it never invalidates the userdata pointer.
        let userdata = (&*slot as *const WritePtySlot).cast_mut().cast::<c_void>();
        self.set_userdata(userdata);
        self.write_pty = Some(slot);
        // SAFETY: the effect options take the function pointer itself, passed as
        // a data pointer, which is the upstream calling convention; see
        // example/c-vt-effects/src/main.c.
        unsafe {
            ffi::ghostty_terminal_set(
                self.raw,
                ffi::GHOSTTY_TERMINAL_OPT_WRITE_PTY,
                write_pty_trampoline as *const c_void,
            );
        }
    }

    /// Register a callback invoked when the program rings the bell (`BEL`).
    ///
    /// Passing `None` unregisters the effect, drops the closure, and resets the
    /// counter reported by [`Terminal::bell_count`].
    pub fn set_bell<F>(&mut self, callback: Option<F>)
    where
        F: FnMut() + 'static,
    {
        self.clear_effect(ffi::GHOSTTY_TERMINAL_OPT_BELL);
        self.bell = None;

        let Some(callback) = callback else {
            return;
        };

        let slot: Box<BellSlot> = Box::new(BellSlot {
            callback: RefCell::new(Box::new(callback)),
            count: Cell::new(0),
        });
        let userdata = (&*slot as *const BellSlot).cast_mut().cast::<c_void>();
        self.set_userdata(userdata);
        self.bell = Some(slot);
        // SAFETY: as in `set_write_pty`.
        unsafe {
            ffi::ghostty_terminal_set(
                self.raw,
                ffi::GHOSTTY_TERMINAL_OPT_BELL,
                bell_trampoline as *const c_void,
            );
        }
    }

    /// Number of bells observed since the bell effect was registered.
    ///
    /// Returns `0` when no bell callback is registered.
    pub fn bell_count(&self) -> u64 {
        self.bell.as_ref().map_or(0, |slot| slot.count.get())
    }

    // ---- Private plumbing --------------------------------------------------

    /// Clear a callback effect by passing a null value pointer, which is the
    /// documented "disable the effect" spelling.
    pub(super) fn clear_effect(&mut self, option: ffi::GhosttyTerminalOption) {
        // SAFETY: `self.raw` is live and NULL is explicitly documented as the
        // way to clear an effect callback.
        unsafe { ffi::ghostty_terminal_set(self.raw, option, ptr::null()) };
    }

    /// Store the pointer passed to every effect callback.
    pub(super) fn set_userdata(&mut self, userdata: *mut c_void) {
        // SAFETY: `self.raw` is live; the option stores the pointer value and
        // does not dereference it.
        unsafe {
            ffi::ghostty_terminal_set(self.raw, ffi::GHOSTTY_TERMINAL_OPT_USERDATA, userdata)
        };
    }
}

impl Drop for Terminal {
    fn drop(&mut self) {
        // Unregister every effect first so the library cannot reach a closure
        // whose storage is about to be freed.
        for option in [
            ffi::GHOSTTY_TERMINAL_OPT_WRITE_PTY,
            ffi::GHOSTTY_TERMINAL_OPT_BELL,
            ffi::GHOSTTY_TERMINAL_OPT_USERDATA,
        ] {
            // SAFETY: `self.raw` is still live at this point.
            unsafe { ffi::ghostty_terminal_set(self.raw, option, ptr::null()) };
        }
        // SAFETY: `self.raw` is a live handle owned solely by `self`, and this
        // is the only place it is freed.
        unsafe { ffi::ghostty_terminal_free(self.raw) };
        self.raw = ptr::null_mut();
    }
}

/// Forwards terminal-initiated output to the registered Rust closure.
///
/// # Safety
///
/// Called only by libghostty-vt, with the `userdata` set by
/// [`Terminal::set_write_pty`] and `data`/`len` describing a borrowed byte range
/// that is valid for the duration of the call.
unsafe extern "C" fn write_pty_trampoline(
    _terminal: ffi::GhosttyTerminal,
    userdata: *mut c_void,
    data: *const u8,
    len: usize,
) {
    if userdata.is_null() || (data.is_null() && len > 0) {
        return;
    }
    // A panic must not unwind into C. The closure is reached through a
    // `RefCell`, so a reentrant call is dropped rather than panicking.
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        // SAFETY: `userdata` points at the `WritePtySlot` owned by the live
        // `Terminal`; the address is stable because the slot is boxed, and the
        // effect is unregistered before that storage is dropped.
        let slot = unsafe { &*(userdata as *const WritePtySlot) };
        let Ok(mut callback) = slot.try_borrow_mut() else {
            return;
        };
        let bytes = if len == 0 {
            &[][..]
        } else {
            // SAFETY: `data`/`len` describe a readable region for this call.
            unsafe { core::slice::from_raw_parts(data, len) }
        };
        callback(bytes);
    }));
}

/// Counts bells and forwards them to the registered Rust closure.
///
/// # Safety
///
/// Called only by libghostty-vt, with the `userdata` set by
/// [`Terminal::set_bell`].
unsafe extern "C" fn bell_trampoline(_terminal: ffi::GhosttyTerminal, userdata: *mut c_void) {
    if userdata.is_null() {
        return;
    }
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        // SAFETY: `userdata` points at the `BellSlot` owned by the live
        // `Terminal`, with the same stability argument as `write_pty`.
        let slot = unsafe { &*(userdata as *const BellSlot) };
        slot.count.set(slot.count.get().saturating_add(1));
        if let Ok(mut callback) = slot.callback.try_borrow_mut() {
            callback();
        }
    }));
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Compile-time check that `Terminal` is neither `Send` nor `Sync`.
    ///
    /// The technique is the standard ambiguity trick: if `Terminal` did
    /// implement `Send`, both blanket impls below would apply and the
    /// fully-qualified call would be ambiguous, which is a compile error. It
    /// replaces `static_assertions::assert_not_impl_any!` without adding a
    /// dependency.
    mod not_send_assertion {
        pub trait AmbiguousIfSend<A> {
            fn some_item() {}
        }
        impl<T: ?Sized> AmbiguousIfSend<()> for T {}
        impl<T: ?Sized + Send> AmbiguousIfSend<u8> for T {}
    }

    mod not_sync_assertion {
        pub trait AmbiguousIfSync<A> {
            fn some_item() {}
        }
        impl<T: ?Sized> AmbiguousIfSync<()> for T {}
        impl<T: ?Sized + Sync> AmbiguousIfSync<u8> for T {}
    }

    #[test]
    fn terminal_is_neither_send_nor_sync() {
        // These two lines fail to compile if `Terminal` gains `Send` or `Sync`.
        let _ = <Terminal as not_send_assertion::AmbiguousIfSend<()>>::some_item;
        let _ = <Terminal as not_sync_assertion::AmbiguousIfSync<()>>::some_item;
    }
}
