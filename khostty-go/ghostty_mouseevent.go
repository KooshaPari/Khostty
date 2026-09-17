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

// This file holds the mouse event and mouse encoder. The action, button,
// format, and tracking enums they use live in ghostty_mouse.go.

// MouseEvent is a mutable input event handed to a MouseEncoder.
//
// As with KeyEvent, one event can be reconfigured and reused for every
// pointer movement rather than allocating per event.
type MouseEvent struct {
	ptr C.GhosttyMouseEvent
}

// NewMouseEvent creates an empty mouse event.
func NewMouseEvent() (*MouseEvent, error) {
	var ce C.GhosttyMouseEvent
	if err := errno(C.ghostty_mouse_event_new(nil, &ce)); err != nil {
		return nil, err
	}
	e := &MouseEvent{ptr: ce}
	runtime.SetFinalizer(e, (*MouseEvent).Close)
	return e, nil
}

// Close frees the event. It is safe to call twice, and on a nil receiver.
func (e *MouseEvent) Close() error {
	if e == nil || e.ptr == nil {
		return nil
	}
	C.ghostty_mouse_event_free(e.ptr)
	e.ptr = nil
	runtime.SetFinalizer(e, nil)
	return nil
}

// SetAction sets the event phase.
func (e *MouseEvent) SetAction(action MouseAction) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	C.ghostty_mouse_event_set_action(e.ptr, C.GhosttyMouseAction(action))
	return nil
}

// Action returns the event phase.
func (e *MouseEvent) Action() (MouseAction, error) {
	if e == nil || e.ptr == nil {
		return 0, ErrInvalidValue
	}
	return MouseAction(C.ghostty_mouse_event_get_action(e.ptr)), nil
}

// SetButton sets which button the event involves.
func (e *MouseEvent) SetButton(button MouseButton) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	C.ghostty_mouse_event_set_button(e.ptr, C.GhosttyMouseButton(button))
	return nil
}

// ClearButton marks the event as involving no button, which is how motion with
// nothing held is reported.
func (e *MouseEvent) ClearButton() error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	C.ghostty_mouse_event_clear_button(e.ptr)
	return nil
}

// Button returns the event's button and whether one is set.
func (e *MouseEvent) Button() (MouseButton, bool, error) {
	if e == nil || e.ptr == nil {
		return 0, false, ErrInvalidValue
	}
	var out C.GhosttyMouseButton
	if !bool(C.ghostty_mouse_event_get_button(e.ptr, &out)) {
		return 0, false, nil
	}
	return MouseButton(out), true, nil
}

// SetMods sets the held modifiers.
func (e *MouseEvent) SetMods(mods Mods) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	C.ghostty_mouse_event_set_mods(e.ptr, C.GhosttyMods(mods))
	return nil
}

// Mods returns the held modifiers.
func (e *MouseEvent) Mods() (Mods, error) {
	if e == nil || e.ptr == nil {
		return 0, ErrInvalidValue
	}
	return Mods(C.ghostty_mouse_event_get_mods(e.ptr)), nil
}

// SetPosition sets the position in surface-space pixels.
func (e *MouseEvent) SetPosition(pos MousePosition) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	C.ghostty_mouse_event_set_position(e.ptr, C.GhosttyMousePosition{
		x: C.float(pos.X),
		y: C.float(pos.Y),
	})
	return nil
}

// Position returns the position in surface-space pixels.
func (e *MouseEvent) Position() (MousePosition, error) {
	if e == nil || e.ptr == nil {
		return MousePosition{}, ErrInvalidValue
	}
	p := C.ghostty_mouse_event_get_position(e.ptr)
	return MousePosition{X: float32(p.x), Y: float32(p.y)}, nil
}

// MouseEncoder turns mouse events into the byte sequences a pty expects.
//
// The tracking mode and format are decided by the application and change at
// runtime, so either keep the encoder in sync with SyncFromTerminal or set them
// explicitly with SetTrackingMode and SetFormat.
type MouseEncoder struct {
	ptr C.GhosttyMouseEncoder
}

// NewMouseEncoder creates an encoder with the library's defaults.
func NewMouseEncoder() (*MouseEncoder, error) {
	var ce C.GhosttyMouseEncoder
	if err := errno(C.ghostty_mouse_encoder_new(nil, &ce)); err != nil {
		return nil, err
	}
	e := &MouseEncoder{ptr: ce}
	runtime.SetFinalizer(e, (*MouseEncoder).Close)
	return e, nil
}

// Close frees the encoder. It is safe to call twice, and on a nil receiver.
func (e *MouseEncoder) Close() error {
	if e == nil || e.ptr == nil {
		return nil
	}
	C.ghostty_mouse_encoder_free(e.ptr)
	e.ptr = nil
	runtime.SetFinalizer(e, nil)
	return nil
}

// Reset clears the encoder's accumulated state, such as the last reported
// cell. Call it when the pointer leaves the surface, so the next entry is not
// treated as motion from the old position.
func (e *MouseEncoder) Reset() error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	C.ghostty_mouse_encoder_reset(e.ptr)
	return nil
}

// SyncFromTerminal copies the tracking mode and format the application
// selected from a terminal into this encoder.
func (e *MouseEncoder) SyncFromTerminal(t *Terminal) error {
	p, err := t.valid()
	if err != nil {
		return err
	}
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	C.ghostty_mouse_encoder_setopt_from_terminal(e.ptr, p)
	return nil
}

// SetTrackingMode sets the mode reported to the application.
func (e *MouseEncoder) SetTrackingMode(mode MouseTrackingMode) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	v := C.GhosttyMouseTrackingMode(mode)
	C.ghostty_mouse_encoder_setopt(e.ptr, C.GHOSTTY_MOUSE_ENCODER_OPT_EVENT, unsafe.Pointer(&v))
	return nil
}

// SetFormat sets the wire format.
func (e *MouseEncoder) SetFormat(format MouseFormat) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	v := C.GhosttyMouseFormat(format)
	C.ghostty_mouse_encoder_setopt(e.ptr, C.GHOSTTY_MOUSE_ENCODER_OPT_FORMAT, unsafe.Pointer(&v))
	return nil
}

// SetSize sets the surface geometry used to map pixels onto cells.
func (e *MouseEncoder) SetSize(size EncoderSize) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	cs := size.cEncoderSize()
	C.ghostty_mouse_encoder_setopt(e.ptr, C.GHOSTTY_MOUSE_ENCODER_OPT_SIZE, unsafe.Pointer(&cs))
	return nil
}

// SetAnyButtonPressed tells the encoder whether any button is currently down,
// which decides between press and drag encodings for motion events.
func (e *MouseEncoder) SetAnyButtonPressed(pressed bool) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	v := C.bool(pressed)
	C.ghostty_mouse_encoder_setopt(e.ptr, C.GHOSTTY_MOUSE_ENCODER_OPT_ANY_BUTTON_PRESSED, unsafe.Pointer(&v))
	return nil
}

// SetTrackLastCell enables coalescing of motion within the same cell.
func (e *MouseEncoder) SetTrackLastCell(enabled bool) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	v := C.bool(enabled)
	C.ghostty_mouse_encoder_setopt(e.ptr, C.GHOSTTY_MOUSE_ENCODER_OPT_TRACK_LAST_CELL, unsafe.Pointer(&v))
	return nil
}

// Encode turns an event into bytes.
//
// An empty result with no error is normal and expected: it means the event is
// not reportable under the current tracking mode. Motion with no button held
// encodes to nothing under MouseTrackingNormal, for example, because that mode
// reports only presses and releases; use MouseTrackingButton or
// MouseTrackingAny to report it.
func (e *MouseEncoder) Encode(ev *MouseEvent) ([]byte, error) {
	if e == nil || e.ptr == nil {
		return nil, ErrInvalidValue
	}
	if ev == nil || ev.ptr == nil {
		return nil, ErrInvalidValue
	}

	buf := make([]byte, 64)
	var written C.size_t

	res := C.ghostty_mouse_encoder_encode(
		e.ptr, ev.ptr,
		(*C.char)(unsafe.Pointer(&buf[0])), C.size_t(len(buf)),
		&written,
	)
	if res == C.GHOSTTY_OUT_OF_SPACE {
		buf = make([]byte, int(written))
		res = C.ghostty_mouse_encoder_encode(
			e.ptr, ev.ptr,
			(*C.char)(unsafe.Pointer(&buf[0])), C.size_t(len(buf)),
			&written,
		)
	}
	if err := errno(res); err != nil {
		return nil, err
	}
	runtime.KeepAlive(buf)
	return buf[:int(written)], nil
}
