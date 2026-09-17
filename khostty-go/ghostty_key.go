package khostty

/*
#include <stdlib.h>
#include <ghostty/vt.h>
*/
import "C"

// Key is a physical key code, mirroring GhosttyKey.
//
// The named constants live in keys_gen.go, generated from the library's own
// type manifest. A raw integer is also valid, which is what a caller needs when
// forwarding a key this build does not name.
type Key int32

// Mods is a bitmask of held modifiers, mirroring the GHOSTTY_MODS_* constants.
//
// Side bits are only meaningful when the corresponding base modifier is set.
type Mods uint16

// Modifier bits.
const (
	// ModShift is the Shift key.
	ModShift Mods = C.GHOSTTY_MODS_SHIFT
	// ModCtrl is the Control key.
	ModCtrl Mods = C.GHOSTTY_MODS_CTRL
	// ModAlt is the Alt/Option key.
	ModAlt Mods = C.GHOSTTY_MODS_ALT
	// ModSuper is the Super/Command/Windows key.
	ModSuper Mods = C.GHOSTTY_MODS_SUPER
	// ModCapsLock reports the Caps Lock latch.
	ModCapsLock Mods = C.GHOSTTY_MODS_CAPS_LOCK
	// ModNumLock reports the Num Lock latch.
	ModNumLock Mods = C.GHOSTTY_MODS_NUM_LOCK
	// ModShiftSide distinguishes right Shift from left.
	ModShiftSide Mods = C.GHOSTTY_MODS_SHIFT_SIDE
	// ModCtrlSide distinguishes right Control from left.
	ModCtrlSide Mods = C.GHOSTTY_MODS_CTRL_SIDE
	// ModAltSide distinguishes right Alt from left.
	ModAltSide Mods = C.GHOSTTY_MODS_ALT_SIDE
	// ModSuperSide distinguishes right Super from left.
	ModSuperSide Mods = C.GHOSTTY_MODS_SUPER_SIDE
)

// Has reports whether every bit in other is set.
func (m Mods) Has(other Mods) bool { return m&other == other }

// String renders the held modifiers, for logs and test failures.
func (m Mods) String() string {
	names := []struct {
		bit  Mods
		name string
	}{
		{ModShift, "shift"},
		{ModCtrl, "ctrl"},
		{ModAlt, "alt"},
		{ModSuper, "super"},
		{ModCapsLock, "caps"},
		{ModNumLock, "num"},
	}
	out := "mods{"
	first := true
	for _, n := range names {
		if !m.Has(n.bit) {
			continue
		}
		if !first {
			out += ","
		}
		out += n.name
		first = false
	}
	return out + "}"
}

// KeyAction identifies an event's phase.
type KeyAction C.GhosttyKeyAction

// Key actions.
const (
	// KeyRelease is a key release.
	KeyRelease KeyAction = C.GHOSTTY_KEY_ACTION_RELEASE
	// KeyPress is a key press.
	KeyPress KeyAction = C.GHOSTTY_KEY_ACTION_PRESS
	// KeyRepeat is an auto-repeat while held.
	KeyRepeat KeyAction = C.GHOSTTY_KEY_ACTION_REPEAT
)

// OptionAsAlt selects how the platform's Option key is reported.
type OptionAsAlt C.GhosttyOptionAsAlt

// Option-as-Alt behaviours.
const (
	// OptionAsAltFalse never treats Option as Alt.
	OptionAsAltFalse OptionAsAlt = C.GHOSTTY_OPTION_AS_ALT_FALSE
	// OptionAsAltTrue always treats Option as Alt.
	OptionAsAltTrue OptionAsAlt = C.GHOSTTY_OPTION_AS_ALT_TRUE
	// OptionAsAltLeft treats only the left Option key as Alt.
	OptionAsAltLeft OptionAsAlt = C.GHOSTTY_OPTION_AS_ALT_LEFT
	// OptionAsAltRight treats only the right Option key as Alt.
	OptionAsAltRight OptionAsAlt = C.GHOSTTY_OPTION_AS_ALT_RIGHT
)

// KittyFlags is the Kitty keyboard protocol flag bitmask, mirroring the
// GHOSTTY_KITTY_KEY_* constants. It is passed through to the encoder verbatim.
type KittyFlags uint8

// Kitty keyboard protocol flags.
const (
	// KittyDisabled disables Kitty encoding.
	KittyDisabled KittyFlags = C.GHOSTTY_KITTY_KEY_DISABLED
	// KittyDisambiguate reports key events unambiguously.
	KittyDisambiguate KittyFlags = C.GHOSTTY_KITTY_KEY_DISAMBIGUATE
	// KittyReportEvents includes press/repeat/release in the encoding.
	KittyReportEvents KittyFlags = C.GHOSTTY_KITTY_KEY_REPORT_EVENTS
	// KittyReportAlternates reports alternate keys, such as shifted variants.
	KittyReportAlternates KittyFlags = C.GHOSTTY_KITTY_KEY_REPORT_ALTERNATES
	// KittyReportAll reports all keys, not only those with a text form.
	KittyReportAll KittyFlags = C.GHOSTTY_KITTY_KEY_REPORT_ALL
	// KittyReportAssociated reports associated text.
	KittyReportAssociated KittyFlags = C.GHOSTTY_KITTY_KEY_REPORT_ASSOCIATED
	// KittyAll enables every Kitty feature, as the C example does.
	KittyAll KittyFlags = C.GHOSTTY_KITTY_KEY_ALL
)

// KeyEncoderOption identifies a writable encoder setting.
type KeyEncoderOption C.GhosttyKeyEncoderOption

// Key encoder options.
const (
	// KeyEncCursorKeyApplication sets DEC mode 1 (bool).
	KeyEncCursorKeyApplication KeyEncoderOption = C.GHOSTTY_KEY_ENCODER_OPT_CURSOR_KEY_APPLICATION
	// KeyEncKeypadKeyApplication sets DEC mode 66 (bool).
	KeyEncKeypadKeyApplication KeyEncoderOption = C.GHOSTTY_KEY_ENCODER_OPT_KEYPAD_KEY_APPLICATION
	// KeyEncIgnoreKeypadWithNumlock sets DEC mode 1035 (bool).
	KeyEncIgnoreKeypadWithNumlock KeyEncoderOption = C.GHOSTTY_KEY_ENCODER_OPT_IGNORE_KEYPAD_WITH_NUMLOCK
	// KeyEncAltEscPrefix sets DEC mode 1036, Alt sends an ESC prefix (bool).
	KeyEncAltEscPrefix KeyEncoderOption = C.GHOSTTY_KEY_ENCODER_OPT_ALT_ESC_PREFIX
	// KeyEncModifyOtherKeysState2 sets xterm modifyOtherKeys mode 2 (bool).
	KeyEncModifyOtherKeysState2 KeyEncoderOption = C.GHOSTTY_KEY_ENCODER_OPT_MODIFY_OTHER_KEYS_STATE_2
	// KeyEncKittyFlags sets the Kitty protocol flags (KittyFlags).
	KeyEncKittyFlags KeyEncoderOption = C.GHOSTTY_KEY_ENCODER_OPT_KITTY_FLAGS
	// KeyEncMacOSOptionAsAlt sets Option-as-Alt behaviour (OptionAsAlt).
	KeyEncMacOSOptionAsAlt KeyEncoderOption = C.GHOSTTY_KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT
	// KeyEncBackarrowKeyMode switches Backspace between 0x7f and 0x08 (bool).
	KeyEncBackarrowKeyMode KeyEncoderOption = C.GHOSTTY_KEY_ENCODER_OPT_BACKARROW_KEY_MODE
)

// EncodeKey is the one-shot convenience for a single keystroke.
//
// It allocates an encoder and an event per call, which is right for tests and
// occasional use. Hot paths should keep a KeyEncoder and one reused KeyEvent.
//
// No text is set, so it is suitable for keys that encode without it: control
// characters, Escape, Enter, Tab, Backspace, arrows, and function keys. Use a
// KeyEncoder directly when the key produces text.
func EncodeKey(key Key, mods Mods, action KeyAction) ([]byte, error) {
	enc, err := NewKeyEncoder()
	if err != nil {
		return nil, err
	}
	defer enc.Close()

	ev, err := NewKeyEvent()
	if err != nil {
		return nil, err
	}
	defer ev.Close()

	if err := ev.SetKey(key); err != nil {
		return nil, err
	}
	if err := ev.SetMods(mods); err != nil {
		return nil, err
	}
	if err := ev.SetAction(action); err != nil {
		return nil, err
	}
	return enc.Encode(ev)
}
