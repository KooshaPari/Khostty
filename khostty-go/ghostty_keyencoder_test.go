package khostty

import (
	"errors"
	"testing"
)

// Tests for key encoding: text, modifier handling, protocol modes, and the
// encoder lifecycle.

// TestEncodePrintableNeedsText documents that a physical key code alone does
// not say which character was produced.
func TestEncodePrintableNeedsText(t *testing.T) {
	got, err := EncodeKey(KeyA, 0, KeyPress)
	if err != nil {
		t.Fatalf("EncodeKey: %v", err)
	}
	if len(got) != 0 {
		t.Errorf("EncodeKey(KeyA) = %q, want empty without text", got)
	}

	enc, err := NewKeyEncoder()
	if err != nil {
		t.Fatalf("NewKeyEncoder: %v", err)
	}
	defer enc.Close()

	ev, err := NewKeyEvent()
	if err != nil {
		t.Fatalf("NewKeyEvent: %v", err)
	}
	defer ev.Close()

	if err := ev.SetKey(KeyA); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetAction(KeyPress); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetUTF8("a"); err != nil {
		t.Fatal(err)
	}

	out, err := enc.Encode(ev)
	if err != nil {
		t.Fatalf("Encode: %v", err)
	}
	if string(out) != "a" {
		t.Errorf("encoded %q, want %q", out, "a")
	}

	// A non-ASCII character must survive the round trip.
	if err := ev.SetUTF8("é"); err != nil {
		t.Fatal(err)
	}
	out, err = enc.Encode(ev)
	if err != nil {
		t.Fatalf("Encode: %v", err)
	}
	if string(out) != "é" {
		t.Errorf("encoded %q, want %q", out, "é")
	}

	if got, err := ev.UTF8(); err != nil || got != "é" {
		t.Errorf("UTF8() = %q (err %v), want %q", got, err, "é")
	}
}

// TestEncodeAltNeedsBothSettings shows that an Alt prefix requires the DEC
// 1036 mode and the platform option-as-alt setting together.
func TestEncodeAltNeedsBothSettings(t *testing.T) {
	enc, err := NewKeyEncoder()
	if err != nil {
		t.Fatalf("NewKeyEncoder: %v", err)
	}
	defer enc.Close()

	ev, err := NewKeyEvent()
	if err != nil {
		t.Fatalf("NewKeyEvent: %v", err)
	}
	defer ev.Close()

	if err := ev.SetKey(KeyA); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetMods(ModAlt); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetUTF8("a"); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetAction(KeyPress); err != nil {
		t.Fatal(err)
	}

	out, err := enc.Encode(ev)
	if err != nil {
		t.Fatalf("Encode: %v", err)
	}
	if string(out) != "a" {
		t.Errorf("default Alt encoding = %q, want the bare text %q", out, "a")
	}

	if err := enc.SetBool(KeyEncAltEscPrefix, true); err != nil {
		t.Fatal(err)
	}
	if err := enc.SetOptionAsAlt(OptionAsAltTrue); err != nil {
		t.Fatal(err)
	}

	out, err = enc.Encode(ev)
	if err != nil {
		t.Fatalf("Encode: %v", err)
	}
	if string(out) != "\x1ba" {
		t.Errorf("with ESC-prefix Alt = %q, want %q", out, "\x1ba")
	}
}

// TestEncodeModesChangeOutput covers the encoder options that switch encoding
// schemes rather than merely tweaking one sequence.
func TestEncodeModesChangeOutput(t *testing.T) {
	enc, err := NewKeyEncoder()
	if err != nil {
		t.Fatalf("NewKeyEncoder: %v", err)
	}
	defer enc.Close()

	ev, err := NewKeyEvent()
	if err != nil {
		t.Fatalf("NewKeyEvent: %v", err)
	}
	defer ev.Close()

	if err := ev.SetKey(KeyArrowUp); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetAction(KeyPress); err != nil {
		t.Fatal(err)
	}

	out, err := enc.Encode(ev)
	if err != nil {
		t.Fatalf("Encode: %v", err)
	}
	if string(out) != "\x1b[A" {
		t.Errorf("normal cursor keys = %q, want %q", out, "\x1b[A")
	}

	// DEC mode 1 makes arrows emit SS3 sequences instead.
	if err := enc.SetBool(KeyEncCursorKeyApplication, true); err != nil {
		t.Fatal(err)
	}
	out, err = enc.Encode(ev)
	if err != nil {
		t.Fatalf("Encode: %v", err)
	}
	if string(out) != "\x1bOA" {
		t.Errorf("application cursor keys = %q, want %q", out, "\x1bOA")
	}

	// DEC mode 67 switches Backspace between DEL and BS.
	if err := ev.SetKey(KeyBackspace); err != nil {
		t.Fatal(err)
	}
	out, err = enc.Encode(ev)
	if err != nil {
		t.Fatalf("Encode: %v", err)
	}
	if string(out) != "\x7f" {
		t.Errorf("default backspace = %q, want DEL", out)
	}
	if err := enc.SetBool(KeyEncBackarrowKeyMode, true); err != nil {
		t.Fatal(err)
	}
	out, err = enc.Encode(ev)
	if err != nil {
		t.Fatalf("Encode: %v", err)
	}
	if string(out) != "\b" {
		t.Errorf("backarrow mode backspace = %q, want BS", out)
	}
}

// TestKittyEncodingNeedsCodepoint covers the Kitty protocol path, which
// requires the unshifted codepoint as well as the physical key.
func TestKittyEncodingNeedsCodepoint(t *testing.T) {
	enc, err := NewKeyEncoder()
	if err != nil {
		t.Fatalf("NewKeyEncoder: %v", err)
	}
	defer enc.Close()

	if err := enc.SetKittyFlags(KittyAll); err != nil {
		t.Fatal(err)
	}

	ev, err := NewKeyEvent()
	if err != nil {
		t.Fatalf("NewKeyEvent: %v", err)
	}
	defer ev.Close()

	if err := ev.SetKey(KeyC); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetMods(ModCtrl); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetAction(KeyPress); err != nil {
		t.Fatal(err)
	}

	out, err := enc.Encode(ev)
	if err != nil {
		t.Fatalf("Encode: %v", err)
	}
	if len(out) != 0 {
		t.Errorf("Kitty encode without a codepoint = %q, want empty", out)
	}

	if err := ev.SetUnshiftedCodepoint('c'); err != nil {
		t.Fatal(err)
	}
	if got, err := ev.UnshiftedCodepoint(); err != nil || got != 'c' {
		t.Errorf("UnshiftedCodepoint() = %q (err %v), want 'c'", got, err)
	}

	out, err = enc.Encode(ev)
	if err != nil {
		t.Fatalf("Encode: %v", err)
	}
	if string(out) != "\x1b[99;5u" {
		t.Errorf("Kitty ctrl-c = %q, want %q", out, "\x1b[99;5u")
	}
}

// TestKeyEncoderSyncFromTerminal checks that terminal modes reach the encoder,
// which is what makes arrow keys follow the application's DEC mode 1.
func TestKeyEncoderSyncFromTerminal(t *testing.T) {
	term := newTestTerminal(t, 80, 24)

	enc, err := NewKeyEncoder()
	if err != nil {
		t.Fatalf("NewKeyEncoder: %v", err)
	}
	defer enc.Close()

	ev, err := NewKeyEvent()
	if err != nil {
		t.Fatalf("NewKeyEvent: %v", err)
	}
	defer ev.Close()

	if err := ev.SetKey(KeyArrowUp); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetAction(KeyPress); err != nil {
		t.Fatal(err)
	}

	// The application enables application cursor keys.
	term.WriteString("\x1b[?1h")

	if err := enc.SyncFromTerminal(term); err != nil {
		t.Fatalf("SyncFromTerminal: %v", err)
	}

	out, err := enc.Encode(ev)
	if err != nil {
		t.Fatalf("Encode: %v", err)
	}
	if string(out) != "\x1bOA" {
		t.Errorf("after syncing DEC mode 1, arrow = %q, want %q", out, "\x1bOA")
	}

	// A closed terminal must be refused rather than synced from.
	closed := newTestTerminal(t, 80, 24)
	_ = closed.Close()
	if err := enc.SyncFromTerminal(closed); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("SyncFromTerminal(closed) = %v, want ErrInvalidValue", err)
	}
	var nilTerm *Terminal
	if err := enc.SyncFromTerminal(nilTerm); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("SyncFromTerminal(nil) = %v, want ErrInvalidValue", err)
	}
}

// TestKeyEncoderUseAfterClose checks the guards on released handles.
func TestKeyEncoderUseAfterClose(t *testing.T) {
	enc, err := NewKeyEncoder()
	if err != nil {
		t.Fatalf("NewKeyEncoder: %v", err)
	}
	if err := enc.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if err := enc.Close(); err != nil {
		t.Fatalf("second Close: %v", err)
	}

	ev, err := NewKeyEvent()
	if err != nil {
		t.Fatalf("NewKeyEvent: %v", err)
	}
	defer ev.Close()
	if err := ev.SetKey(KeyA); err != nil {
		t.Fatal(err)
	}

	if _, err := enc.Encode(ev); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("Encode after Close = %v, want ErrInvalidValue", err)
	}
	if err := enc.SetKittyFlags(KittyAll); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("SetKittyFlags after Close = %v, want ErrInvalidValue", err)
	}

	if err := ev.Close(); err != nil {
		t.Fatalf("event Close: %v", err)
	}

	open, err := NewKeyEncoder()
	if err != nil {
		t.Fatalf("NewKeyEncoder: %v", err)
	}
	defer open.Close()
	if _, err := open.Encode(ev); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("Encode with a closed event = %v, want ErrInvalidValue", err)
	}
	if _, err := open.Encode(nil); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("Encode(nil) = %v, want ErrInvalidValue", err)
	}

	var nilEvent *KeyEvent
	if err := nilEvent.Close(); err != nil {
		t.Errorf("nil event Close = %v, want nil", err)
	}
	if err := nilEvent.SetKey(KeyA); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("nil event SetKey = %v, want ErrInvalidValue", err)
	}
	var nilEncoder *KeyEncoder
	if err := nilEncoder.Close(); err != nil {
		t.Errorf("nil encoder Close = %v, want nil", err)
	}
	if _, err := nilEncoder.Encode(ev); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("nil encoder Encode = %v, want ErrInvalidValue", err)
	}
}
