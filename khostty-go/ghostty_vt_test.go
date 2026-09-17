package khostty

import (
	"errors"
	"strings"
	"testing"
	"unsafe"
)

// Tests for the Terminal lifecycle and state reads.
// TestTerminalResetAndResize covers the two mutating lifecycle calls.
func TestTerminalResetAndResize(t *testing.T) {
	term := newTestTerminal(t, 80, 24)
	term.WriteString("hello\r\nworld")

	term.Reset()
	if got := screenText(t, term); got != "" {
		t.Errorf("screen after Reset = %q, want empty", got)
	}
	if cy, _ := term.CursorY(); cy != 0 {
		t.Errorf("cursor row after Reset = %d, want 0", cy)
	}

	if err := term.Resize(100, 30, 8, 16); err != nil {
		t.Fatalf("Resize: %v", err)
	}
	if cols, _ := term.Cols(); cols != 100 {
		t.Errorf("Cols = %d, want 100", cols)
	}
	if rows, _ := term.Rows(); rows != 30 {
		t.Errorf("Rows = %d, want 30", rows)
	}
	w, err := term.WidthPx()
	if err != nil {
		t.Fatalf("WidthPx: %v", err)
	}
	h, err := term.HeightPx()
	if err != nil {
		t.Fatalf("HeightPx: %v", err)
	}
	if w != 800 || h != 480 {
		t.Errorf("pixel size = %dx%d, want 800x480", w, h)
	}

	if err := term.Resize(0, 30, 8, 16); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("Resize(0,...) error = %v, want ErrInvalidValue", err)
	}

	term.Reset()
	if cols, _ := term.Cols(); cols != 100 {
		t.Errorf("Reset changed columns to %d, want 100 preserved", cols)
	}
}

// TestTerminalWriteAndReadScreen is the primary end-to-end path: create a
// terminal, feed VT bytes, read the screen back as text.
func TestTerminalWriteAndReadScreen(t *testing.T) {
	term := newTestTerminal(t, 80, 24)

	term.WriteString("Line 1: Hello World!\r\n")
	term.WriteString("Line 2: \x1b[1mBold\x1b[0m and \x1b[4mUnderline\x1b[0m\r\n")
	term.WriteString("Line 3\r\n")

	got := screenText(t, term)
	for _, want := range []string{
		"Line 1: Hello World!",
		"Line 2: Bold and Underline",
		"Line 3",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("screen text is missing %q\n--- screen ---\n%s", want, got)
		}
	}

	// Styling must not leak into the plain-text form.
	if strings.Contains(got, "\x1b") {
		t.Errorf("plain text contains escape sequences: %q", got)
	}
}

// TestTerminalUseAfterClose verifies the guard on a released handle.
func TestTerminalUseAfterClose(t *testing.T) {
	term := newTestTerminal(t, 80, 24)
	if err := term.Close(); err != nil {
		t.Fatalf("first Close: %v", err)
	}
	if err := term.Close(); err != nil {
		t.Fatalf("second Close: %v", err)
	}

	if _, err := term.Cols(); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("Cols after Close = %v, want ErrInvalidValue", err)
	}
	if _, err := term.Text(); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("Text after Close = %v, want ErrInvalidValue", err)
	}
	if err := term.Resize(80, 24, 0, 0); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("Resize after Close = %v, want ErrInvalidValue", err)
	}
	if _, err := term.Snapshot(); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("Snapshot after Close = %v, want ErrInvalidValue", err)
	}
	term.WriteString("must not panic")
	term.Reset()

	var nilTerm *Terminal
	if err := nilTerm.Close(); err != nil {
		t.Errorf("Close on nil = %v, want nil", err)
	}
	if _, err := nilTerm.Cols(); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("Cols on nil = %v, want ErrInvalidValue", err)
	}
}

// TestTerminalCursorReports checks cursor tracking and deferred wrap, which is
// what an agent needs to reason about where the next write lands.
func TestTerminalCursorReports(t *testing.T) {
	term := newTestTerminal(t, 80, 24)

	term.WriteString("hello\r\nworld")
	cx, err := term.CursorX()
	if err != nil {
		t.Fatalf("CursorX: %v", err)
	}
	cy, err := term.CursorY()
	if err != nil {
		t.Fatalf("CursorY: %v", err)
	}
	if cx != 5 || cy != 1 {
		t.Errorf("cursor = (%d,%d), want (5,1)", cx, cy)
	}

	// CUP must move the cursor and leave no pending wrap.
	term.WriteString("\x1b[10;20H")
	cx, _ = term.CursorX()
	cy, _ = term.CursorY()
	if cx != 19 || cy != 9 {
		t.Errorf("after CUP cursor = (%d,%d), want (19,9)", cx, cy)
	}
	if pw, err := term.CursorPendingWrap(); err != nil || pw {
		t.Errorf("CursorPendingWrap = %v (err %v), want false", pw, err)
	}

	if ground, err := term.VTGround(); err != nil || !ground {
		t.Errorf("VTGround = %v (err %v), want true after complete sequences", ground, err)
	}
}

// TestTerminalScreenSwitching checks alternate-screen reporting and the OSC
// title/pwd reads that agents use for session context.
func TestTerminalScreenSwitching(t *testing.T) {
	term := newTestTerminal(t, 80, 24)

	if s, err := term.ActiveScreen(); err != nil || s != ScreenPrimary {
		t.Errorf("initial screen = %v (err %v), want primary", s, err)
	}

	term.WriteString("\x1b[?1049h")
	if s, err := term.ActiveScreen(); err != nil || s != ScreenAlternate {
		t.Errorf("after 1049h screen = %v (err %v), want alternate", s, err)
	}
	term.WriteString("\x1b[?1049l")
	if s, err := term.ActiveScreen(); err != nil || s != ScreenPrimary {
		t.Errorf("after 1049l screen = %v (err %v), want primary", s, err)
	}
	if ScreenPrimary.String() != "primary" || ScreenAlternate.String() != "alternate" {
		t.Error("Screen.String() is not table-driven")
	}

	term.WriteString("\x1b]0;my-title\x07")
	if title, err := term.Title(); err != nil || title != "my-title" {
		t.Errorf("Title = %q (err %v), want %q", title, err, "my-title")
	}

	term.WriteString("\x1b]7;file://localhost/tmp/proj\x07")
	pwd, err := term.Pwd()
	if err != nil {
		t.Fatalf("Pwd: %v", err)
	}
	if !strings.Contains(pwd, "/tmp/proj") {
		t.Errorf("Pwd = %q, want it to contain /tmp/proj", pwd)
	}
}

// TestNewTerminalValidation checks the argument guard that keeps a zero-sized
// grid from reaching the library.
func TestNewTerminalValidation(t *testing.T) {
	for _, tc := range []struct{ cols, rows int }{
		{0, 24}, {80, 0}, {-1, 24}, {80, -1},
	} {
		if _, err := NewTerminal(tc.cols, tc.rows); err == nil {
			t.Errorf("NewTerminal(%d,%d) succeeded, want error", tc.cols, tc.rows)
		} else if !errors.Is(err, ErrInvalidValue) {
			t.Errorf("NewTerminal(%d,%d) error = %v, want ErrInvalidValue", tc.cols, tc.rows, err)
		}
	}
}

// TestWriteUntilGround covers the incremental-write contract: at ground the
// call consumes nothing, and mid-sequence it consumes exactly through the byte
// that returns the stream to ground.
func TestWriteUntilGround(t *testing.T) {
	term := newTestTerminal(t, 40, 4)

	// Already at ground: nothing to consume, and that is success.
	n, ok := term.WriteUntilGround([]byte("plain text"))
	if !ok {
		t.Fatal("WriteUntilGround at ground returned ok=false")
	}
	if n != 0 {
		t.Errorf("consumed %d bytes at ground, want 0", n)
	}
	if g, err := term.VTGround(); err != nil || !g {
		t.Errorf("VTGround = %v (err %v), want true", g, err)
	}

	// Leave the parser inside a CSI, then feed the remainder.
	term.WriteString("\x1b[3")
	if g, _ := term.VTGround(); g {
		t.Fatal("stream is still at ground after a partial CSI")
	}

	n, ok = term.WriteUntilGround([]byte("1m;hello"))
	if !ok {
		t.Fatal("WriteUntilGround did not reach ground")
	}
	if n != 2 {
		t.Errorf("consumed %d bytes, want 2 (through the CSI final byte)", n)
	}
	if g, _ := term.VTGround(); !g {
		t.Error("stream is not at ground after the final byte was consumed")
	}
	// The bytes after ground are left for the caller, not consumed.
	if n >= len("1m;hello") {
		t.Error("WriteUntilGround consumed past ground")
	}
}

// TestContinuationOption checks the option plumbing for the continuation
// tracking that snapshots rely on to capture unfinished parser state.
func TestContinuationOption(t *testing.T) {
	term := newTestTerminal(t, 40, 4)

	var before uint64
	if err := term.Data(DataContinuationMaxBytes, unsafe.Pointer(&before)); err != nil {
		t.Fatalf("Data(DataContinuationMaxBytes): %v", err)
	}

	if err := term.SetSize(OptContinuationMaxBytes, 4096); err != nil {
		t.Fatalf("SetSize(OptContinuationMaxBytes): %v", err)
	}

	var after uint64
	if err := term.Data(DataContinuationMaxBytes, unsafe.Pointer(&after)); err != nil {
		t.Fatalf("Data(DataContinuationMaxBytes): %v", err)
	}
	if after != 4096 {
		t.Errorf("continuation limit = %d, want 4096 (was %d)", after, before)
	}

	// Option plumbing for the other scalar kinds must not error either.
	if err := term.SetBool(OptDefaultCursorBlink, true); err != nil {
		t.Errorf("SetBool(OptDefaultCursorBlink): %v", err)
	}
	// The scrollback budget is a size_t option an embedding application
	// typically sets right after construction.
	if err := term.SetSize(OptScrollbackMaxLines, 10_000); err != nil {
		t.Errorf("SetSize(OptScrollbackMaxLines): %v", err)
	}
}
