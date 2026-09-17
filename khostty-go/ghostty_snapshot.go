package khostty

/*
#include <stdlib.h>
#include <ghostty/vt.h>
*/
import "C"

import (
	"runtime"
	"unsafe"
)

// Snapshot returns a complete encoded snapshot of the terminal.
//
// The snapshot is a self-contained byte stream that a fresh Terminal can be
// restored from with RestoreSnapshot; it captures screen contents, modes, and
// the unfinished VT continuation needed to resume mid-sequence.
//
// The terminal must not be mutated concurrently, and its parser and UTF-8
// decoder must either be at ground or have had continuation tracking enabled
// before the input that left them unfinished.
func (t *Terminal) Snapshot() ([]byte, error) {
	p, err := t.valid()
	if err != nil {
		return nil, err
	}

	var ptr *C.uint8_t
	var n C.size_t
	if err := errno(C.ghostty_snapshot_encode_alloc(p, nil, &ptr, &n)); err != nil {
		return nil, err
	}
	// The buffer comes from the default allocator, so it must go back to
	// ghostty_free with a NULL allocator. A NULL pointer with zero length
	// is a valid, freeable empty result.
	if ptr == nil || n == 0 {
		C.ghostty_free(nil, ptr, 0)
		return []byte{}, nil
	}

	out := C.GoBytes(unsafe.Pointer(ptr), C.int(n))
	C.ghostty_free(nil, ptr, n)
	return out, nil
}

// SnapshotSize returns the number of bytes Snapshot would produce, without
// allocating the snapshot.
//
// It is the two-call pattern the C API documents: query with a NULL buffer,
// then encode into a buffer of the reported size. Use it to reuse a buffer
// across frames.
func (t *Terminal) SnapshotSize() (int, error) {
	p, err := t.valid()
	if err != nil {
		return 0, err
	}

	var written C.size_t
	res := C.ghostty_snapshot_encode_buf(p, nil, 0, &written)
	if res == C.GHOSTTY_OUT_OF_SPACE {
		return int(written), nil
	}
	if err := errno(res); err != nil {
		return 0, err
	}
	return int(written), nil
}

// SnapshotInto encodes a snapshot into buf and returns the number of bytes
// written.
//
// If buf is too small it returns ErrOutOfSpace; SnapshotSize reports the
// required capacity. A caller-provided buffer that is too small may have been
// partially overwritten, so discard the prefix rather than appending to it.
func (t *Terminal) SnapshotInto(buf []byte) (int, error) {
	p, err := t.valid()
	if err != nil {
		return 0, err
	}

	var written C.size_t
	var base *C.uint8_t
	if len(buf) > 0 {
		base = (*C.uint8_t)(unsafe.Pointer(&buf[0]))
	}

	res := C.ghostty_snapshot_encode_buf(p, base, C.size_t(len(buf)), &written)
	if err := errno(res); err != nil {
		return int(written), err
	}
	return int(written), nil
}

// RestoreSnapshot decodes a snapshot produced by Snapshot into a new Terminal.
//
// The bytes are copied into C memory first: the C decoder retains the buffer
// pointer across the decode call, so handing it Go memory would break the cgo
// pointer rules.
func RestoreSnapshot(data []byte) (*Terminal, error) {
	if len(data) == 0 {
		return nil, ErrInvalidValue
	}

	src := C.CBytes(data)
	defer C.free(src)

	var dec C.GhosttySnapshotDecoder
	if err := errno(C.ghostty_snapshot_decoder_new_buf(
		nil, &dec, (*C.uint8_t)(src), C.size_t(len(data)),
	)); err != nil {
		return nil, err
	}
	defer C.ghostty_snapshot_decoder_free(dec)

	var ct C.GhosttyTerminal
	if err := errno(C.ghostty_snapshot_decoder_decode(dec, &ct)); err != nil {
		return nil, err
	}

	// The decoder hands over ownership of the terminal: freeing the decoder
	// does not free it, and the caller frees it like any other terminal.
	t := &Terminal{ptr: ct}
	runtime.SetFinalizer(t, (*Terminal).Close)
	return t, nil
}
