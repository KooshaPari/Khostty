//! Error type for libghostty-vt operations.
//!
//! Every fallible `libghostty-vt` entry point returns a `GhosttyResult`, which
//! is an `int`-backed C enum (see `include/ghostty/vt/types.h`). This module
//! maps those codes onto a Rust error type and provides the small conversion
//! helpers the safe wrappers use.
//!
//! Two properties matter for a wrapper like this:
//!
//! 1. **Forward compatibility.** The upstream headers describe the API as
//!    work in progress. A newer library can return a code this crate predates,
//!    so [`GhosttyError::Unknown`] retains the raw integer instead of failing
//!    an exhaustive match.
//! 2. **Recoverable detail.** `GHOSTTY_OUT_OF_SPACE` means "your buffer was too
//!    small, here is the size you need". The buffer helpers in [`crate::sys`]
//!    surface that requirement as `GhosttyError::OutOfSpace { required }`, which
//!    is what makes the two-pass "size then fill" pattern safe.

use crate::ffi;
use core::fmt;

/// Result alias used throughout the crate.
pub type Result<T> = core::result::Result<T, GhosttyError>;

/// Failure modes reported by `libghostty-vt`.
///
/// Marked `#[non_exhaustive]` because the C API is explicitly unstable: new
/// codes may appear in future libghostty-vt releases.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum GhosttyError {
    /// `GHOSTTY_OUT_OF_MEMORY` (`-1`): an allocation failed.
    OutOfMemory,

    /// `GHOSTTY_INVALID_VALUE` (`-2`): a value passed in was not acceptable.
    InvalidValue,

    /// `GHOSTTY_OUT_OF_SPACE` (`-3`): the caller-provided buffer was too small.
    ///
    /// `required` is the byte capacity the library reported it needs, when the
    /// API that failed writes one back (the C `GhosttyBuffer` contract). It is
    /// `None` when the failing call does not report a size, which happens for
    /// opaque handles where the caller cannot retry with a carve-out.
    OutOfSpace {
        /// Required byte capacity, as reported by the library.
        required: Option<usize>,
    },

    /// `GHOSTTY_NO_VALUE` (`-4`): the requested value is not set.
    ///
    /// This is the normal answer for "no selection", "no title set yet", and
    /// similar queries. It is distinct from an error in the caller's request.
    NoValue,

    /// `GHOSTTY_IO_ERROR` (`-5`): a read or write callback failed.
    IoError,

    /// `GHOSTTY_LIMIT_EXCEEDED` (`-6`): encoded input passed a configured cap.
    LimitExceeded,

    /// `GHOSTTY_REJECTED` (`-7`): a safety check refused the operation.
    ///
    /// The documented case is pasted text that could inject commands. Nothing
    /// was done; the embedder must confirm with the user and retry with the
    /// operation's allow flag set.
    Rejected,

    /// The library reported success but produced a null handle.
    ///
    /// Not a documented `GhosttyResult` code. It is a defensive check in the
    /// safe wrappers: a null handle out of a successful constructor would
    /// otherwise be dereferenced on the next call.
    NullHandle,

    /// A `GhosttyResult` code this crate does not know.
    ///
    /// Keeps the raw integer so callers can still report or match on it.
    Unknown {
        /// The raw `GhosttyResult` value returned by the library.
        code: ffi::GhosttyResult,
    },
}

impl GhosttyError {
    /// Convert a raw `GhosttyResult` into a [`Result`].
    ///
    /// Returns `Ok(())` for `GHOSTTY_SUCCESS` and the mapped error otherwise.
    #[inline]
    pub fn from_result(code: ffi::GhosttyResult) -> Result<()> {
        match code {
            ffi::GHOSTTY_SUCCESS => Ok(()),
            ffi::GHOSTTY_OUT_OF_MEMORY => Err(GhosttyError::OutOfMemory),
            ffi::GHOSTTY_INVALID_VALUE => Err(GhosttyError::InvalidValue),
            ffi::GHOSTTY_OUT_OF_SPACE => Err(GhosttyError::OutOfSpace { required: None }),
            ffi::GHOSTTY_NO_VALUE => Err(GhosttyError::NoValue),
            ffi::GHOSTTY_IO_ERROR => Err(GhosttyError::IoError),
            ffi::GHOSTTY_LIMIT_EXCEEDED => Err(GhosttyError::LimitExceeded),
            ffi::GHOSTTY_REJECTED => Err(GhosttyError::Rejected),
            other => Err(GhosttyError::Unknown { code: other }),
        }
    }

    /// Convert a raw `GhosttyResult` from a buffer-writing call into a
    /// [`Result`].
    ///
    /// On `GHOSTTY_OUT_OF_SPACE` the C contract says the `len` field holds the
    /// required capacity; pass that as `required` so callers can retry.
    #[inline]
    pub fn from_buffer_result(code: ffi::GhosttyResult, required: usize) -> Result<()> {
        match code {
            ffi::GHOSTTY_OUT_OF_SPACE => Err(GhosttyError::OutOfSpace {
                required: Some(required),
            }),
            other => GhosttyError::from_result(other),
        }
    }

    /// The raw `GhosttyResult` code this error came from.
    ///
    /// [`GhosttyError::NullHandle`] has no library code and maps to
    /// `GHOSTTY_SUCCESS`, since the library itself reported success.
    pub fn code(&self) -> ffi::GhosttyResult {
        match self {
            GhosttyError::OutOfMemory => ffi::GHOSTTY_OUT_OF_MEMORY,
            GhosttyError::InvalidValue => ffi::GHOSTTY_INVALID_VALUE,
            GhosttyError::OutOfSpace { .. } => ffi::GHOSTTY_OUT_OF_SPACE,
            GhosttyError::NoValue => ffi::GHOSTTY_NO_VALUE,
            GhosttyError::IoError => ffi::GHOSTTY_IO_ERROR,
            GhosttyError::LimitExceeded => ffi::GHOSTTY_LIMIT_EXCEEDED,
            GhosttyError::Rejected => ffi::GHOSTTY_REJECTED,
            GhosttyError::NullHandle => ffi::GHOSTTY_SUCCESS,
            GhosttyError::Unknown { code } => *code,
        }
    }

    /// Whether retrying the same call could plausibly succeed.
    ///
    /// `OutOfSpace` is retryable with a larger buffer, `IoError` may be
    /// transient, and `Unknown` is treated as retryable because the crate
    /// cannot reason about a code it does not know. `Rejected` is *not*
    /// retryable: the caller must change the request, not repeat it.
    pub fn is_retryable(&self) -> bool {
        matches!(
            self,
            GhosttyError::OutOfSpace { .. } | GhosttyError::IoError | GhosttyError::Unknown { .. }
        )
    }

    /// Whether this error means "no value", i.e. an expected empty result.
    ///
    /// Useful where the API uses `GHOSTTY_NO_VALUE` to mean "nothing here"
    /// rather than "something went wrong", such as an unset terminal title.
    pub fn is_empty_value(&self) -> bool {
        matches!(self, GhosttyError::NoValue)
    }
}

impl fmt::Display for GhosttyError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            GhosttyError::OutOfMemory => f.write_str("libghostty-vt allocation failed"),
            GhosttyError::InvalidValue => f.write_str("libghostty-vt rejected an invalid value"),
            GhosttyError::OutOfSpace { required } => match required {
                Some(n) => write!(f, "buffer too small: {n} bytes required"),
                None => f.write_str("buffer too small"),
            },
            GhosttyError::NoValue => f.write_str("no value"),
            GhosttyError::IoError => f.write_str("libghostty-vt I/O callback failed"),
            GhosttyError::LimitExceeded => f.write_str("encoded input exceeded a configured limit"),
            GhosttyError::Rejected => f.write_str(
                "libghostty-vt refused the operation as unsafe; confirm with the user and retry \
                 with the operation's allow flag set",
            ),
            GhosttyError::NullHandle => {
                f.write_str("libghostty-vt reported success but returned a null handle")
            }
            GhosttyError::Unknown { code } => {
                write!(f, "unknown libghostty-vt result code {code}")
            }
        }
    }
}

impl std::error::Error for GhosttyError {}

impl From<ffi::GhosttyResult> for GhosttyError {
    /// Convenience conversion; prefer [`GhosttyError::from_result`] when the
    /// success case has no error value to build.
    fn from(code: ffi::GhosttyResult) -> Self {
        match GhosttyError::from_result(code) {
            Ok(()) => GhosttyError::NullHandle,
            Err(err) => err,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn success_maps_to_ok() {
        assert!(GhosttyError::from_result(ffi::GHOSTTY_SUCCESS).is_ok());
    }

    #[test]
    fn crate_codes_match_the_header_values() {
        // Values from include/ghostty/vt/types.h.
        assert_eq!(ffi::GHOSTTY_SUCCESS, 0);
        assert_eq!(ffi::GHOSTTY_OUT_OF_MEMORY, -1);
        assert_eq!(ffi::GHOSTTY_INVALID_VALUE, -2);
        assert_eq!(ffi::GHOSTTY_OUT_OF_SPACE, -3);
        assert_eq!(ffi::GHOSTTY_NO_VALUE, -4);
        assert_eq!(ffi::GHOSTTY_IO_ERROR, -5);
        assert_eq!(ffi::GHOSTTY_LIMIT_EXCEEDED, -6);
        assert_eq!(ffi::GHOSTTY_REJECTED, -7);
    }

    #[test]
    fn every_documented_code_round_trips() {
        for code in [
            ffi::GHOSTTY_OUT_OF_MEMORY,
            ffi::GHOSTTY_INVALID_VALUE,
            ffi::GHOSTTY_OUT_OF_SPACE,
            ffi::GHOSTTY_NO_VALUE,
            ffi::GHOSTTY_IO_ERROR,
            ffi::GHOSTTY_LIMIT_EXCEEDED,
            ffi::GHOSTTY_REJECTED,
        ] {
            let err = GhosttyError::from_result(code).expect_err("code should be an error");
            assert_eq!(err.code(), code, "round-trip failed for {code}");
        }
    }

    #[test]
    fn unknown_codes_are_preserved() {
        let err = GhosttyError::from_result(-99).expect_err("unknown code is an error");
        assert_eq!(err, GhosttyError::Unknown { code: -99 });
        assert_eq!(err.code(), -99);
        assert!(err.is_retryable());
    }

    #[test]
    fn buffer_result_records_required_capacity() {
        let err = GhosttyError::from_buffer_result(ffi::GHOSTTY_OUT_OF_SPACE, 4096)
            .expect_err("out of space is an error");
        assert_eq!(
            err,
            GhosttyError::OutOfSpace {
                required: Some(4096)
            }
        );
        assert!(err.is_retryable());
        assert!(GhosttyError::from_buffer_result(ffi::GHOSTTY_SUCCESS, 0).is_ok());
    }

    #[test]
    fn rejection_is_not_retryable() {
        let err = GhosttyError::from_result(ffi::GHOSTTY_REJECTED).expect_err("rejected");
        assert!(!err.is_retryable());
    }

    #[test]
    fn no_value_is_an_empty_result_not_a_failure() {
        let err = GhosttyError::from_result(ffi::GHOSTTY_NO_VALUE).expect_err("no value");
        assert!(err.is_empty_value());
    }

    #[test]
    fn display_mentions_the_required_capacity() {
        let err = GhosttyError::OutOfSpace { required: Some(64) };
        assert!(err.to_string().contains("64"));
    }

    #[test]
    fn implements_std_error() {
        fn assert_error<E: std::error::Error>() {}
        assert_error::<GhosttyError>();
    }
}
