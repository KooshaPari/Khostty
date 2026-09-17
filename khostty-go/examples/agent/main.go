// Command agent demonstrates the workflow libghostty-vt is most useful for in
// agent tooling: drive a terminal programmatically, then read its state back
// as data instead of scraping a screen.
//
// It covers the three operations an agent-oriented wrapper needs:
//
//   - read the visible screen and the cursor position to know where a prompt is
//   - search the screen and scrollback for a pattern and walk the matches
//   - snapshot the session so it can be resumed, and resize the pane
//
// Run it from khostty-go after building the library:
//
//	zig build install -Doptimize=ReleaseFast   # from the repo root
//	go run ./examples/agent
package main

import (
	"fmt"
	"log"
	"strings"

	khostty "github.com/KooshaPari/Khostty/khostty-go"
)

func main() {
	if err := run(); err != nil {
		log.Fatal(err)
	}
}

func run() error {
	// A pane is a terminal. 80x24 is the conservative default an agent
	// should assume before it knows the real viewport.
	pane, err := khostty.NewTerminal(80, 24)
	if err != nil {
		return fmt.Errorf("create pane: %w", err)
	}
	defer pane.Close()

	// Keep a scrollback budget the agent can reason about, rather than
	// inheriting the library default.
	if err := pane.SetSize(khostty.OptScrollbackMaxLines, 5_000); err != nil {
		return fmt.Errorf("set scrollback budget: %w", err)
	}

	if err := typeOutput(pane, testOutput); err != nil {
		return err
	}
	if err := reportPrompt(pane); err != nil {
		return err
	}
	if err := reportMatches(pane, "FAIL"); err != nil {
		return err
	}
	if err := reportSnapshot(pane); err != nil {
		return err
	}
	if err := resizePane(pane, 120, 40); err != nil {
		return err
	}

	return nil
}

// reportPrompt prints what the agent knows about the prompt location, which is
// the anchor for "is the program waiting for input".
func reportPrompt(pane *khostty.Terminal) error {
	// Finish the transcript with a fresh prompt.
	pane.WriteString("$ ")

	atPrompt, err := pane.CursorAtPrompt()
	if err != nil {
		return fmt.Errorf("read prompt state: %w", err)
	}

	// OSC 133 marks are what make CursorAtPrompt meaningful; without them the
	// library reports false, so the cursor position is the fallback signal.
	pane.WriteString("\x1b]133;A\x07")
	atPromptAfterMark, err := pane.CursorAtPrompt()
	if err != nil {
		return fmt.Errorf("read prompt state: %w", err)
	}

	cx, _ := pane.CursorX()
	cy, _ := pane.CursorY()
	ground, _ := pane.VTGround()

	fmt.Printf("cursor at (%d,%d), at-prompt=%v (after OSC 133 mark: %v), stream at ground: %v\n",
		cx, cy, atPrompt, atPromptAfterMark, ground)
	return nil
}

// reportMatches searches the transcript and walks the match list, the way a
// find bar or a "show me the failures" tool would.
func reportMatches(pane *khostty.Terminal, needle string) error {
	search, err := khostty.NewSearch(pane)
	if err != nil {
		return fmt.Errorf("create search: %w", err)
	}
	defer search.Close()

	// Do not move the viewport while walking matches: an agent wants the
	// transcript where it is.
	if err := search.SetScrollPolicy(khostty.SearchScrollNone); err != nil {
		return fmt.Errorf("set scroll policy: %w", err)
	}
	if err := search.SetNeedle(needle); err != nil {
		return fmt.Errorf("set needle: %w", err)
	}
	if err := search.Run(); err != nil {
		return fmt.Errorf("run search: %w", err)
	}

	total, viewport, err := search.MatchCounts()
	if err != nil {
		return fmt.Errorf("count matches: %w", err)
	}
	fmt.Printf("%d matches for %q (%d on the viewport)\n", total, needle, viewport)
	if total == 0 {
		return nil
	}

	// Walk oldest-to-newest and back to prove the selection cursor moves.
	for step := 0; step < total; step++ {
		if err := search.SelectNext(); err != nil {
			return fmt.Errorf("select next: %w", err)
		}
		idx, selected, err := search.SelectedIndex()
		if err != nil {
			return fmt.Errorf("read selection: %w", err)
		}
		if !selected {
			return fmt.Errorf("step %d: search reported no selection after SelectNext", step)
		}
		fmt.Printf("  match %d of %d selected (index %d, 0 is newest)\n", step+1, total, idx)
	}

	if err := search.SelectPrev(); err != nil {
		return fmt.Errorf("select prev: %w", err)
	}
	if idx, _, err := search.SelectedIndex(); err == nil {
		fmt.Printf("  after SelectPrev: index %d\n", idx)
	}
	return nil
}

// reportSnapshot captures the pane so a later process can resume it.
func reportSnapshot(pane *khostty.Terminal) error {
	snap, err := pane.Snapshot()
	if err != nil {
		return fmt.Errorf("snapshot: %w", err)
	}

	resumed, err := khostty.RestoreSnapshot(snap)
	if err != nil {
		return fmt.Errorf("restore snapshot: %w", err)
	}
	defer resumed.Close()

	before, err := pane.Text()
	if err != nil {
		return fmt.Errorf("read screen: %w", err)
	}
	after, err := resumed.Text()
	if err != nil {
		return fmt.Errorf("read resumed screen: %w", err)
	}

	cx, cy := cursorOf(resumed)
	fmt.Printf("snapshot %d bytes; resumed screen identical: %v; resumed cursor (%d,%d)\n",
		len(snap), before == after, cx, cy)
	return nil
}

// resizePane exercises reflow, which is what makes a pane usable after the
// surrounding layout changes.
func resizePane(pane *khostty.Terminal, cols, rows int) error {
	// 8x16 is a placeholder cell metric; real callers measure the font.
	if err := pane.Resize(cols, rows, 8, 16); err != nil {
		return fmt.Errorf("resize: %w", err)
	}
	w, _ := pane.WidthPx()
	h, _ := pane.HeightPx()
	total, _ := pane.TotalRows()
	scrollback, _ := pane.ScrollbackRows()

	screen, err := pane.Text()
	if err != nil {
		return fmt.Errorf("read screen after resize: %w", err)
	}
	fmt.Printf("resized to %dx%d cells (%dx%d px); %d rows total, %d of scrollback\n",
		cols, rows, w, h, total, scrollback)
	fmt.Printf("transcript still readable after reflow: %v\n",
		strings.Contains(screen, "TestWidgetRender"))
	return nil
}

// typeOutput feeds a transcript to the pane a chunk at a time, mirroring how
// bytes arrive from a pty in small, arbitrarily split writes.
func typeOutput(pane *khostty.Terminal, transcript string) error {
	chunks := strings.SplitAfter(transcript, "\r\n")
	for _, chunk := range chunks {
		if chunk == "" {
			continue
		}
		pane.WriteString(chunk)
	}
	return nil
}

// cursorOf is a small helper so call sites read cleanly.
func cursorOf(t *khostty.Terminal) (uint16, uint16) {
	x, _ := t.CursorX()
	y, _ := t.CursorY()
	return x, y
}

// testOutput stands in for a test run the agent is watching.
const testOutput = "$ make test\r\n" +
	"ok   github.com/example/a\t0.021s\r\n" +
	"ok   github.com/example/b\t0.114s\r\n" +
	"--- FAIL: TestWidgetRender (0.03s)\r\n" +
	"    widget_test.go:41: got 3 widgets, want 4\r\n" +
	"FAIL\tgithub.com/example/c\t0.412s\r\n"
