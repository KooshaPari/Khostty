package khostty

import (
	"errors"
	"testing"
)

// Tests for mouse event and encoder state, lifecycle, and terminal sync.

// TestMouseEventStateRoundTrip covers the setters and getters.
func TestMouseEventStateRoundTrip(t *testing.T) {
	ev, err := NewMouseEvent()
	if err != nil {
		t.Fatalf("NewMouseEvent: %v", err)
	}
	defer ev.Close()

	if err := ev.SetAction(MouseMotion); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetButton(MouseMiddle); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetMods(ModShift); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetPosition(MousePosition{X: 12.5, Y: 34.25}); err != nil {
		t.Fatal(err)
	}

	if got, err := ev.Action(); err != nil || got != MouseMotion {
		t.Errorf("Action() = %v (err %v), want MouseMotion", got, err)
	}
	if got, ok, err := ev.Button(); err != nil || !ok || got != MouseMiddle {
		t.Errorf("Button() = %v, %v (err %v), want MouseMiddle", got, ok, err)
	}
	if got, err := ev.Mods(); err != nil || got != ModShift {
		t.Errorf("Mods() = %v (err %v), want shift", got, err)
	}
	if got, err := ev.Position(); err != nil || got.X != 12.5 || got.Y != 34.25 {
		t.Errorf("Position() = %v (err %v), want (12.5, 34.25)", got, err)
	}

	// Clearing the button must be distinguishable from the UNKNOWN button.
	if err := ev.ClearButton(); err != nil {
		t.Fatal(err)
	}
	if got, ok, err := ev.Button(); err != nil || ok {
		t.Errorf("Button() after ClearButton = %v, %v (err %v), want not set", got, ok, err)
	}
}

// TestMouseEncoderLifecycleGuards covers Reset, track-last-cell, and the
// closed-handle guards.
func TestMouseEncoderLifecycleGuards(t *testing.T) {
	enc, ev := mouseFixture(t)

	if err := enc.SetTrackLastCell(true); err != nil {
		t.Fatalf("SetTrackLastCell: %v", err)
	}
	if err := enc.Reset(); err != nil {
		t.Fatalf("Reset: %v", err)
	}
	if err := enc.SetAnyButtonPressed(true); err != nil {
		t.Fatalf("SetAnyButtonPressed: %v", err)
	}

	if err := enc.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if err := enc.Close(); err != nil {
		t.Fatalf("second Close: %v", err)
	}

	if _, err := enc.Encode(ev); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("Encode after Close = %v, want ErrInvalidValue", err)
	}
	if err := enc.SetFormat(MouseFormatSGR); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("SetFormat after Close = %v, want ErrInvalidValue", err)
	}
	if err := enc.Reset(); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("Reset after Close = %v, want ErrInvalidValue", err)
	}

	if err := ev.Close(); err != nil {
		t.Fatalf("event Close: %v", err)
	}
	open, err := NewMouseEncoder()
	if err != nil {
		t.Fatalf("NewMouseEncoder: %v", err)
	}
	defer open.Close()
	if _, err := open.Encode(ev); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("Encode with a closed event = %v, want ErrInvalidValue", err)
	}
	if _, err := open.Encode(nil); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("Encode(nil) = %v, want ErrInvalidValue", err)
	}

	var nilEncoder *MouseEncoder
	if err := nilEncoder.Close(); err != nil {
		t.Errorf("nil encoder Close = %v, want nil", err)
	}
	if _, err := nilEncoder.Encode(ev); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("nil encoder Encode = %v, want ErrInvalidValue", err)
	}
	var nilEvent *MouseEvent
	if err := nilEvent.Close(); err != nil {
		t.Errorf("nil event Close = %v, want nil", err)
	}
	if err := nilEvent.SetButton(MouseLeft); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("nil event SetButton = %v, want ErrInvalidValue", err)
	}
}

// TestMouseEncoderSyncFromTerminal checks that the tracking mode the
// application enabled reaches the encoder.
func TestMouseEncoderSyncFromTerminal(t *testing.T) {
	term := newTestTerminal(t, 80, 24)
	term.WriteString("\x1b[?1000h") // normal mouse tracking

	enc, ev := mouseFixture(t)
	if err := enc.SyncFromTerminal(term); err != nil {
		t.Fatalf("SyncFromTerminal: %v", err)
	}
	if err := enc.SetFormat(MouseFormatSGR); err != nil {
		t.Fatal(err)
	}

	if err := ev.SetAction(MousePress); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetButton(MouseLeft); err != nil {
		t.Fatal(err)
	}
	if got := mustEncode(t, enc, ev); got == "" {
		t.Error("a press should still encode after syncing from a tracking terminal")
	}

	// With no tracking enabled there is nothing to report.
	quiet := newTestTerminal(t, 80, 24)
	other, otherEvent := mouseFixture(t)
	if err := other.SyncFromTerminal(quiet); err != nil {
		t.Fatalf("SyncFromTerminal: %v", err)
	}
	if err := otherEvent.SetAction(MousePress); err != nil {
		t.Fatal(err)
	}
	if err := otherEvent.SetButton(MouseLeft); err != nil {
		t.Fatal(err)
	}
	if got := mustEncode(t, other, otherEvent); got != "" {
		t.Errorf("press with tracking disabled = %q, want empty", got)
	}

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

// TestMouseEncodingEntersTheTerminal closes the loop: sync an encoder from a
// terminal that enabled mouse reporting, encode a press, and feed it back. A
// well-formed sequence is consumed by the terminal rather than printed, so the
// screen stays empty.
//
// Both the tracking mode and the wire format have to match what the terminal
// was told, which is exactly why the encoder is synced rather than configured
// by hand here.
func TestMouseEncodingEntersTheTerminal(t *testing.T) {
	term := newTestTerminal(t, 80, 24)
	// 1000 = normal tracking, 1006 = SGR extended coordinates.
	term.WriteString("\x1b[?1000h\x1b[?1006h")

	if tracking, err := term.MouseTracking(); err != nil || !tracking {
		t.Fatalf("MouseTracking = %v (err %v), want true", tracking, err)
	}

	enc, ev := mouseFixture(t)
	if err := enc.SyncFromTerminal(term); err != nil {
		t.Fatalf("SyncFromTerminal: %v", err)
	}
	if err := enc.SetSize(EncoderSize{
		ScreenWidth: 800, ScreenHeight: 600,
		CellWidth: 10, CellHeight: 20,
	}); err != nil {
		t.Fatalf("SetSize: %v", err)
	}

	before, err := term.CursorY()
	if err != nil {
		t.Fatal(err)
	}

	if err := ev.SetAction(MousePress); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetButton(MouseLeft); err != nil {
		t.Fatal(err)
	}
	seq := mustEncode(t, enc, ev)
	if seq == "" {
		t.Fatal("encoder produced no sequence")
	}
	if seq != "\x1b[<0;6;3M" {
		t.Fatalf("synced encoder emitted %q, want the SGR form", seq)
	}

	term.WriteString(seq)

	if got := screenText(t, term); got != "" {
		t.Errorf("terminal printed the mouse sequence instead of consuming it: %q", got)
	}
	if after, err := term.CursorY(); err != nil || after != before {
		t.Errorf("cursor row = %d (err %v), want %d unchanged", after, err, before)
	}
	if ground, err := term.VTGround(); err != nil || !ground {
		t.Errorf("VTGround = %v (err %v), want true after a complete sequence", ground, err)
	}
}
