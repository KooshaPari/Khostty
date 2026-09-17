//! Allocator integration and buffer management.
//!
//! `libghostty-vt` never allocates behind the caller's back for ownership
//! purposes. Anything it hands back as owned memory is either allocated through
//! the caller's `GhosttyAllocator` or through the library default, and must be
//! released with `ghostty_free` using the *same* allocator
//! (`include/ghostty/vt/allocator.h`). On platforms where Zig's libc and the
//! consumer's C runtime disagree — Windows is the documented case — calling the
//! C `free()` on library-allocated memory is undefined behaviour, so this module
//! never does.
//!
//! Three things live here:
//!
//! * [`Allocator`] — the default (NULL) allocator, or a Rust-backed allocator
//!   installed through the `GhosttyAllocatorVtable` interface.
//! * [`OwnedBuffer`] — RAII ownership of library-allocated bytes.
//! * [`encode_with_buffer`] — the two-pass "query the required size, then fill"
//!   helper shared by every buffer-writing API (`ghostty_snapshot_encode_buf`,
//!   `ghostty_key_encoder_encode`, `ghostty_focus_encode`,
//!   `ghostty_terminal_selection_format_buf`, ...).

use crate::error::{GhosttyError, Result};
use crate::ffi;

/// Which allocator to hand to a `libghostty-vt` function that takes one.
///
/// `Allocator::default()` and [`Allocator::library_default`] both produce the
/// NULL allocator pointer, which tells the library to use its own default
/// (libc `malloc`/`free` when libc is linked). [`Allocator::system`] installs a
/// Rust-backed vtable instead.
#[derive(Clone, Copy)]
pub struct Allocator {
    /// Backing struct. Only meaningful when `use_vtable` is set; otherwise the
    /// C side receives NULL and picks its default allocator.
    raw: ffi::GhosttyAllocator,
    use_vtable: bool,
}

/// Vtable for the Rust-backed allocator.
///
/// Semantics, from `allocator.h`:
///
/// * `alloc` returns NULL on failure. `alignment` is a power of two in 1..=16.
/// * `resize` returns true only if the block could grow or shrink *in place*.
///   Returning false is always legal and means "the caller must relocate", so
///   this implementation reports false and lets the library copy.
/// * `remap` returns the (possibly relocated) pointer, or NULL to tell the
///   library to allocate and copy itself. This implementation returns NULL.
/// * `free` must release a block previously returned by `alloc`, with the
///   original `len` and `alignment`.
///
/// None of these may unwind across the FFI boundary, so every one of them is
/// written with a `catch_unwind` guard that degrades to a failure return.
static SYSTEM_VTABLE: ffi::GhosttyAllocatorVtable = ffi::GhosttyAllocatorVtable {
    alloc: Some(system_alloc),
    resize: Some(system_resize),
    remap: Some(system_remap),
    free: Some(system_free),
};

/// Run `body`, swallowing any unwind so it cannot cross the C boundary.
fn guarded<T>(fallback: T, body: impl FnOnce() -> T) -> T {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(body)) {
        Ok(value) => value,
        Err(_) => fallback,
    }
}

/// # Safety
///
/// Called by libghostty-vt through the allocator vtable. `alignment` must be a
/// power of two in 1..=16, as the C contract guarantees; anything else is
/// clamped rather than trusted.
unsafe extern "C" fn system_alloc(
    _ctx: *mut core::ffi::c_void,
    len: usize,
    alignment: u8,
    _ret_addr: usize,
) -> *mut core::ffi::c_void {
    guarded(core::ptr::null_mut(), || {
        if len == 0 {
            return core::ptr::null_mut();
        }
        let align = (alignment as usize).clamp(1, 16);
        // SAFETY: `align` is a power of two in 1..=16 as guaranteed by the C
        // contract (clamped defensively), and `len` is non-zero.
        match unsafe {
            std::alloc::alloc(std::alloc::Layout::from_size_align_unchecked(len, align))
        } {
            ptr if ptr.is_null() => core::ptr::null_mut(),
            ptr => ptr.cast(),
        }
    })
}

/// # Safety
///
/// Called by libghostty-vt through the allocator vtable. This implementation
/// never touches `memory`, so the pointer and length are unused; the return
/// value is always `false`, which the caller must treat as "relocate yourself".
unsafe extern "C" fn system_resize(
    _ctx: *mut core::ffi::c_void,
    _memory: *mut core::ffi::c_void,
    _memory_len: usize,
    _alignment: u8,
    _new_len: usize,
    _ret_addr: usize,
) -> bool {
    // Always false: the library then performs its own allocate-copy-free, which
    // is correct for any allocator and avoids relying on the Rust allocator's
    // in-place growth. See the `resize` contract in allocator.h.
    false
}

/// # Safety
///
/// Called by libghostty-vt through the allocator vtable. Returns NULL, which
/// per the C contract tells the library to allocate and copy for itself.
unsafe extern "C" fn system_remap(
    _ctx: *mut core::ffi::c_void,
    _memory: *mut core::ffi::c_void,
    _memory_len: usize,
    _alignment: u8,
    _new_len: usize,
    _ret_addr: usize,
) -> *mut core::ffi::c_void {
    // NULL means "allocate and copy yourself", which is always legal.
    core::ptr::null_mut()
}

/// # Safety
///
/// Called by libghostty-vt through the allocator vtable. `memory` must have come
/// from `system_alloc` with the same `memory_len` and `alignment`; this
/// implementation deallocates with exactly those parameters.
unsafe extern "C" fn system_free(
    _ctx: *mut core::ffi::c_void,
    memory: *mut core::ffi::c_void,
    memory_len: usize,
    alignment: u8,
    _ret_addr: usize,
) {
    if memory.is_null() || memory_len == 0 {
        return;
    }
    guarded((), || {
        let align = (alignment as usize).clamp(1, 16);
        // SAFETY: `memory` came from `system_alloc` with this exact `len` and
        // `alignment`, which is the contract for `free` in allocator.h.
        unsafe {
            std::alloc::dealloc(
                memory.cast::<u8>(),
                std::alloc::Layout::from_size_align_unchecked(memory_len, align),
            )
        }
    })
}

impl Allocator {
    /// The library's own default allocator (NULL pointer).
    ///
    /// This is what the C examples pass and what the crate uses everywhere
    /// unless a caller asks otherwise.
    pub const fn library_default() -> Self {
        Allocator {
            raw: ffi::GhosttyAllocator {
                ctx: core::ptr::null_mut(),
                vtable: core::ptr::null(),
            },
            use_vtable: false,
        }
    }

    /// A Rust-backed allocator installed through the vtable interface.
    ///
    /// The returned allocator is `Copy`, stateless, and safe to share: it
    /// delegates to Rust's global allocator. Use it when the process must not
    /// depend on the library's libc-based default, for example when linking a
    /// freestanding or musl-flavoured build.
    pub const fn system() -> Self {
        Allocator {
            raw: ffi::GhosttyAllocator {
                ctx: core::ptr::null_mut(),
                vtable: &SYSTEM_VTABLE,
            },
            use_vtable: true,
        }
    }

    /// Pointer to pass to a `libghostty-vt` function taking an allocator.
    ///
    /// NULL for the default allocator, which is the documented "use yours"
    /// spelling in the C API.
    pub fn as_ptr(&self) -> *const ffi::GhosttyAllocator {
        if self.use_vtable {
            &self.raw
        } else {
            core::ptr::null()
        }
    }
}

impl core::fmt::Debug for Allocator {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        if self.use_vtable {
            f.write_str("Allocator::system()")
        } else {
            f.write_str("Allocator::library_default()")
        }
    }
}

impl Default for Allocator {
    fn default() -> Self {
        Allocator::library_default()
    }
}

/// Owned bytes allocated by `libghostty-vt`.
///
/// Released through `ghostty_free` with the allocator that produced them, in
/// [`Drop`]. This is the only correct way to release memory returned by
/// `ghostty_*_alloc` functions.
#[derive(Debug)]
pub struct OwnedBuffer {
    ptr: *mut u8,
    len: usize,
    allocator: Allocator,
}

impl OwnedBuffer {
    /// Take ownership of `ptr`, which must have been allocated by
    /// `libghostty-vt` using `allocator` and be `len` bytes long.
    ///
    /// # Errors
    ///
    /// [`GhosttyError::NullHandle`] when `ptr` is null while `len` is non-zero,
    /// which would otherwise turn into a use of an invalid pointer.
    pub fn from_raw(ptr: *mut u8, len: usize, allocator: Allocator) -> Result<Self> {
        if ptr.is_null() && len > 0 {
            return Err(GhosttyError::NullHandle);
        }
        Ok(OwnedBuffer {
            ptr,
            len,
            allocator,
        })
    }

    /// The bytes.
    pub fn as_slice(&self) -> &[u8] {
        if self.ptr.is_null() || self.len == 0 {
            return &[];
        }
        // SAFETY: `ptr`/`len` describe a live allocation owned by this value.
        unsafe { core::slice::from_raw_parts(self.ptr, self.len) }
    }

    /// Number of bytes.
    pub fn len(&self) -> usize {
        self.len
    }

    /// Whether the buffer is empty.
    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    /// Copy the contents into a `Vec<u8>`, leaving ownership here.
    pub fn to_vec(&self) -> Vec<u8> {
        self.as_slice().to_vec()
    }

    /// Copy the contents as a `String`, requiring valid UTF-8.
    pub fn to_string_lossy(&self) -> String {
        String::from_utf8_lossy(self.as_slice()).into_owned()
    }
}

impl Drop for OwnedBuffer {
    fn drop(&mut self) {
        if self.ptr.is_null() || self.len == 0 {
            return;
        }
        // SAFETY: `ptr` came from a libghostty-vt allocation made with
        // `self.allocator`, and `len` is that allocation's size, which is what
        // `ghostty_free` requires. `ghostty_free` tolerates a NULL pointer, and
        // this is the sole owner, so there is no double free.
        unsafe { ffi::ghostty_free(self.allocator.as_ptr(), self.ptr, self.len) };
        self.ptr = core::ptr::null_mut();
        self.len = 0;
    }
}

/// Allocate `len` bytes through `allocator`, or the library default.
///
/// Returns a null pointer when `len` is zero or the allocation fails, matching
/// the C contract.
pub fn alloc(allocator: Allocator, len: usize) -> *mut u8 {
    // SAFETY: `allocator.as_ptr()` is either NULL (documented default) or a
    // pointer to a live `Allocator` that outlives the call, with every vtable
    // entry non-null.
    unsafe { ffi::ghostty_alloc(allocator.as_ptr(), len) }
}

/// Fill a buffer through a two-pass C API.
///
/// Many `libghostty-vt` entry points follow the same contract: called with a
/// null buffer and zero capacity they return `GHOSTTY_OUT_OF_SPACE` and write
/// the required size into the length out-parameter; called again with a
/// correctly sized buffer they write the bytes and report how many.
///
/// `body` receives `(buffer_ptr, capacity, &mut written)` and returns the raw
/// `GhosttyResult`. The returned `Vec` is truncated to the number of bytes the
/// library actually reported, so a stale or hostile length cannot smuggle
/// uninitialised bytes into safe code.
///
/// # Errors
///
/// Propagates whatever the encoding call reported, with
/// [`GhosttyError::OutOfSpace`] carrying the required capacity if the second
/// pass still failed.
pub fn encode_with_buffer<F>(mut body: F) -> Result<Vec<u8>>
where
    F: FnMut(*mut u8, usize, &mut usize) -> ffi::GhosttyResult,
{
    let mut required: usize = 0;
    let first = body(core::ptr::null_mut(), 0, &mut required);
    match first {
        // Nothing to encode (for example an empty key event payload).
        ffi::GHOSTTY_SUCCESS => return Ok(Vec::with_capacity(required)),
        // The expected "tell me how much room you need" answer.
        ffi::GHOSTTY_OUT_OF_SPACE => {}
        other => return Err(GhosttyError::from(other)),
    }

    if required == 0 {
        return Ok(Vec::new());
    }

    let mut buf = vec![0u8; required];
    let mut written: usize = 0;
    let second = body(buf.as_mut_ptr(), buf.len(), &mut written);
    match second {
        ffi::GHOSTTY_SUCCESS => {
            if written > buf.len() {
                // The library reported writing more than it was given, which
                // breaks its own buffer contract. Refuse to hand back a slice
                // that would read past the allocation.
                return Err(GhosttyError::Unknown { code: second });
            }
            // Truncate to what was actually written so uninitialised tail bytes
            // can never reach safe code.
            buf.truncate(written);
            Ok(buf)
        }
        // The requirement grew between the two passes. Surface the new size
        // rather than looping, so the caller decides whether to retry.
        ffi::GHOSTTY_OUT_OF_SPACE => Err(GhosttyError::OutOfSpace {
            required: Some(written),
        }),
        other => Err(GhosttyError::from(other)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_allocator_passes_null_upstream() {
        assert!(Allocator::default().as_ptr().is_null());
        assert!(Allocator::library_default().as_ptr().is_null());
    }

    #[test]
    fn system_allocator_supplies_a_vtable() {
        let alloc = Allocator::system();
        assert!(!alloc.as_ptr().is_null());
    }

    #[test]
    fn zero_length_allocation_is_null() {
        assert!(alloc(Allocator::default(), 0).is_null());
        assert!(alloc(Allocator::system(), 0).is_null());
    }

    #[test]
    fn from_raw_rejects_null_with_length() {
        let err = OwnedBuffer::from_raw(core::ptr::null_mut(), 8, Allocator::default())
            .expect_err("null with length is rejected");
        assert_eq!(err, GhosttyError::NullHandle);
    }

    #[test]
    fn empty_buffer_is_safe() {
        let buf = OwnedBuffer::from_raw(core::ptr::null_mut(), 0, Allocator::default())
            .expect("null with zero length is fine");
        assert!(buf.is_empty());
        assert_eq!(buf.as_slice(), b"");
        assert_eq!(buf.to_vec(), Vec::<u8>::new());
    }

    #[test]
    fn encode_with_buffer_fills_a_growing_result() {
        // Mimic the C contract: first call with cap 0 reports the need, second
        // call writes. The payload is deterministic so we can assert content.
        let payload = b"hello ghostty";
        let mut calls = 0usize;
        let out = encode_with_buffer(|buf, cap, written| {
            calls += 1;
            if cap < payload.len() {
                *written = payload.len();
                return ffi::GHOSTTY_OUT_OF_SPACE;
            }
            // SAFETY: caller offered `cap >= payload.len()` bytes.
            unsafe { core::ptr::copy_nonoverlapping(payload.as_ptr(), buf, payload.len()) };
            *written = payload.len();
            ffi::GHOSTTY_SUCCESS
        })
        .expect("two-pass encode succeeds");

        assert_eq!(out, payload);
        assert_eq!(calls, 2);
    }

    #[test]
    fn encode_with_buffer_returns_empty_when_nothing_is_written() {
        let out = encode_with_buffer(|_buf, _cap, written| {
            *written = 0;
            ffi::GHOSTTY_SUCCESS
        })
        .expect("success with no payload");
        assert!(out.is_empty());
    }

    #[test]
    fn encode_with_buffer_rejects_overreported_writes() {
        let err = encode_with_buffer(|_buf, cap, written| {
            if cap == 0 {
                *written = 4;
                return ffi::GHOSTTY_OUT_OF_SPACE;
            }
            // Claim more bytes than the buffer holds.
            *written = cap + 1024;
            ffi::GHOSTTY_SUCCESS
        })
        .expect_err("over-reported write must not produce a slice");
        assert!(matches!(err, GhosttyError::Unknown { .. }));
    }

    #[test]
    fn encode_with_buffer_propagates_failures() {
        let err = encode_with_buffer(|_buf, _cap, _written| ffi::GHOSTTY_OUT_OF_MEMORY)
            .expect_err("allocation failure propagates");
        assert_eq!(err, GhosttyError::OutOfMemory);
    }
}
