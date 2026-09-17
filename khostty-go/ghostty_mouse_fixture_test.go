package khostty

import "testing"

// Shared fixture for the mouse tests.

// mouseFixture builds an encoder configured for SGR reporting on a 800x600
// surface with 10x20 cells, plus a reusable event.
func mouseFixture(t *testing.T) (*MouseEncoder, *MouseEvent) {
	t.Helper()

	enc, err := NewMouseEncoder()
	if err != nil {
		t.Fatalf("NewMouseEncoder: %v", err)
	}
	t.Cleanup(func() { _ = enc.Close() })

	if err := enc.SetTrackLastCell(false); err != nil {
		t.Fatalf("SetTrackLastCell: %v", err)
	}
	if err := enc.SetFormat(MouseFormatSGR); err != nil {
		t.Fatalf("SetFormat: %v", err)
	}
	if err := enc.SetTrackingMode(MouseTrackingNormal); err != nil {
		t.Fatalf("SetTrackingMode: %v", err)
	}
	if err := enc.SetSize(EncoderSize{
		ScreenWidth: 800, ScreenHeight: 600,
		CellWidth: 10, CellHeight: 20,
	}); err != nil {
		t.Fatalf("SetSize: %v", err)
	}

	ev, err := NewMouseEvent()
	if err != nil {
		t.Fatalf("NewMouseEvent: %v", err)
	}
	t.Cleanup(func() { _ = ev.Close() })

	if err := ev.SetPosition(MousePosition{X: 50, Y: 40}); err != nil {
		t.Fatalf("SetPosition: %v", err)
	}
	return enc, ev
}

func mustEncode(t *testing.T, enc *MouseEncoder, ev *MouseEvent) string {
	t.Helper()
	out, err := enc.Encode(ev)
	if err != nil {
		t.Fatalf("Encode: %v", err)
	}
	return string(out)
}
