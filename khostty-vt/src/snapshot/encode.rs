//! Snapshot encoding: turn a [`Terminal`] into snapshot bytes.
//!
//! Three shapes are offered, matching the three C entry points:
//!
//! | Function | C entry point | Use when |
//! |----------|---------------|----------|
//! | [`encode_alloc`] | `ghostty_snapshot_encode_alloc` | You want a library-allocated [`OwnedBuffer`] |
//! | [`encode`] | `ghostty_snapshot_encode_buf` | You want a `Vec<u8>` |
//! | [`encode_to`] | `ghostty_snapshot_encode` | You want to stream into an existing sink |
//!
//! All three require that the terminal's VT parser and UTF-8 decoder are either
//! at ground state, or had continuation tracking enabled *before* the input that
//! left them unfinished. Otherwise the library reports
//! [`GhosttyError::InvalidValue`], because a snapshot that omitted a partial
//! sequence could not be resumed faithfully.

use crate::error::{GhosttyError, Result};
use crate::ffi;
use crate::sys::{encode_with_buffer, Allocator, OwnedBuffer};
use crate::terminal::Terminal;
use core::ffi::c_void;
use core::ptr;

// ---------------------------------------------------------------------------
// Encoding
// ---------------------------------------------------------------------------

/// Encode `terminal` into a freshly allocated library buffer.
///
/// The bytes are owned by an [`OwnedBuffer`], which releases them through
/// `ghostty_free` with the allocator that produced them.
///
/// # Errors
///
/// [`GhosttyError::InvalidValue`] when the terminal's VT parser or UTF-8 decoder
/// is unfinished and continuation tracking was not enabled before that input was
/// written. See the `ghostty_snapshot_encode_alloc` contract.
pub fn encode_alloc(terminal: &Terminal, allocator: Allocator) -> Result<OwnedBuffer> {
    let mut ptr: *mut u8 = ptr::null_mut();
    let mut len: usize = 0;
    // SAFETY: `terminal.as_raw()` is live for this call, `allocator.as_ptr()` is
    // NULL or a live allocator, and both out-parameters are valid and distinct.
    let code = unsafe {
        ffi::ghostty_snapshot_encode_alloc(
            terminal.as_raw(),
            allocator.as_ptr(),
            &mut ptr,
            &mut len,
        )
    };
    GhosttyError::from_result(code)?;
    OwnedBuffer::from_raw(ptr, len, allocator)
}

/// Encode `terminal` into a `Vec<u8>`.
///
/// Uses the two-pass `GHOSTTY_OUT_OF_SPACE` protocol documented on
/// `ghostty_snapshot_encode_buf`: a null buffer with zero capacity reports the
/// required size, then a correctly sized buffer receives the bytes.
///
/// # Errors
///
/// As [`encode_alloc`], plus whatever the buffer protocol reports.
pub fn encode(terminal: &Terminal) -> Result<Vec<u8>> {
    encode_with_buffer(|buf, cap, written| {
        // SAFETY: `terminal.as_raw()` is live, `buf`/`cap` are the caller's
        // buffer (possibly NULL/0, which the function documents as the size
        // query), and `written` is a valid out-parameter.
        unsafe { ffi::ghostty_snapshot_encode_buf(terminal.as_raw(), buf, cap, written) }
    })
}

/// Encode `terminal` by streaming bytes into `sink`.
///
/// `sink` returns `true` once it has accepted the whole slice, and `false` to
/// abort the encode, which surfaces as [`GhosttyError::IoError`]. A rejected
/// write leaves a partial snapshot without a FINISH marker in the destination,
/// as the C contract warns.
///
/// # Errors
///
/// [`GhosttyError::IoError`] if `sink` rejects a write, plus the errors
/// documented on [`encode_alloc`].
pub fn encode_to<F>(terminal: &Terminal, mut sink: F) -> Result<()>
where
    F: FnMut(&[u8]) -> bool,
{
    let writer = ffi::GhosttyWriter {
        write: Some(snapshot_writer_trampoline::<F>),
        // SAFETY: the pointer is only dereferenced inside the trampoline, which
        // upstream calls synchronously during this function, so `sink` outlives
        // every use.
        userdata: (&mut sink as *mut F).cast::<c_void>(),
    };
    // SAFETY: `terminal.as_raw()` is live for the call and the writer's callback
    // and context stay valid for its duration.
    let code = unsafe { ffi::ghostty_snapshot_encode(terminal.as_raw(), writer) };
    GhosttyError::from_result(code)
}

/// Forwards snapshot output to a Rust closure.
///
/// # Safety
///
/// Called only by libghostty-vt, with the `userdata` set by [`encode_to`] and
/// `data`/`len` describing a borrowed byte range valid for the call.
unsafe extern "C" fn snapshot_writer_trampoline<F>(
    userdata: *mut c_void,
    data: *const u8,
    len: usize,
) -> bool
where
    F: FnMut(&[u8]) -> bool,
{
    if userdata.is_null() || (data.is_null() && len > 0) {
        return false;
    }
    // A panic must not unwind into C; a rejected write is reported as false.
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        // SAFETY: `userdata` is the pointer to the caller's closure created in
        // `encode_to`, which is alive for the whole call.
        let sink = unsafe { &mut *(userdata as *mut F) };
        let bytes = if len == 0 {
            &[][..]
        } else {
            // SAFETY: `data`/`len` describe a readable region for this call.
            unsafe { core::slice::from_raw_parts(data, len) }
        };
        sink(bytes)
    }))
    .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Drive the trampoline the way the library does.
    fn forward<F>(sink: &mut F, data: &[u8]) -> bool
    where
        F: FnMut(&[u8]) -> bool,
    {
        // SAFETY: `sink` is a live mutable reference for the duration of the
        // call, which is exactly the contract the trampoline documents.
        unsafe {
            snapshot_writer_trampoline::<F>(
                (sink as *mut F).cast::<c_void>(),
                data.as_ptr(),
                data.len(),
            )
        }
    }

    #[test]
    fn writer_trampoline_rejects_a_null_context() {
        let accepted = unsafe {
            snapshot_writer_trampoline::<fn(&[u8]) -> bool>(ptr::null_mut(), b"x".as_ptr(), 1)
        };
        assert!(!accepted);
    }

    #[test]
    fn writer_trampoline_forwards_bytes() {
        let mut seen: Vec<u8> = Vec::new();
        let mut sink = |bytes: &[u8]| {
            seen.extend_from_slice(bytes);
            true
        };
        assert!(forward(&mut sink, b"snapshot"));
        assert_eq!(seen, b"snapshot");
    }

    #[test]
    fn writer_trampoline_reports_a_rejected_write() {
        let mut sink = |_bytes: &[u8]| false;
        assert!(
            !forward(&mut sink, b"x"),
            "a rejecting sink must report failure to the library"
        );
    }

    #[test]
    fn writer_trampoline_swallows_a_panic() {
        let mut sink = |_bytes: &[u8]| panic!("writer panic");
        // If the panic escaped, this test would abort the process.
        assert!(!forward(&mut sink, b"x"));
    }

    #[test]
    fn writer_trampoline_handles_an_empty_slice() {
        let mut seen: Vec<u8> = Vec::new();
        let mut sink = |bytes: &[u8]| {
            seen.extend_from_slice(bytes);
            true
        };
        assert!(forward(&mut sink, &[]));
        assert!(seen.is_empty());
    }
}
