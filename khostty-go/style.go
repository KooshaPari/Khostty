package khostty

/*
#include <stdlib.h>
#include <ghostty/vt.h>
*/
import "C"

import "unsafe"

// StyleColorKind identifies which arm of a style color is set.
type StyleColorKind int

// Style color kinds.
const (
	// StyleColorNone means the attribute is unset and the terminal default applies.
	StyleColorNone StyleColorKind = iota
	// StyleColorPalette means the color is a 256-entry palette index.
	StyleColorPalette
	// StyleColorRGB means the color is a direct 24-bit RGB value.
	StyleColorRGB
)

// StyleColor is one color attribute of a cell style.
type StyleColor struct {
	// Kind selects which of the remaining fields is meaningful.
	Kind StyleColorKind

	// Palette is the palette index, valid when Kind is StyleColorPalette.
	Palette uint8

	// R, G, B are the components, valid when Kind is StyleColorRGB.
	R, G, B uint8
}

// RGB returns the color as a 24-bit value and whether Kind is StyleColorRGB.
func (c StyleColor) RGB() (uint32, bool) {
	if c.Kind != StyleColorRGB {
		return 0, false
	}
	return uint32(c.R)<<16 | uint32(c.G)<<8 | uint32(c.B), true
}

// Underline identifies an underline decoration.
type Underline int

// Underline styles, mirroring GHOSTTY_SGR_UNDERLINE_*.
const (
	// UnderlineNone is no underline.
	UnderlineNone Underline = C.GHOSTTY_SGR_UNDERLINE_NONE
	// UnderlineSingle is a single underline.
	UnderlineSingle Underline = C.GHOSTTY_SGR_UNDERLINE_SINGLE
	// UnderlineDouble is a double underline.
	UnderlineDouble Underline = C.GHOSTTY_SGR_UNDERLINE_DOUBLE
	// UnderlineCurly is a curly underline.
	UnderlineCurly Underline = C.GHOSTTY_SGR_UNDERLINE_CURLY
	// UnderlineDotted is a dotted underline.
	UnderlineDotted Underline = C.GHOSTTY_SGR_UNDERLINE_DOTTED
	// UnderlineDashed is a dashed underline.
	UnderlineDashed Underline = C.GHOSTTY_SGR_UNDERLINE_DASHED
)

// Style is the complete SGR style of a cell.
//
// It mirrors GhosttyStyle: decoration flags plus foreground, background, and
// underline colors, each of which is independently unset, a palette index, or
// a direct RGB value.
type Style struct {
	Bold          bool
	Italic        bool
	Faint         bool
	Blink         bool
	Inverse       bool
	Invisible     bool
	Strikethrough bool
	Overline      bool
	Underline     Underline

	Foreground     StyleColor
	Background     StyleColor
	UnderlineColor StyleColor
}

// String renders the enabled decorations, for logs and test failures.
func (s Style) String() string {
	names := []string{}
	for _, f := range []struct {
		on   bool
		name string
	}{
		{s.Bold, "bold"},
		{s.Italic, "italic"},
		{s.Faint, "faint"},
		{s.Blink, "blink"},
		{s.Inverse, "inverse"},
		{s.Invisible, "invisible"},
		{s.Strikethrough, "strikethrough"},
		{s.Overline, "overline"},
	} {
		if f.on {
			names = append(names, f.name)
		}
	}
	out := "style{"
	for i, n := range names {
		if i > 0 {
			out += ","
		}
		out += n
	}
	if s.Underline != UnderlineNone {
		if len(names) > 0 {
			out += ","
		}
		out += "underline"
	}
	return out + "}"
}

// base returns a zeroed C style with the sized-struct header set, which the C
// API requires before it will write into it.
func cStyle() C.GhosttyStyle {
	return C.GhosttyStyle{size: C.size_t(unsafe.Sizeof(C.GhosttyStyle{}))}
}

// styleFromC converts a filled C style into the Go value.
func styleFromC(cs C.GhosttyStyle) Style {
	return Style{
		Bold:          bool(cs.bold),
		Italic:        bool(cs.italic),
		Faint:         bool(cs.faint),
		Blink:         bool(cs.blink),
		Inverse:       bool(cs.inverse),
		Invisible:     bool(cs.invisible),
		Strikethrough: bool(cs.strikethrough),
		Overline:      bool(cs.overline),
		Underline:     Underline(cs.underline),

		Foreground:     styleColorFromC(cs.fg_color),
		Background:     styleColorFromC(cs.bg_color),
		UnderlineColor: styleColorFromC(cs.underline_color),
	}
}

// styleColorFromC decodes one tagged-union color.
func styleColorFromC(c C.GhosttyStyleColor) StyleColor {
	switch c.tag {
	case C.GHOSTTY_STYLE_COLOR_PALETTE:
		// cgo does not expose union arms by name, so each arm is reached
		// through a pointer cast onto the union's storage. All three arms
		// alias the same 8 bytes; the tag says which one is live.
		idx := (*C.GhosttyColorPaletteIndex)(unsafe.Pointer(&c.value))
		return StyleColor{Kind: StyleColorPalette, Palette: uint8(*idx)}
	case C.GHOSTTY_STYLE_COLOR_RGB:
		// The union's RGB arm is reached through a byte view: cgo does not
		// generate named accessors for the non-first arm of the union here,
		// because all three arms alias the same storage.
		rgb := (*C.GhosttyColorRgb)(unsafe.Pointer(&c.value))
		return StyleColor{Kind: StyleColorRGB, R: uint8(rgb.r), G: uint8(rgb.g), B: uint8(rgb.b)}
	default:
		return StyleColor{Kind: StyleColorNone}
	}
}

// CursorStyle returns the SGR style that will be applied to newly printed
// characters.
//
// This is the style the terminal is currently in, which is how a caller knows
// what attributes text written at the cursor will carry. It is not the cursor
// shape: for that, set OptDefaultCursorStyle at construction time.
func (t *Terminal) CursorStyle() (Style, error) {
	p, err := t.valid()
	if err != nil {
		return Style{}, err
	}

	cs := cStyle()
	if err := errno(C.ghostty_terminal_get(p, C.GHOSTTY_TERMINAL_DATA_CURSOR_STYLE, unsafe.Pointer(&cs))); err != nil {
		return Style{}, err
	}
	return styleFromC(cs), nil
}

// IsDefaultStyle reports whether the style has no colors set and no
// decorations, using the library's own definition.
func IsDefaultStyle(s Style) bool {
	cs := C.GhosttyStyle{
		size:            C.size_t(unsafe.Sizeof(C.GhosttyStyle{})),
		bold:            C.bool(s.Bold),
		italic:          C.bool(s.Italic),
		faint:           C.bool(s.Faint),
		blink:           C.bool(s.Blink),
		inverse:         C.bool(s.Inverse),
		invisible:       C.bool(s.Invisible),
		strikethrough:   C.bool(s.Strikethrough),
		overline:        C.bool(s.Overline),
		underline:       C.int(s.Underline),
		fg_color:        styleColorToC(s.Foreground),
		bg_color:        styleColorToC(s.Background),
		underline_color: styleColorToC(s.UnderlineColor),
	}
	return bool(C.ghostty_style_is_default(&cs))
}

// styleColorToC encodes one color back into the tagged union.
func styleColorToC(c StyleColor) C.GhosttyStyleColor {
	out := C.GhosttyStyleColor{}
	switch c.Kind {
	case StyleColorPalette:
		out.tag = C.GHOSTTY_STYLE_COLOR_PALETTE
		*((*C.GhosttyColorPaletteIndex)(unsafe.Pointer(&out.value))) = C.GhosttyColorPaletteIndex(c.Palette)
	case StyleColorRGB:
		out.tag = C.GHOSTTY_STYLE_COLOR_RGB
		rgb := (*C.GhosttyColorRgb)(unsafe.Pointer(&out.value))
		rgb.r, rgb.g, rgb.b = C.uint8_t(c.R), C.uint8_t(c.G), C.uint8_t(c.B)
	}
	return out
}

// DefaultStyle returns the library's default style: no colors, no
// decorations.
func DefaultStyle() Style {
	cs := cStyle()
	C.ghostty_style_default(&cs)
	return styleFromC(cs)
}
