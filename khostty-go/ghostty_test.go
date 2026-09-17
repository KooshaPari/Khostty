package khostty

import (
	"testing"
)

// Shared test helpers. The per-concern test files carry the cases:
// ffi_test.go, ghostty_vt_test.go, ghostty_snapshot_test.go,
// ghostty_render_test.go, and ghostty_search_test.go.
// newTestTerminal creates a terminal that is closed when the test ends.
func newTestTerminal(t *testing.T, cols, rows int) *Terminal {
	t.Helper()
	term, err := NewTerminal(cols, rows)
	if err != nil {
		t.Fatalf("NewTerminal(%d,%d): %v", cols, rows, err)
	}
	t.Cleanup(func() { _ = term.Close() })
	return term
}

// screenText reads the visible screen as trimmed plain text.
func screenText(t *testing.T, term *Terminal) string {
	t.Helper()
	text, err := term.Text()
	if err != nil {
		t.Fatalf("Text(): %v", err)
	}
	return text
}
