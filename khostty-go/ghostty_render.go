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

// Format selects the output encoding produced by a Formatter.
type Format C.GhosttyFormatterFormat

// Output formats.
const (
	// FormatPlain emits text with no escape sequences.
	FormatPlain Format = C.GHOSTTY_FORMATTER_FORMAT_PLAIN
	// FormatVT emits VT sequences preserving colors, styles, and URLs.
	FormatVT Format = C.GHOSTTY_FORMATTER_FORMAT_VT
	// FormatHTML emits HTML with inline styles.
	FormatHTML Format = C.GHOSTTY_FORMATTER_FORMAT_HTML
)

// FormatterOptions configures a Formatter.
//
// The zero value is usable and equivalent to plain text with no trimming,
// which suits reading a screen dump. Enable Trim to drop trailing blanks, and
// Unwrap to join soft-wrapped lines into logical lines.
type FormatterOptions struct {
	// Format is the output encoding. FormatPlain when zero.
	Format Format

	// Unwrap joins soft-wrapped lines.
	Unwrap bool

	// Trim removes trailing whitespace from non-blank lines.
	Trim bool

	// Extras toggles the extra state emitted by FormatVT and FormatHTML.
	Extras FormatterExtras
}

// FormatterExtras selects which non-content state a styled format includes.
//
// Extras only affect FormatVT and FormatHTML; FormatPlain ignores them.
type FormatterExtras struct {
	// Cursor emits the cursor position (CUP).
	Cursor bool
	// Style emits the cursor's active SGR style.
	Style bool
	// Hyperlink emits OSC 8 hyperlink state.
	Hyperlink bool
	// Charsets emits character set designation and invocation.
	Charsets bool
	// Palette emits the palette as OSC 4 sequences.
	Palette bool
	// Modes emits non-default terminal modes as CSI h/l.
	Modes bool
	// ScrollingRegion emits DECSTBM and DECSLRM.
	ScrollingRegion bool
	// Pwd emits the working directory as OSC 7.
	Pwd bool
	// Keyboard emits keyboard modes such as ModifyOtherKeys.
	Keyboard bool
}

// Formatter renders a terminal's active screen.
//
// It borrows the terminal: the terminal must outlive the formatter, and each
// call to Format reads the terminal's current state, so one formatter can be
// reused across frames without recreating it.
type Formatter struct {
	ptr  C.GhosttyFormatter
	term *Terminal
}

// NewFormatter creates a formatter for the terminal's active screen.
func NewFormatter(t *Terminal, opts FormatterOptions) (*Formatter, error) {
	p, err := t.valid()
	if err != nil {
		return nil, err
	}

	// GHOSTTY_INIT_SIZED sets `size` on both the outer options struct and
	// the nested extras struct, which is how the library detects the
	// struct versions it was compiled against.
	co := C.GhosttyFormatterTerminalOptions{
		size:   C.size_t(unsafe.Sizeof(C.GhosttyFormatterTerminalOptions{})),
		emit:   C.GhosttyFormatterFormat(opts.Format),
		unwrap: C.bool(opts.Unwrap),
		trim:   C.bool(opts.Trim),
	}
	co.extra = C.GhosttyFormatterTerminalExtra{
		size:             C.size_t(unsafe.Sizeof(C.GhosttyFormatterTerminalExtra{})),
		palette:          C.bool(opts.Extras.Palette),
		modes:            C.bool(opts.Extras.Modes),
		scrolling_region: C.bool(opts.Extras.ScrollingRegion),
		pwd:              C.bool(opts.Extras.Pwd),
		keyboard:         C.bool(opts.Extras.Keyboard),
		screen: C.GhosttyFormatterScreenExtra{
			size:      C.size_t(unsafe.Sizeof(C.GhosttyFormatterScreenExtra{})),
			cursor:    C.bool(opts.Extras.Cursor),
			style:     C.bool(opts.Extras.Style),
			hyperlink: C.bool(opts.Extras.Hyperlink),
			charsets:  C.bool(opts.Extras.Charsets),
		},
	}

	var cf C.GhosttyFormatter
	if err := errno(C.ghostty_formatter_terminal_new(nil, &cf, p, co)); err != nil {
		return nil, err
	}

	f := &Formatter{ptr: cf, term: t}
	runtime.SetFinalizer(f, (*Formatter).Close)
	return f, nil
}

// Close frees the formatter. It is safe to call more than once, and to call on
// a nil receiver. The borrowed terminal is not affected.
func (f *Formatter) Close() error {
	if f == nil || f.ptr == nil {
		return nil
	}
	C.ghostty_formatter_free(f.ptr)
	f.ptr = nil
	runtime.SetFinalizer(f, nil)
	return nil
}

// Format renders the terminal's current state and returns the bytes.
//
// An empty result is returned as a nil slice with no error: the C API reports
// empty output as success with a NULL buffer.
func (f *Formatter) Format() ([]byte, error) {
	if f == nil || f.ptr == nil {
		return nil, ErrInvalidValue
	}

	var ptr *C.uint8_t
	var n C.size_t
	if err := errno(C.ghostty_formatter_format_alloc(f.ptr, nil, &ptr, &n)); err != nil {
		return nil, err
	}
	if ptr == nil || n == 0 {
		C.ghostty_free(nil, ptr, 0)
		return nil, nil
	}

	out := C.GoBytes(unsafe.Pointer(ptr), C.int(n))
	C.ghostty_free(nil, ptr, n)
	return out, nil
}

// Text renders the terminal's active screen as plain text.
//
// It is the one-shot convenience for the most common read: create a formatter,
// format, free it again. Use a persistent Formatter when formatting more than
// once against the same terminal.
func (f *Formatter) Text() (string, error) {
	b, err := f.Format()
	return string(b), err
}

// Text renders the terminal's active screen as trimmed plain text.
//
// It is a convenience wrapper over NewFormatter(FormatPlain, Trim) + Format,
// for the common "what is on the screen" read.
func (t *Terminal) Text() (string, error) {
	f, err := NewFormatter(t, FormatterOptions{Format: FormatPlain, Trim: true})
	if err != nil {
		return "", err
	}
	defer f.Close()
	return f.Text()
}
