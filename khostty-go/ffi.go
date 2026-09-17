package khostty

/*
#include <stdlib.h>
#include <ghostty/vt.h>
*/
import "C"

import (
	"fmt"
	"unsafe"
)

// Error is a libghostty-vt result code that is not GHOSTTY_SUCCESS.
//
// The C API returns one of a small, fixed set of codes; Error preserves the
// numeric value so callers can compare against the exported constants and
// still see the raw code in logs.
type Error C.GhosttyResult

// Result codes returned by the C API, mirroring GhosttyResult.
const (
	// ErrOutOfMemory indicates a failed allocation.
	ErrOutOfMemory = Error(C.GHOSTTY_OUT_OF_MEMORY)
	// ErrInvalidValue indicates an argument or option value was rejected.
	ErrInvalidValue = Error(C.GHOSTTY_INVALID_VALUE)
	// ErrOutOfSpace indicates a caller-provided buffer was too small.
	ErrOutOfSpace = Error(C.GHOSTTY_OUT_OF_SPACE)
	// ErrNoValue indicates the requested value is not currently set.
	ErrNoValue = Error(C.GHOSTTY_NO_VALUE)
	// ErrIO indicates a reader or writer rejected the operation.
	ErrIO = Error(C.GHOSTTY_IO_ERROR)
	// ErrLimitExceeded indicates encoded input exceeded a configured limit.
	ErrLimitExceeded = Error(C.GHOSTTY_LIMIT_EXCEEDED)
	// ErrRejected indicates a safety check refused the operation.
	ErrRejected = Error(C.GHOSTTY_REJECTED)
)

// Error implements the error interface.
func (e Error) Error() string {
	switch e {
	case ErrOutOfMemory:
		return "khostty: out of memory"
	case ErrInvalidValue:
		return "khostty: invalid value"
	case ErrOutOfSpace:
		return "khostty: buffer too small"
	case ErrNoValue:
		return "khostty: no value"
	case ErrIO:
		return "khostty: io error"
	case ErrLimitExceeded:
		return "khostty: limit exceeded"
	case ErrRejected:
		return "khostty: rejected by safety check"
	case 0:
		return "khostty: success"
	default:
		return fmt.Sprintf("khostty: unknown result %d", int32(e))
	}
}

// Is reports whether target is the same result code. It makes the exported
// sentinels usable with errors.Is.
func (e Error) Is(target error) bool {
	t, ok := target.(Error)
	return ok && t == e
}

// errno converts a C result code into an error, or nil for GHOSTTY_SUCCESS.
//
// Every wrapper funnels its C return values through here so callers only
// ever see Go errors.
func errno(res C.GhosttyResult) error {
	if res == C.GHOSTTY_SUCCESS {
		return nil
	}
	return Error(res)
}

// mustString builds a GhosttyString view over b.
//
// The C API treats a GhosttyString as borrowed for the duration of the call
// that receives it, so the bytes are copied into C memory here. That keeps
// the bindings inside the cgo pointer rules: the Go-allocated struct only
// ever holds pointers to C memory, never to Go memory.
//
// The returned cleanup must be called after the C call returns.
func mustString(b []byte) (s C.GhosttyString, cleanup func()) {
	if len(b) == 0 {
		// An empty needle / empty value: the C API documents NULL and
		// zero length as "no value".
		return C.GhosttyString{ptr: nil, len: 0}, func() {}
	}

	ptr := C.CBytes(b)
	return C.GhosttyString{
		ptr: (*C.uchar)(ptr),
		len: C.size_t(len(b)),
	}, func() { C.free(ptr) }
}

// goBytes copies len bytes of C memory into a Go byte slice.
func goBytes(ptr *C.uchar, n C.size_t) []byte {
	if ptr == nil || n == 0 {
		return nil
	}
	return C.GoBytes(unsafe.Pointer(ptr), C.int(n))
}

// TypeManifest returns the library's versioned C type manifest as JSON.
//
// It is the machine-readable description of every public struct, enum, and
// union the linked build exposes, including sizes, alignments, field offsets,
// and enum values. The Python bindings derive their struct sizes from the
// same manifest, so it doubles as a cross-language ABI check.
//
// The C API returns this as a borrowed pointer to static storage that is
// valid for the lifetime of the process.
func TypeManifest() string {
	return C.GoString(C.ghostty_type_json())
}
