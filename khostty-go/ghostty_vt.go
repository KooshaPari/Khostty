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

// Terminal is an opaque libghostty-vt terminal.
//
// It owns the underlying handle: Close releases it, and the finalizer calls
// Close as a backstop. A Terminal is not safe for concurrent use; the C
// library requires callers to serialize all access to one handle.
type Terminal struct {
	ptr C.GhosttyTerminal
}

// NewTerminal creates a terminal with the given grid size in cells.
//
// The terminal starts with the library's defaults (scrollback limits, cursor
// style, colors). Use Set or the Set* helpers to change options before
// writing VT data.
func NewTerminal(cols, rows int) (*Terminal, error) {
	if cols <= 0 || rows <= 0 {
		return nil, ErrInvalidValue
	}

	var ct C.GhosttyTerminal
	if err := errno(C.ghostty_terminal_new(nil, &ct, C.uint16_t(cols), C.uint16_t(rows))); err != nil {
		return nil, err
	}

	t := &Terminal{ptr: ct}
	runtime.SetFinalizer(t, (*Terminal).Close)
	return t, nil
}

// Close frees the terminal handle. It is safe to call more than once, and to
// call on a nil receiver.
//
// After Close the Terminal must not be used again: every method returns
// ErrInvalidValue because the handle is nil.
func (t *Terminal) Close() error {
	if t == nil || t.ptr == nil {
		return nil
	}
	C.ghostty_terminal_free(t.ptr)
	t.ptr = nil
	runtime.SetFinalizer(t, nil)
	return nil
}

// valid reports whether the handle is still usable and returns it.
func (t *Terminal) valid() (C.GhosttyTerminal, error) {
	if t == nil || t.ptr == nil {
		return nil, ErrInvalidValue
	}
	return t.ptr, nil
}

// Write feeds raw bytes through the terminal's VT parser.
//
// It mirrors ghostty_terminal_vt_write, which cannot fail: malformed input is
// logged internally and the parser is kept consistent rather than reporting
// an error. Queries and device-status reports are discarded unless a
// write-PTY callback is installed with SetOption.
func (t *Terminal) Write(data []byte) {
	p, err := t.valid()
	if err != nil || len(data) == 0 {
		return
	}
	C.ghostty_terminal_vt_write(p, (*C.uint8_t)(unsafe.Pointer(&data[0])), C.size_t(len(data)))
	runtime.KeepAlive(data)
}

// WriteString is Write for a string operand.
func (t *Terminal) WriteString(s string) {
	if len(s) == 0 {
		return
	}
	// The copy is unavoidable: cgo cannot take a pointer to string data
	// without going through a byte slice, and the C call borrows its
	// argument only for the duration of the call.
	t.Write([]byte(s))
}

// WriteUntilGround feeds bytes and stops at the point where the VT stream
// returns to ground, reporting how many bytes were consumed.
//
// Ground is the stateless point of the stream (not inside a UTF-8 sequence,
// ESC, CSI, or OSC). It is the safe place to inject out-of-band sequences.
// The terminal must have been created with continuation tracking enabled for
// this to make progress; otherwise it returns false.
func (t *Terminal) WriteUntilGround(data []byte) (consumed int, ok bool) {
	p, err := t.valid()
	if err != nil || len(data) == 0 {
		return 0, err == nil
	}

	var written C.size_t
	res := C.ghostty_terminal_vt_write_until_ground(
		p,
		(*C.uint8_t)(unsafe.Pointer(&data[0])),
		C.size_t(len(data)),
		&written,
	)
	runtime.KeepAlive(data)
	if err := errno(res); err != nil {
		return int(written), false
	}
	return int(written), true
}

// Reset performs a full terminal reset (RIS). Terminal dimensions and
// configured options are preserved.
func (t *Terminal) Reset() {
	if p, err := t.valid(); err == nil {
		C.ghostty_terminal_reset(p)
	}
}

// Resize changes the grid to cols by rows cells.
//
// The primary screen reflows wrapped content; the alternate screen does not.
// The pixel dimensions feed image protocols and XTWINOPS size reports. Pass
// zero cell sizes when pixels are unknown.
func (t *Terminal) Resize(cols, rows int, cellWidthPx, cellHeightPx uint32) error {
	p, err := t.valid()
	if err != nil {
		return err
	}
	if cols <= 0 || rows <= 0 {
		return ErrInvalidValue
	}
	return errno(C.ghostty_terminal_resize(
		p,
		C.uint16_t(cols),
		C.uint16_t(rows),
		C.uint32_t(cellWidthPx),
		C.uint32_t(cellHeightPx),
	))
}

// SetOption writes an option whose value is a pointer (callbacks, userdata)
// or a pointer to the value (as documented per option).
//
// The caller is responsible for the pointer's type and lifetime; for
// callback options the C library retains it, so any func value must be pinned
// for as long as the terminal lives.
func (t *Terminal) SetOption(opt TerminalOption, value unsafe.Pointer) error {
	p, err := t.valid()
	if err != nil {
		return err
	}
	return errno(C.ghostty_terminal_set(p, C.GhosttyTerminalOption(opt), value))
}

// SetString writes a string-valued option (TITLE, PWD, TERMINFO_NAME).
//
// The C API documents these as "const GhosttyString*", and copies the bytes,
// so the value does not need to outlive the call.
func (t *Terminal) SetString(opt TerminalOption, value string) error {
	p, err := t.valid()
	if err != nil {
		return err
	}

	s, cleanup := mustString([]byte(value))
	defer cleanup()

	return errno(C.ghostty_terminal_set(p, C.GhosttyTerminalOption(opt), unsafe.Pointer(&s)))
}

// SetUint32 writes a uint32-valued option.
func (t *Terminal) SetUint32(opt TerminalOption, value uint32) error {
	v := C.uint32_t(value)
	return t.SetOption(opt, unsafe.Pointer(&v))
}

// SetSize writes a size_t-valued option (byte or line limits).
func (t *Terminal) SetSize(opt TerminalOption, value uint64) error {
	v := C.size_t(value)
	return t.SetOption(opt, unsafe.Pointer(&v))
}

// SetBool writes a bool-valued option.
func (t *Terminal) SetBool(opt TerminalOption, value bool) error {
	v := C.bool(value)
	return t.SetOption(opt, unsafe.Pointer(&v))
}

// uint16Data reads a uint16-valued data field.
func (t *Terminal) uint16Data(d TerminalData) (uint16, error) {
	p, err := t.valid()
	if err != nil {
		return 0, err
	}
	var v C.uint16_t
	if err := errno(C.ghostty_terminal_get(p, C.GhosttyTerminalData(d), unsafe.Pointer(&v))); err != nil {
		return 0, err
	}
	return uint16(v), nil
}

// uint32Data reads a uint32-valued data field.
func (t *Terminal) uint32Data(d TerminalData) (uint32, error) {
	p, err := t.valid()
	if err != nil {
		return 0, err
	}
	var v C.uint32_t
	if err := errno(C.ghostty_terminal_get(p, C.GhosttyTerminalData(d), unsafe.Pointer(&v))); err != nil {
		return 0, err
	}
	return uint32(v), nil
}

// sizeData reads a size_t-valued data field.
func (t *Terminal) sizeData(d TerminalData) (uint64, error) {
	p, err := t.valid()
	if err != nil {
		return 0, err
	}
	var v C.size_t
	if err := errno(C.ghostty_terminal_get(p, C.GhosttyTerminalData(d), unsafe.Pointer(&v))); err != nil {
		return 0, err
	}
	return uint64(v), nil
}

// boolData reads a bool-valued data field.
func (t *Terminal) boolData(d TerminalData) (bool, error) {
	p, err := t.valid()
	if err != nil {
		return false, err
	}
	var v C.bool
	if err := errno(C.ghostty_terminal_get(p, C.GhosttyTerminalData(d), unsafe.Pointer(&v))); err != nil {
		return false, err
	}
	return bool(v), nil
}

// stringData reads a GhosttyString-valued data field.
//
// The C API borrows the bytes from the terminal, so they are copied into Go
// memory before returning.
func (t *Terminal) stringData(d TerminalData) (string, error) {
	p, err := t.valid()
	if err != nil {
		return "", err
	}
	var v C.GhosttyString
	if err := errno(C.ghostty_terminal_get(p, C.GhosttyTerminalData(d), unsafe.Pointer(&v))); err != nil {
		return "", err
	}
	if v.ptr == nil || v.len == 0 {
		return "", nil
	}
	return string(C.GoBytes(unsafe.Pointer(v.ptr), C.int(v.len))), nil
}

// Cols returns the terminal width in cells.
func (t *Terminal) Cols() (uint16, error) { return t.uint16Data(DataCols) }

// Rows returns the terminal height in cells.
func (t *Terminal) Rows() (uint16, error) { return t.uint16Data(DataRows) }

// CursorX returns the cursor column.
func (t *Terminal) CursorX() (uint16, error) { return t.uint16Data(DataCursorX) }

// CursorY returns the cursor row.
func (t *Terminal) CursorY() (uint16, error) { return t.uint16Data(DataCursorY) }

// TotalRows returns the number of rows including scrollback.
func (t *Terminal) TotalRows() (uint64, error) { return t.sizeData(DataTotalRows) }

// ScrollbackRows returns the number of scrollback rows.
func (t *Terminal) ScrollbackRows() (uint64, error) { return t.sizeData(DataScrollbackRows) }

// WidthPx returns the terminal width in pixels.
func (t *Terminal) WidthPx() (uint32, error) { return t.uint32Data(DataWidthPx) }

// HeightPx returns the terminal height in pixels.
func (t *Terminal) HeightPx() (uint32, error) { return t.uint32Data(DataHeightPx) }

// Title returns the terminal title set via OSC 0 / OSC 2.
func (t *Terminal) Title() (string, error) { return t.stringData(DataTitle) }

// Pwd returns the working directory reported via OSC 7.
func (t *Terminal) Pwd() (string, error) { return t.stringData(DataPwd) }

// CursorVisible reports whether the cursor is shown.
func (t *Terminal) CursorVisible() (bool, error) { return t.boolData(DataCursorVisible) }

// CursorPendingWrap reports deferred-wrap state, which matters when deciding
// whether a character at the last column wraps.
func (t *Terminal) CursorPendingWrap() (bool, error) { return t.boolData(DataCursorPendingWrap) }

// MouseTracking reports whether the application enabled mouse reporting.
// It is the signal for deciding whether to encode and forward mouse events.
func (t *Terminal) MouseTracking() (bool, error) { return t.boolData(DataMouseTracking) }

// VTGround reports whether the VT parser is at a stateless point, where
// out-of-band sequences can be injected safely.
func (t *Terminal) VTGround() (bool, error) { return t.boolData(DataVTGround) }

// CursorAtPrompt reports whether the cursor sits at a semantic shell prompt
// or input area, based on OSC 133 markers. It is false on the alternate
// screen and when no semantic prompt information is available.
func (t *Terminal) CursorAtPrompt() (bool, error) { return t.boolData(DataCursorAtPrompt) }

// ActiveScreen returns which screen buffer is in use.
func (t *Terminal) ActiveScreen() (Screen, error) {
	p, err := t.valid()
	if err != nil {
		return 0, err
	}
	var v C.GhosttyTerminalScreen
	if err := errno(C.ghostty_terminal_get(p, C.GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN, unsafe.Pointer(&v))); err != nil {
		return 0, err
	}
	return Screen(v), nil
}

// CursorStyle returns the current cursor shape.
func (t *Terminal) CursorStyle() (CursorStyle, error) {
	p, err := t.valid()
	if err != nil {
		return 0, err
	}
	var v C.GhosttyTerminalCursorStyle
	if err := errno(C.ghostty_terminal_get(p, C.GHOSTTY_TERMINAL_DATA_CURSOR_STYLE, unsafe.Pointer(&v))); err != nil {
		return 0, err
	}
	return CursorStyle(v), nil
}

// Data reads `out`-typed data from the terminal directly, for fields without a
// dedicated accessor. `out` must point at storage of the type documented by
// the TerminalData entry.
func (t *Terminal) Data(d TerminalData, out unsafe.Pointer) error {
	p, err := t.valid()
	if err != nil {
		return err
	}
	return errno(C.ghostty_terminal_get(p, C.GhosttyTerminalData(d), out))
}
