package khostty

/*
#include <stdlib.h>
#include <ghostty/vt.h>
*/
import "C"

import (
	"unsafe"
)

// This file holds the read side of the Terminal wrapper: the typed accessors
// for the fields documented by TerminalData. The lifecycle and mutation paths
// live in ghostty_vt.go.

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
