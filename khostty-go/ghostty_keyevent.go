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

// This file holds the key event and key encoder. The Key, Mods, and option
// enums they use live in ghostty_key.go, and the generated key table in
// keys_gen.go.

// KeyEvent is a mutable input event handed to a KeyEncoder.
//
// One event can be reconfigured and reused for every keystroke rather than
// allocating per event, which is what the C API recommends.
type KeyEvent struct {
	ptr C.GhosttyKeyEvent

	// utf8 holds the bytes last passed to SetUTF8. The C API documents that
	// the key event does not take ownership of the text pointer and that the
	// caller must keep it valid for as long as the event needs it, so the
	// buffer lives here rather than in a call-scoped local. Without this the
	// bytes are collected before Encode reads them and encoding silently
	// produces garbage.
	utf8 []byte
}

// NewKeyEvent creates an empty key event.
func NewKeyEvent() (*KeyEvent, error) {
	var ce C.GhosttyKeyEvent
	if err := errno(C.ghostty_key_event_new(nil, &ce)); err != nil {
		return nil, err
	}
	e := &KeyEvent{ptr: ce}
	runtime.SetFinalizer(e, (*KeyEvent).Close)
	return e, nil
}

// Close frees the event. It is safe to call twice, and on a nil receiver.
func (e *KeyEvent) Close() error {
	if e == nil || e.ptr == nil {
		return nil
	}
	C.ghostty_key_event_free(e.ptr)
	e.ptr = nil
	e.utf8 = nil
	runtime.SetFinalizer(e, nil)
	return nil
}

// SetKey sets which physical key the event describes.
func (e *KeyEvent) SetKey(key Key) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	C.ghostty_key_event_set_key(e.ptr, C.GhosttyKey(key))
	return nil
}

// Key returns the event's physical key.
func (e *KeyEvent) Key() (Key, error) {
	if e == nil || e.ptr == nil {
		return 0, ErrInvalidValue
	}
	return Key(C.ghostty_key_event_get_key(e.ptr)), nil
}

// SetAction sets the event phase.
func (e *KeyEvent) SetAction(action KeyAction) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	C.ghostty_key_event_set_action(e.ptr, C.GhosttyKeyAction(action))
	return nil
}

// Action returns the event phase.
func (e *KeyEvent) Action() (KeyAction, error) {
	if e == nil || e.ptr == nil {
		return 0, ErrInvalidValue
	}
	return KeyAction(C.ghostty_key_event_get_action(e.ptr)), nil
}

// SetMods sets the held modifiers.
func (e *KeyEvent) SetMods(mods Mods) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	C.ghostty_key_event_set_mods(e.ptr, C.GhosttyMods(mods))
	return nil
}

// Mods returns the held modifiers.
func (e *KeyEvent) Mods() (Mods, error) {
	if e == nil || e.ptr == nil {
		return 0, ErrInvalidValue
	}
	return Mods(C.ghostty_key_event_get_mods(e.ptr)), nil
}

// SetConsumedMods sets which modifiers the encoder should treat as already
// consumed by the key itself, so they are not reported again.
func (e *KeyEvent) SetConsumedMods(mods Mods) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	C.ghostty_key_event_set_consumed_mods(e.ptr, C.GhosttyMods(mods))
	return nil
}

// ConsumedMods returns the consumed modifiers.
func (e *KeyEvent) ConsumedMods() (Mods, error) {
	if e == nil || e.ptr == nil {
		return 0, ErrInvalidValue
	}
	return Mods(C.ghostty_key_event_get_consumed_mods(e.ptr)), nil
}

// SetUTF8 sets the text this key produces, which dead keys and IMEs need.
//
// The bytes are retained by the event, because the C API borrows the pointer
// rather than copying it. Setting new text releases the previous buffer.
func (e *KeyEvent) SetUTF8(text string) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	if text == "" {
		e.utf8 = nil
		C.ghostty_key_event_set_utf8(e.ptr, nil, 0)
		return nil
	}

	e.utf8 = []byte(text)
	C.ghostty_key_event_set_utf8(
		e.ptr, (*C.char)(unsafe.Pointer(&e.utf8[0])), C.size_t(len(e.utf8)),
	)
	return nil
}

// UTF8 returns the text this key produces.
func (e *KeyEvent) UTF8() (string, error) {
	if e == nil || e.ptr == nil {
		return "", ErrInvalidValue
	}
	var n C.size_t
	ptr := C.ghostty_key_event_get_utf8(e.ptr, &n)
	if ptr == nil || n == 0 {
		return "", nil
	}
	return C.GoStringN(ptr, C.int(n)), nil
}

// SetUnshiftedCodepoint sets the codepoint the key would produce unshifted.
func (e *KeyEvent) SetUnshiftedCodepoint(cp rune) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	C.ghostty_key_event_set_unshifted_codepoint(e.ptr, C.uint32_t(cp))
	return nil
}

// UnshiftedCodepoint returns the unshifted codepoint.
func (e *KeyEvent) UnshiftedCodepoint() (rune, error) {
	if e == nil || e.ptr == nil {
		return 0, ErrInvalidValue
	}
	return rune(C.ghostty_key_event_get_unshifted_codepoint(e.ptr)), nil
}

// SetComposing marks the key as part of an IME composition.
func (e *KeyEvent) SetComposing(composing bool) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	C.ghostty_key_event_set_composing(e.ptr, C.bool(composing))
	return nil
}

// Composing reports whether the key is part of an IME composition.
func (e *KeyEvent) Composing() (bool, error) {
	if e == nil || e.ptr == nil {
		return false, ErrInvalidValue
	}
	return bool(C.ghostty_key_event_get_composing(e.ptr)), nil
}

// KeyEncoder turns key events into the byte sequences a pty expects.
//
// The encoder holds the mode state that decides which encoding applies, so it
// should be long-lived and kept in sync with the terminal it is feeding with
// SyncFromTerminal.
type KeyEncoder struct {
	ptr C.GhosttyKeyEncoder
}

// NewKeyEncoder creates an encoder with the library's defaults.
func NewKeyEncoder() (*KeyEncoder, error) {
	var ce C.GhosttyKeyEncoder
	if err := errno(C.ghostty_key_encoder_new(nil, &ce)); err != nil {
		return nil, err
	}
	e := &KeyEncoder{ptr: ce}
	runtime.SetFinalizer(e, (*KeyEncoder).Close)
	return e, nil
}

// Close frees the encoder. It is safe to call twice, and on a nil receiver.
func (e *KeyEncoder) Close() error {
	if e == nil || e.ptr == nil {
		return nil
	}
	C.ghostty_key_encoder_free(e.ptr)
	e.ptr = nil
	runtime.SetFinalizer(e, nil)
	return nil
}

// SyncFromTerminal copies the modes that affect key encoding from a terminal
// into this encoder (cursor key application, Kitty flags, and so on).
//
// Call it after the application changes terminal modes; otherwise the encoder
// keeps encoding against stale state.
func (e *KeyEncoder) SyncFromTerminal(t *Terminal) error {
	p, err := t.valid()
	if err != nil {
		return err
	}
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	C.ghostty_key_encoder_setopt_from_terminal(e.ptr, p)
	return nil
}

// SetBool sets a boolean encoder option.
func (e *KeyEncoder) SetBool(opt KeyEncoderOption, value bool) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	v := C.bool(value)
	C.ghostty_key_encoder_setopt(e.ptr, C.GhosttyKeyEncoderOption(opt), unsafe.Pointer(&v))
	return nil
}

// SetKittyFlags sets the Kitty keyboard protocol flags.
func (e *KeyEncoder) SetKittyFlags(flags KittyFlags) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	v := C.GhosttyKittyKeyFlags(flags)
	C.ghostty_key_encoder_setopt(e.ptr, C.GHOSTTY_KEY_ENCODER_OPT_KITTY_FLAGS, unsafe.Pointer(&v))
	return nil
}

// SetOptionAsAlt sets how the platform's Option key is reported.
func (e *KeyEncoder) SetOptionAsAlt(mode OptionAsAlt) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	v := C.GhosttyOptionAsAlt(mode)
	C.ghostty_key_encoder_setopt(e.ptr, C.GHOSTTY_KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT, unsafe.Pointer(&v))
	return nil
}

// SetEnumOption writes an encoder option whose value is an int-sized enum,
// such as KeyEncMacOSOptionAsAlt.
//
// Bitmask options are not written this way: KeyEncKittyFlags takes a
// single-byte KittyFlags, so use SetKittyFlags for it and the boolean setters
// for the mode flags.
func (e *KeyEncoder) SetEnumOption(opt KeyEncoderOption, value int32) error {
	if e == nil || e.ptr == nil {
		return ErrInvalidValue
	}
	v := C.int(value)
	C.ghostty_key_encoder_setopt(e.ptr, C.GhosttyKeyEncoderOption(opt), unsafe.Pointer(&v))
	return nil
}

// Encode turns an event into bytes.
//
// Two behaviours are worth knowing before using this:
//
//   - A printable key needs its text. Setting only the physical key and no
//     UTF-8 text encodes to nothing, because a key code alone does not say
//     which character was produced. Set KeyEvent.SetUTF8, or
//     SetUnshiftedCodepoint for the Kitty protocol.
//   - Kitty encoding also needs the unshifted codepoint. With Kitty flags
//     enabled but no codepoint, the encoder produces nothing; setting both
//     yields the CSI-u form, for example \x1b[99;5u for Ctrl+C.
//
// The encoder reports the required size on ErrOutOfSpace, so this grows its
// buffer once and retries rather than guessing a maximum encoding length.
func (e *KeyEncoder) Encode(ev *KeyEvent) ([]byte, error) {
	if e == nil || e.ptr == nil {
		return nil, ErrInvalidValue
	}
	if ev == nil || ev.ptr == nil {
		return nil, ErrInvalidValue
	}

	// 128 bytes covers every legacy sequence; the Kitty protocol can be longer,
	// hence the retry.
	buf := make([]byte, 128)
	var written C.size_t

	res := C.ghostty_key_encoder_encode(
		e.ptr, ev.ptr,
		(*C.char)(unsafe.Pointer(&buf[0])), C.size_t(len(buf)),
		&written,
	)
	if res == C.GHOSTTY_OUT_OF_SPACE {
		buf = make([]byte, int(written))
		res = C.ghostty_key_encoder_encode(
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
