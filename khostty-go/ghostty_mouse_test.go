package khostty

import "testing"

// Tests for mouse encoding: formats, tracking modes, modifiers, and the
// pixel-to-cell mapping. The shared fixture is in ghostty_mouse_fixture_test.go.

// TestMousePressAndReleaseSGR is the primary path: a left press and release at
// pixel (50,40) on 10x20 cells, which is cell (6,3) one-based.
func TestMousePressAndReleaseSGR(t *testing.T) {
	enc, ev := mouseFixture(t)

	if err := ev.SetAction(MousePress); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetButton(MouseLeft); err != nil {
		t.Fatal(err)
	}
	if got := mustEncode(t, enc, ev); got != "\x1b[<0;6;3M" {
		t.Errorf("SGR press = %q, want %q", got, "\x1b[<0;6;3M")
	}

	// SGR distinguishes release with a lowercase final byte.
	if err := ev.SetAction(MouseRelease); err != nil {
		t.Fatal(err)
	}
	if got := mustEncode(t, enc, ev); got != "\x1b[<0;6;3m" {
		t.Errorf("SGR release = %q, want %q", got, "\x1b[<0;6;3m")
	}
}

// TestMouseFormats pins one press per wire format.
func TestMouseFormats(t *testing.T) {
	cases := []struct {
		format MouseFormat
		want   string
	}{
		{MouseFormatX10, "\x1b[M &#"},
		{MouseFormatUTF8, "\x1b[M &#"},
		{MouseFormatSGR, "\x1b[<0;6;3M"},
		{MouseFormatURXVT, "\x1b[32;6;3M"},
		{MouseFormatSGRPixels, "\x1b[<0;50;40M"},
	}

	for _, tc := range cases {
		t.Run(tc.format.String(), func(t *testing.T) {
			enc, ev := mouseFixture(t)
			if err := enc.SetFormat(tc.format); err != nil {
				t.Fatal(err)
			}
			if err := ev.SetAction(MousePress); err != nil {
				t.Fatal(err)
			}
			if err := ev.SetButton(MouseLeft); err != nil {
				t.Fatal(err)
			}
			if got := mustEncode(t, enc, ev); got != tc.want {
				t.Errorf("format %d press = %q, want %q", int(tc.format), got, tc.want)
			}
		})
	}
}

// TestMotionDependsOnTrackingMode shows that the same motion event is reported
// or dropped depending on what the application asked for.
func TestMotionDependsOnTrackingMode(t *testing.T) {
	cases := []struct {
		mode MouseTrackingMode
		want string
	}{
		// Presses and releases only: motion is not reportable.
		{MouseTrackingNormal, ""},
		// Reports drags while a button is held.
		{MouseTrackingButton, ""},
		// Reports all motion.
		{MouseTrackingAny, "\x1b[<35;6;3M"},
	}

	for _, tc := range cases {
		t.Run(tc.mode.String(), func(t *testing.T) {
			enc, ev := mouseFixture(t)
			if err := enc.SetTrackingMode(tc.mode); err != nil {
				t.Fatal(err)
			}
			if err := ev.SetAction(MouseMotion); err != nil {
				t.Fatal(err)
			}
			if err := ev.ClearButton(); err != nil {
				t.Fatal(err)
			}
			if err := enc.SetAnyButtonPressed(false); err != nil {
				t.Fatal(err)
			}
			if got := mustEncode(t, enc, ev); got != tc.want {
				t.Errorf("motion in mode %d = %q, want %q", int(tc.mode), got, tc.want)
			}
		})
	}

	// A drag (motion with a button held) is reported in Button mode.
	enc, ev := mouseFixture(t)
	if err := enc.SetTrackingMode(MouseTrackingButton); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetAction(MouseMotion); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetButton(MouseLeft); err != nil {
		t.Fatal(err)
	}
	if err := enc.SetAnyButtonPressed(true); err != nil {
		t.Fatal(err)
	}
	if got := mustEncode(t, enc, ev); got != "\x1b[<32;6;3M" {
		t.Errorf("drag in Button mode = %q, want %q", got, "\x1b[<32;6;3M")
	}
}

// TestModifiersShiftTheButtonCode checks the SGR button-code arithmetic.
func TestModifiersShiftTheButtonCode(t *testing.T) {
	cases := []struct {
		mods Mods
		want string
	}{
		{0, "\x1b[<0;6;3M"},
		{ModShift, "\x1b[<4;6;3M"},
		{ModAlt, "\x1b[<8;6;3M"},
		{ModCtrl, "\x1b[<16;6;3M"},
		{ModShift | ModCtrl, "\x1b[<20;6;3M"},
	}

	for _, tc := range cases {
		t.Run(tc.mods.String(), func(t *testing.T) {
			enc, ev := mouseFixture(t)
			if err := ev.SetAction(MousePress); err != nil {
				t.Fatal(err)
			}
			if err := ev.SetButton(MouseLeft); err != nil {
				t.Fatal(err)
			}
			if err := ev.SetMods(tc.mods); err != nil {
				t.Fatal(err)
			}
			if got := mustEncode(t, enc, ev); got != tc.want {
				t.Errorf("press with %s = %q, want %q", tc.mods, got, tc.want)
			}
		})
	}
}

// TestPixelToCellMapping checks that the configured cell size is what turns a
// pixel position into a cell, and that padding is subtracted first.
func TestPixelToCellMapping(t *testing.T) {
	enc, ev := mouseFixture(t)
	if err := ev.SetAction(MousePress); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetButton(MouseLeft); err != nil {
		t.Fatal(err)
	}

	// 50/10 = column 5, 40/20 = row 2, one-based.
	if got := mustEncode(t, enc, ev); got != "\x1b[<0;6;3M" {
		t.Errorf("unpadded mapping = %q, want %q", got, "\x1b[<0;6;3M")
	}

	// Padding shifts the origin, so the same pixel is one column and one row
	// lower.
	if err := enc.SetSize(EncoderSize{
		ScreenWidth: 800, ScreenHeight: 600,
		CellWidth: 10, CellHeight: 20,
		PaddingLeft: 10, PaddingTop: 20,
	}); err != nil {
		t.Fatal(err)
	}
	if got := mustEncode(t, enc, ev); got != "\x1b[<0;5;2M" {
		t.Errorf("padded mapping = %q, want %q", got, "\x1b[<0;5;2M")
	}
}
