package khostty

/*
#include <stdlib.h>
#include <ghostty/vt.h>
*/
import "C"

import "unsafe"

// MouseAction identifies a mouse event's phase.
type MouseAction C.GhosttyMouseAction

// Mouse actions.
const (
	// MousePress is a button press.
	MousePress MouseAction = C.GHOSTTY_MOUSE_ACTION_PRESS
	// MouseRelease is a button release.
	MouseRelease MouseAction = C.GHOSTTY_MOUSE_ACTION_RELEASE
	// MouseMotion is movement, with or without a button held.
	MouseMotion MouseAction = C.GHOSTTY_MOUSE_ACTION_MOTION
)

// MouseButton identifies which button an event involves.
type MouseButton C.GhosttyMouseButton

// Mouse buttons.
const (
	// MouseUnknown is used for motion with no button involved.
	MouseUnknown MouseButton = C.GHOSTTY_MOUSE_BUTTON_UNKNOWN
	// MouseLeft is button 1.
	MouseLeft MouseButton = C.GHOSTTY_MOUSE_BUTTON_LEFT
	// MouseRight is button 2.
	MouseRight MouseButton = C.GHOSTTY_MOUSE_BUTTON_RIGHT
	// MouseMiddle is button 3.
	MouseMiddle MouseButton = C.GHOSTTY_MOUSE_BUTTON_MIDDLE
	// MouseFour is the first extra button.
	MouseFour MouseButton = C.GHOSTTY_MOUSE_BUTTON_FOUR
	// MouseFive is the second extra button.
	MouseFive MouseButton = C.GHOSTTY_MOUSE_BUTTON_FIVE
	// MouseSix is the third extra button.
	MouseSix MouseButton = C.GHOSTTY_MOUSE_BUTTON_SIX
	// MouseSeven is the fourth extra button.
	MouseSeven MouseButton = C.GHOSTTY_MOUSE_BUTTON_SEVEN
	// MouseEight is the fifth extra button.
	MouseEight MouseButton = C.GHOSTTY_MOUSE_BUTTON_EIGHT
	// MouseNine is the sixth extra button.
	MouseNine MouseButton = C.GHOSTTY_MOUSE_BUTTON_NINE
	// MouseTen is the seventh extra button.
	MouseTen MouseButton = C.GHOSTTY_MOUSE_BUTTON_TEN
	// MouseEleven is the eighth extra button.
	MouseEleven MouseButton = C.GHOSTTY_MOUSE_BUTTON_ELEVEN
)

// String returns the wire format name.
func (f MouseFormat) String() string {
	switch f {
	case MouseFormatX10:
		return "x10"
	case MouseFormatUTF8:
		return "utf8"
	case MouseFormatSGR:
		return "sgr"
	case MouseFormatURXVT:
		return "urxvt"
	case MouseFormatSGRPixels:
		return "sgr-pixels"
	default:
		return "unknown"
	}
}

// String returns the button name.
func (b MouseButton) String() string {
	switch b {
	case MouseUnknown:
		return "unknown"
	case MouseLeft:
		return "left"
	case MouseRight:
		return "right"
	case MouseMiddle:
		return "middle"
	default:
		return "extra"
	}
}

// MousePosition is a position in surface-space pixels, with (0,0) at the
// top-left of the surface. It is not a grid coordinate; the encoder maps it
// through the configured cell size.
type MousePosition struct {
	X float32
	Y float32
}

// String returns the action name.
func (a MouseAction) String() string {
	switch a {
	case MousePress:
		return "press"
	case MouseRelease:
		return "release"
	case MouseMotion:
		return "motion"
	default:
		return "unknown"
	}
}

// MouseFormat is the wire format the encoder emits.
type MouseFormat C.GhosttyMouseFormat

// Mouse wire formats.
const (
	// MouseFormatX10 is the original X10 encoding, coordinates only.
	MouseFormatX10 MouseFormat = C.GHOSTTY_MOUSE_FORMAT_X10
	// MouseFormatUTF8 is the UTF-8 extended encoding.
	MouseFormatUTF8 MouseFormat = C.GHOSTTY_MOUSE_FORMAT_UTF8
	// MouseFormatSGR is the SGR encoding, which is unambiguous past column 223.
	MouseFormatSGR MouseFormat = C.GHOSTTY_MOUSE_FORMAT_SGR
	// MouseFormatURXVT is the urxvt encoding.
	MouseFormatURXVT MouseFormat = C.GHOSTTY_MOUSE_FORMAT_URXVT
	// MouseFormatSGRPixels is SGR with pixel coordinates.
	MouseFormatSGRPixels MouseFormat = C.GHOSTTY_MOUSE_FORMAT_SGR_PIXELS
)

// MouseTrackingMode is the tracking mode the application requested.
type MouseTrackingMode C.GhosttyMouseTrackingMode

// Mouse tracking modes, corresponding to the DEC private modes.
const (
	// MouseTrackingNone disables reporting.
	MouseTrackingNone MouseTrackingMode = C.GHOSTTY_MOUSE_TRACKING_NONE
	// MouseTrackingX10 reports presses only.
	MouseTrackingX10 MouseTrackingMode = C.GHOSTTY_MOUSE_TRACKING_X10
	// MouseTrackingNormal reports presses and releases.
	MouseTrackingNormal MouseTrackingMode = C.GHOSTTY_MOUSE_TRACKING_NORMAL
	// MouseTrackingButton reports drags while a button is held.
	MouseTrackingButton MouseTrackingMode = C.GHOSTTY_MOUSE_TRACKING_BUTTON
	// MouseTrackingAny reports all motion.
	MouseTrackingAny MouseTrackingMode = C.GHOSTTY_MOUSE_TRACKING_ANY
)

// String returns the tracking mode name.
func (m MouseTrackingMode) String() string {
	switch m {
	case MouseTrackingNone:
		return "none"
	case MouseTrackingX10:
		return "x10"
	case MouseTrackingNormal:
		return "normal"
	case MouseTrackingButton:
		return "button"
	case MouseTrackingAny:
		return "any"
	default:
		return "unknown"
	}
}

// MouseEncoderOption identifies a writable encoder setting.
type MouseEncoderOption C.GhosttyMouseEncoderOption

// Mouse encoder options.
const (
	// MouseEncEvent sets the tracking mode (MouseTrackingMode).
	MouseEncEvent MouseEncoderOption = C.GHOSTTY_MOUSE_ENCODER_OPT_EVENT
	// MouseEncFormat sets the wire format (MouseFormat).
	MouseEncFormat MouseEncoderOption = C.GHOSTTY_MOUSE_ENCODER_OPT_FORMAT
	// MouseEncSize sets the surface geometry (EncoderSize).
	MouseEncSize MouseEncoderOption = C.GHOSTTY_MOUSE_ENCODER_OPT_SIZE
	// MouseEncAnyButtonPressed reports whether any button is currently down (bool).
	MouseEncAnyButtonPressed MouseEncoderOption = C.GHOSTTY_MOUSE_ENCODER_OPT_ANY_BUTTON_PRESSED
	// MouseEncTrackLastCell keeps the last reported cell, for motion coalescing (bool).
	MouseEncTrackLastCell MouseEncoderOption = C.GHOSTTY_MOUSE_ENCODER_OPT_TRACK_LAST_CELL
)

// EncoderSize is the surface geometry the encoder needs to map a pixel
// position onto a cell.
//
// The padding fields are summed, not averaged: the encoder subtracts them to
// find the usable origin. Zero is a valid value for every field, which is what
// a caller wants when the surface has no padding.
type EncoderSize struct {
	ScreenWidth   uint32
	ScreenHeight  uint32
	CellWidth     uint32
	CellHeight    uint32
	PaddingTop    uint32
	PaddingBottom uint32
	PaddingRight  uint32
	PaddingLeft   uint32
}

// cEncoderSize converts to the C struct, setting the required size header.
func (s EncoderSize) cEncoderSize() C.GhosttyMouseEncoderSize {
	out := C.GhosttyMouseEncoderSize{
		screen_width:  C.uint32_t(s.ScreenWidth),
		screen_height: C.uint32_t(s.ScreenHeight),
		cell_width:    C.uint32_t(s.CellWidth),
		cell_height:   C.uint32_t(s.CellHeight),
	}
	out.size = C.size_t(unsafe.Sizeof(out))
	out.padding_top = C.uint32_t(s.PaddingTop)
	out.padding_bottom = C.uint32_t(s.PaddingBottom)
	out.padding_right = C.uint32_t(s.PaddingRight)
	out.padding_left = C.uint32_t(s.PaddingLeft)
	return out
}
