//! Snapshot encoding and decoding.
//!
//! A snapshot is a byte string capturing a terminal's persistent VT stream, its
//! scrollback history pages, and the parser continuation needed to resume
//! mid-sequence. [`encode`] produces one and [`SnapshotDecoder`] restores it;
//! encoding lives in [`encode`] (the submodule) and decoding here.
//!
//! The C API splits restoration into two shapes, and this module mirrors both:
//!
//! * **Incremental.** [`SnapshotDecoder::ready`] restores the renderable prefix
//!   and hands back a terminal that is immediately usable for rendering and live
//!   input, then [`ReadyTerminal::next_page`] drains history one page at a time.
//!   This is the shape an embedding terminal wants: it can paint after `ready`
//!   and reflow as history lands.
//! * **One-shot.** [`SnapshotDecoder::decode`] restores everything in one call
//!   and consumes the decoder. This is the shape an agent tool wants.
//!
//! # Lifetime rules this module enforces
//!
//! Three upstream rules are easy to get wrong by hand and are encoded in the
//! types here:
//!
//! 1. `ghostty_snapshot_decoder_new_buf` does **not** copy the source bytes: they
//!    must stay valid and immutable until FINISH or until the decoder is freed.
//!    [`SnapshotDecoder`] therefore borrows its source, or owns it, which is
//!    equally stable.
//! 2. The terminal produced by READY must stay alive until FINISH validates or
//!    the decoder is freed. [`ReadyTerminal`] owns the terminal *and* holds the
//!    mutable borrow of the decoder, so the borrow checker enforces the order.
//! 3. `ghostty_snapshot_decoder_decode` may only be called before decoding
//!    starts, and one-shot decoding validates FINISH itself. It consumes the
//!    decoder, which makes "call decode after ready" impossible to write.

pub mod encode;

pub use encode::{encode, encode_alloc, encode_to};

use crate::error::{GhosttyError, Result};
use crate::ffi;
use crate::sys::Allocator;
use crate::terminal::{Screen, Terminal};
use core::ffi::c_void;
use core::marker::PhantomData;
use core::ptr;
use std::borrow::Cow;
// ---------------------------------------------------------------------------
// Decoding
// ---------------------------------------------------------------------------

/// Geometry recovered by the most recent incremental step.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct DecoderProgress {
    /// Offset into the source buffer after the bytes consumed so far.
    ///
    /// Use it to find data the snapshot left unread, which is how trailing
    /// bytes past FINISH are located.
    pub source_offset: usize,
    /// History rows restored for the primary screen.
    pub history_rows_primary: u64,
    /// History rows restored for the alternate screen.
    pub history_rows_alternate: u64,
    /// Screen the most recently decoded history page belonged to.
    pub page_screen: Option<Screen>,
    /// Rows prepended by the most recent history page.
    ///
    /// Zero means the page was consumed and validated but could not be applied
    /// to the live terminal, for example because the terminal was resized such
    /// that the page no longer fits.
    pub page_rows: usize,
    /// Page records remaining in the same screen's history sequence.
    ///
    /// Not a count of every page left in the snapshot.
    pub page_remaining: u32,
    /// Whether continuation tracking is retained on returned terminals.
    pub retain_continuation: bool,
}

/// Incremental snapshot decoder.
///
/// Borrows its source bytes, matching the C contract that they must stay valid
/// and immutable until FINISH is reached or the decoder is freed. Use
/// [`SnapshotDecoder::from_bytes`] for a borrowed slice or
/// [`SnapshotDecoder::from_vec`] to own the bytes.
///
/// Dropping the decoder calls `ghostty_snapshot_decoder_free`, which never
/// releases a terminal the decoder produced: those are caller-owned and are
/// represented here by [`ReadyTerminal`] or returned directly from
/// [`SnapshotDecoder::decode`].
pub struct SnapshotDecoder<'a> {
    raw: ffi::GhosttySnapshotDecoder,
    /// Keeps the source bytes alive and pins the borrow. For the owned variant
    /// the `Vec`'s heap allocation is stable across moves of this struct, so the
    /// pointer handed to C stays valid.
    _source: Cow<'a, [u8]>,
    /// No thread-safety is documented for decoders, for the same reason as
    /// [`Terminal`].
    _not_thread_safe: PhantomData<*mut ()>,
}

impl<'a> SnapshotDecoder<'a> {
    /// Create a decoder over borrowed snapshot bytes.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_snapshot_decoder_new_buf` reports.
    pub fn from_bytes(bytes: &'a [u8]) -> Result<Self> {
        Self::with_source(Cow::Borrowed(bytes), Allocator::default())
    }

    /// Create a decoder that owns its snapshot bytes.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_snapshot_decoder_new_buf` reports.
    pub fn from_vec(bytes: Vec<u8>) -> Result<SnapshotDecoder<'static>> {
        SnapshotDecoder::with_source(Cow::Owned(bytes), Allocator::default())
    }

    /// Create a decoder over borrowed bytes using a specific allocator.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_snapshot_decoder_new_buf` reports.
    pub fn from_bytes_with_allocator(bytes: &'a [u8], allocator: Allocator) -> Result<Self> {
        Self::with_source(Cow::Borrowed(bytes), allocator)
    }

    fn with_source(source: Cow<'a, [u8]>, allocator: Allocator) -> Result<Self> {
        let mut raw: ffi::GhosttySnapshotDecoder = ptr::null_mut();
        // SAFETY: `allocator.as_ptr()` is NULL or a live allocator; the source
        // pointer and length describe the `Cow`'s buffer, which this struct keeps
        // alive for its whole lifetime; `&mut raw` is a valid out-parameter.
        let code = unsafe {
            ffi::ghostty_snapshot_decoder_new_buf(
                allocator.as_ptr(),
                &mut raw,
                source.as_ptr(),
                source.len(),
            )
        };
        GhosttyError::from_result(code)?;
        if raw.is_null() {
            return Err(GhosttyError::NullHandle);
        }
        Ok(SnapshotDecoder {
            raw,
            _source: source,
            _not_thread_safe: PhantomData,
        })
    }

    /// Cap the largest non-ground parser continuation the decoder will accept.
    ///
    /// Zero accepts only snapshots whose VT parser is in ground state. The
    /// upstream default matches the largest built-in APC protocol buffer limit.
    ///
    /// # Errors
    ///
    /// [`GhosttyError::InvalidValue`] if decoding has already started, per the
    /// option-lifecycle contract.
    pub fn set_max_continuation_bytes(&mut self, bytes: usize) -> Result<()> {
        self.set_option(
            ffi::GHOSTTY_SNAPSHOT_DECODER_OPT_MAX_CONTINUATION_BYTES,
            &bytes,
        )
    }

    /// Whether decoded continuation tracking is retained on returned terminals.
    ///
    /// # Errors
    ///
    /// [`GhosttyError::InvalidValue`] if decoding has already started.
    pub fn set_retain_continuation(&mut self, retain: bool) -> Result<()> {
        let value = u8::from(retain);
        self.set_option(
            ffi::GHOSTTY_SNAPSHOT_DECODER_OPT_RETAIN_CONTINUATION,
            &value,
        )
    }

    /// Decode the renderable prefix and return a terminal ready for rendering.
    ///
    /// The returned [`ReadyTerminal`] owns the terminal and borrows this decoder,
    /// which encodes the upstream rule that the terminal must outlive the
    /// decoder's history replay.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_snapshot_decoder_ready` reports.
    pub fn ready(&mut self) -> Result<ReadyTerminal<'_, 'a>> {
        let mut raw: ffi::GhosttyTerminal = ptr::null_mut();
        // SAFETY: `self.raw` is live and `&mut raw` is a valid out-parameter.
        let code = unsafe { ffi::ghostty_snapshot_decoder_ready(self.raw, &mut raw) };
        GhosttyError::from_result(code)?;
        let terminal = Terminal::from_owned_raw(raw)?;
        Ok(ReadyTerminal {
            decoder: self,
            terminal,
        })
    }

    /// Decode and validate one complete snapshot, consuming the decoder.
    ///
    /// This is the one-shot form of `ready` followed by every history page
    /// through FINISH, so the returned terminal needs no further borrow of the
    /// decoder. Consuming `self` makes it impossible to call after `ready`, which
    /// upstream rejects.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_snapshot_decoder_decode` reports.
    pub fn decode(self) -> Result<Terminal> {
        let mut raw: ffi::GhosttyTerminal = ptr::null_mut();
        // SAFETY: `self.raw` is live (this is the only owner) and `&mut raw` is a
        // valid out-parameter. The call validates FINISH itself, after which the
        // decoder no longer borrows the terminal; `self` is freed by `Drop` when
        // this function returns.
        let code = unsafe { ffi::ghostty_snapshot_decoder_decode(self.raw, &mut raw) };
        GhosttyError::from_result(code)?;
        Terminal::from_owned_raw(raw)
    }

    /// Read the decoder's progress counters.
    ///
    /// This never fails for a missing counter: every `PROGRESS_*` value is
    /// documented as available only at particular points in the decode, and
    /// `GHOSTTY_NO_VALUE` simply means "not meaningful right now". Fields whose
    /// query reports `NoValue` keep their [`DecoderProgress::default`] value.
    ///
    /// # Errors
    ///
    /// Only a genuine failure from `ghostty_snapshot_decoder_get`, such as an
    /// invalid argument.
    pub fn progress(&self) -> Result<DecoderProgress> {
        Ok(DecoderProgress {
            source_offset: self.try_usize(ffi::GHOSTTY_SNAPSHOT_DECODER_DATA_SOURCE_OFFSET)?,
            history_rows_primary: self
                .try_u64(ffi::GHOSTTY_SNAPSHOT_DECODER_DATA_HISTORY_ROWS_PRIMARY)?,
            history_rows_alternate: self
                .try_u64(ffi::GHOSTTY_SNAPSHOT_DECODER_DATA_HISTORY_ROWS_ALTERNATE)?,
            page_screen: self
                .try_i32(ffi::GHOSTTY_SNAPSHOT_DECODER_DATA_PROGRESS_SCREEN)?
                .map(Screen::from_raw),
            page_rows: self.try_usize(ffi::GHOSTTY_SNAPSHOT_DECODER_DATA_PROGRESS_ROWS)?,
            page_remaining: self
                .try_u32(ffi::GHOSTTY_SNAPSHOT_DECODER_DATA_PROGRESS_REMAINING)?
                .unwrap_or(0),
            retain_continuation: self
                .try_bool(ffi::GHOSTTY_SNAPSHOT_DECODER_DATA_RETAIN_CONTINUATION)?,
        })
    }

    /// The configured continuation acceptance limit.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_snapshot_decoder_get` reports.
    pub fn max_continuation_bytes(&self) -> Result<usize> {
        self.get_usize(ffi::GHOSTTY_SNAPSHOT_DECODER_DATA_MAX_CONTINUATION_BYTES)
    }

    fn set_option<T>(
        &mut self,
        option: ffi::GhosttySnapshotDecoderOption,
        value: &T,
    ) -> Result<()> {
        // SAFETY: `self.raw` is live and `value` points at a `T` matching the
        // option's documented input type.
        let code = unsafe {
            ffi::ghostty_snapshot_decoder_set(
                self.raw,
                option,
                (value as *const T).cast::<c_void>(),
            )
        };
        GhosttyError::from_result(code)
    }

    fn get_value<T: Copy>(&self, key: ffi::GhosttySnapshotDecoderData) -> Result<T> {
        let mut out = core::mem::MaybeUninit::<T>::uninit();
        // SAFETY: `self.raw` is live and `out` is an uninitialised slot large
        // enough for the `T` the key documents.
        let code = unsafe {
            ffi::ghostty_snapshot_decoder_get(self.raw, key, out.as_mut_ptr().cast::<c_void>())
        };
        GhosttyError::from_result(code)?;
        // SAFETY: on success the library fully initialised the slot.
        Ok(unsafe { out.assume_init() })
    }

    /// Read a value that reports `GHOSTTY_NO_VALUE` before it has meaning.
    fn try_value<T: Copy>(&self, key: ffi::GhosttySnapshotDecoderData) -> Result<Option<T>> {
        match self.get_value::<T>(key) {
            Ok(value) => Ok(Some(value)),
            Err(err) if err.is_empty_value() => Ok(None),
            Err(err) => Err(err),
        }
    }

    fn get_usize(&self, key: ffi::GhosttySnapshotDecoderData) -> Result<usize> {
        self.get_value(key)
    }

    fn try_usize(&self, key: ffi::GhosttySnapshotDecoderData) -> Result<usize> {
        Ok(self.try_value::<usize>(key)?.unwrap_or(0))
    }

    fn try_u32(&self, key: ffi::GhosttySnapshotDecoderData) -> Result<Option<u32>> {
        self.try_value(key)
    }

    fn try_u64(&self, key: ffi::GhosttySnapshotDecoderData) -> Result<u64> {
        Ok(self.try_value::<u64>(key)?.unwrap_or(0))
    }

    fn try_bool(&self, key: ffi::GhosttySnapshotDecoderData) -> Result<bool> {
        Ok(self.try_value::<u8>(key)?.unwrap_or(0) != 0)
    }

    fn try_i32(&self, key: ffi::GhosttySnapshotDecoderData) -> Result<Option<i32>> {
        self.try_value(key)
    }
}

impl Drop for SnapshotDecoder<'_> {
    fn drop(&mut self) {
        if self.raw.is_null() {
            return;
        }
        // SAFETY: `self.raw` is a live decoder owned solely by `self`, and this
        // is the only place it is freed. The call does not release the caller's
        // ownership of any terminal the decoder produced.
        unsafe { ffi::ghostty_snapshot_decoder_free(self.raw) };
        self.raw = ptr::null_mut();
    }
}

/// A terminal restored through [`SnapshotDecoder::ready`], with history pages
/// still to replay.
///
/// The terminal is fully usable for rendering and live input immediately; scroll
/// back into it while history drains. Dropping this value drops the terminal,
/// which happens before the decoder borrow ends, satisfying the upstream rule
/// that the terminal must outlive the decoder's replay.
pub struct ReadyTerminal<'d, 'a> {
    decoder: &'d mut SnapshotDecoder<'a>,
    terminal: Terminal,
}

impl<'d, 'a> ReadyTerminal<'d, 'a> {
    /// The restored terminal.
    pub fn terminal(&self) -> &Terminal {
        &self.terminal
    }

    /// The restored terminal, mutably, for rendering, resizing, or live input
    /// between history pages.
    pub fn terminal_mut(&mut self) -> &mut Terminal {
        &mut self.terminal
    }

    /// Decode the next history page.
    ///
    /// Returns `Ok(true)` when a page was consumed, and `Ok(false)` once FINISH
    /// has been validated. Repeated calls after FINISH also return `Ok(false)`,
    /// matching the `GHOSTTY_NO_VALUE` contract.
    ///
    /// # Errors
    ///
    /// Any decoding failure. After one, the source position is invalid and only
    /// dropping the decoder is safe; the terminal stays usable with whatever
    /// history was already restored.
    pub fn next_page(&mut self) -> Result<bool> {
        // SAFETY: `self.decoder.raw` is live and borrowed for `'d`.
        let code = unsafe { ffi::ghostty_snapshot_decoder_next(self.decoder.raw) };
        match GhosttyError::from_result(code) {
            Ok(()) => Ok(true),
            Err(err) if err.is_empty_value() => Ok(false),
            Err(err) => Err(err),
        }
    }

    /// Decode history pages until FINISH.
    ///
    /// # Errors
    ///
    /// Propagates the first failure from [`ReadyTerminal::next_page`].
    pub fn finish(&mut self) -> Result<()> {
        while self.next_page()? {}
        Ok(())
    }

    /// Decode every remaining page and take ownership of the terminal.
    ///
    /// # Errors
    ///
    /// Propagates the first failure from [`ReadyTerminal::next_page`].
    pub fn finish_owned(mut self) -> Result<Terminal> {
        self.finish()?;
        // `ReadyTerminal` has no `Drop` impl, so destructuring moves the terminal
        // out cleanly and the decoder borrow simply ends.
        let ReadyTerminal { terminal, .. } = self;
        Ok(terminal)
    }

    /// The decoder's progress counters.
    ///
    /// # Errors
    ///
    /// See [`SnapshotDecoder::progress`].
    pub fn progress(&self) -> Result<DecoderProgress> {
        self.decoder.progress()
    }
}
