package khostty

import (
	"errors"
	"testing"
)

// Tests for scrollback search.
// TestSearchNoMatches checks that selecting with zero matches reports
// ErrNoValue instead of panicking or silently succeeding.
func TestSearchNoMatches(t *testing.T) {
	term := newTestTerminal(t, 40, 4)
	term.WriteString("nothing to see\r\n")

	s, err := NewSearch(term)
	if err != nil {
		t.Fatalf("NewSearch: %v", err)
	}
	defer s.Close()

	if err := s.SetNeedle("absent-needle"); err != nil {
		t.Fatalf("SetNeedle: %v", err)
	}
	if err := s.Run(); err != nil {
		t.Fatalf("Run: %v", err)
	}
	if n, _ := s.TotalMatches(); n != 0 {
		t.Fatalf("matches = %d, want 0", n)
	}
	if err := s.SelectNext(); !errors.Is(err, ErrNoValue) {
		t.Errorf("SelectNext with no matches = %v, want ErrNoValue", err)
	}
	if _, selected, err := s.SelectedIndex(); err != nil || selected {
		t.Errorf("SelectedIndex = (_, %v, %v), want not selected and no error", selected, err)
	}
}

// TestSearchSelectWraps walks the match selection to the end and checks that
// the library wraps around, which is what a find bar relies on.
func TestSearchSelectWraps(t *testing.T) {
	term := newTestTerminal(t, 80, 24)
	term.WriteString("error one\r\nerror two\r\nerror three\r\n")

	s, err := NewSearch(term)
	if err != nil {
		t.Fatalf("NewSearch: %v", err)
	}
	defer s.Close()

	if err := s.SetNeedle("error"); err != nil {
		t.Fatalf("SetNeedle: %v", err)
	}
	if err := s.Run(); err != nil {
		t.Fatalf("Run: %v", err)
	}
	total, err := s.TotalMatches()
	if err != nil {
		t.Fatalf("TotalMatches: %v", err)
	}
	if total != 3 {
		t.Fatalf("total matches = %d, want 3", total)
	}

	if err := s.SetScrollPolicy(SearchScrollNone); err != nil {
		t.Fatalf("SetScrollPolicy: %v", err)
	}

	// SelectNext moves newest to oldest, so the indices form 0,1,2 and then
	// wrap back to 0.
	want := []int{0, 1, 2, 0}
	for step, wantIdx := range want {
		if err := s.SelectNext(); err != nil {
			t.Fatalf("SelectNext step %d: %v", step, err)
		}
		idx, selected, err := s.SelectedIndex()
		if err != nil {
			t.Fatalf("SelectedIndex step %d: %v", step, err)
		}
		if !selected {
			t.Fatalf("step %d: nothing selected", step)
		}
		if idx != wantIdx {
			t.Fatalf("step %d: selected index %d, want %d", step, idx, wantIdx)
		}
	}

	// SelectPrev walks back the other way.
	if err := s.SelectPrev(); err != nil {
		t.Fatalf("SelectPrev: %v", err)
	}
	if idx, _, err := s.SelectedIndex(); err != nil || idx != 2 {
		t.Errorf("after SelectPrev index = %d (err %v), want 2", idx, err)
	}
}

// TestSearchEmptyNeedleClears checks the documented clear-then-idle path.
func TestSearchEmptyNeedleClears(t *testing.T) {
	term := newTestTerminal(t, 40, 4)
	term.WriteString("findme\r\n")

	s, err := NewSearch(term)
	if err != nil {
		t.Fatalf("NewSearch: %v", err)
	}
	defer s.Close()

	if err := s.SetNeedle("findme"); err != nil {
		t.Fatalf("SetNeedle: %v", err)
	}
	if err := s.Run(); err != nil {
		t.Fatalf("Run: %v", err)
	}
	if n, _ := s.TotalMatches(); n != 1 {
		t.Fatalf("matches = %d, want 1", n)
	}

	if err := s.SetNeedle(""); err != nil {
		t.Fatalf("SetNeedle(empty): %v", err)
	}
	if got, err := s.Needle(); err != nil || got != "" {
		t.Errorf("Needle after clear = %q (err %v), want empty", got, err)
	}
	if st, err := s.Status(); err != nil || st != SearchComplete {
		t.Errorf("status after clear = %v (err %v), want complete", st, err)
	}
}

// TestSearchFindsMatchesCaseInsensitively covers the primary search path,
// including the case-insensitivity the library documents.
func TestSearchFindsMatchesCaseInsensitively(t *testing.T) {
	term := newTestTerminal(t, 80, 24)
	for _, line := range []string{
		"$ make test\r\n",
		"compiling module A... ok\r\n",
		"compiling module B... error: missing semicolon\r\n",
		"linking... error: undefined symbol\r\n",
		"$ grep -n ERROR build.log\r\n",
	} {
		term.WriteString(line)
	}

	s, err := NewSearch(term)
	if err != nil {
		t.Fatalf("NewSearch: %v", err)
	}
	defer s.Close()

	// A fresh search has no needle and is complete with zero matches.
	if st, err := s.Status(); err != nil || st != SearchComplete {
		t.Errorf("initial status = %v (err %v), want complete", st, err)
	}
	if n, err := s.TotalMatches(); err != nil || n != 0 {
		t.Errorf("initial matches = %d (err %v), want 0", n, err)
	}

	if err := s.SetNeedle("error"); err != nil {
		t.Fatalf("SetNeedle: %v", err)
	}
	if got, err := s.Needle(); err != nil || got != "error" {
		t.Errorf("Needle = %q (err %v), want %q", got, err, "error")
	}
	if err := s.Run(); err != nil {
		t.Fatalf("Run: %v", err)
	}
	if st, err := s.Status(); err != nil || st != SearchComplete {
		t.Errorf("status after Run = %v (err %v), want complete", st, err)
	}

	total, viewport, err := s.MatchCounts()
	if err != nil {
		t.Fatalf("MatchCounts: %v", err)
	}
	if total != 3 {
		t.Errorf("total matches = %d, want 3 (2x error + 1x ERROR)", total)
	}
	if viewport < 1 || viewport > total {
		t.Errorf("viewport matches = %d, want between 1 and %d", viewport, total)
	}

	// Nothing is selected until a select option runs.
	if _, selected, err := s.SelectedIndex(); err != nil || selected {
		t.Errorf("SelectedIndex before select = (_, %v, %v), want not selected", selected, err)
	}
}

// TestSearchDetachedAfterTerminalClose checks the documented freedom to free
// the terminal and the search in either order.
func TestSearchDetachedAfterTerminalClose(t *testing.T) {
	term := newTestTerminal(t, 40, 4)
	term.WriteString("payload\r\n")

	s, err := NewSearch(term)
	if err != nil {
		t.Fatalf("NewSearch: %v", err)
	}
	defer s.Close()

	if err := s.SetNeedle("payload"); err != nil {
		t.Fatalf("SetNeedle: %v", err)
	}
	if err := s.Run(); err != nil {
		t.Fatalf("Run: %v", err)
	}
	n, err := s.TotalMatches()
	if err != nil {
		t.Fatalf("TotalMatches: %v", err)
	}
	if n != 1 {
		t.Fatalf("matches = %d, want 1", n)
	}

	if err := term.Close(); err != nil {
		t.Fatalf("terminal Close: %v", err)
	}

	// Reading search-owned data is still allowed: it never touches the
	// terminal.
	if _, err := s.TotalMatches(); err != nil {
		t.Errorf("TotalMatches after terminal close = %v, want nil", err)
	}
	if err := s.Close(); err != nil {
		t.Errorf("Close after terminal close = %v, want nil", err)
	}
}
