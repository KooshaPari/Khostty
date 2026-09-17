// Command basic is the smallest useful libghostty-vt example through the Go
// bindings: create a terminal, feed it VT-encoded output, then read the screen
// back.
//
// Run it from khostty-go after building the library:
//
//	zig build install -Doptimize=ReleaseFast   # from the repo root
//	go run ./examples/basic
//
// If linking fails on macOS with `tapi error: malformed file`, see doc.go:
// the installed CommandLineTools linker may predate the active SDK.
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
	term, err := khostty.NewTerminal(80, 24)
	if err != nil {
		return fmt.Errorf("create terminal: %w", err)
	}
	defer term.Close()

	// This is what a program would write to its pty.
	for _, chunk := range []string{
		"\x1b[1m$ build\x1b[0m\r\n",
		"compiling package a... ok\r\n",
		"compiling package b... ok\r\n",
		"\x1b[31merror\x1b[0m: cannot find symbol 'Widget'\r\n",
		"  --> src/app.rs:41:12\r\n",
		"build failed with 1 error\r\n",
	} {
		term.WriteString(chunk)
	}

	// The script is fixed, but finishing with a prompt is what makes the
	// screen read like a real session.
	term.WriteString("$ \r\n")

	cols, err := term.Cols()
	if err != nil {
		return fmt.Errorf("read cols: %w", err)
	}
	rows, err := term.Rows()
	if err != nil {
		return fmt.Errorf("read rows: %w", err)
	}
	cx, _ := term.CursorX()
	cy, _ := term.CursorY()

	screen, err := term.Text()
	if err != nil {
		return fmt.Errorf("read screen: %w", err)
	}

	fmt.Printf("=== %dx%d screen, cursor at (%d,%d) ===\n", cols, rows, cx, cy)
	fmt.Println(screen)
	fmt.Println("=== end screen ===")

	// The same content is available with styles preserved, as VT, or as HTML.
	vt, err := khostty.NewFormatter(term, khostty.FormatterOptions{
		Format: khostty.FormatVT,
		Trim:   true,
	})
	if err != nil {
		return fmt.Errorf("create VT formatter: %w", err)
	}
	defer vt.Close()
	vtOut, err := vt.Format()
	if err != nil {
		return fmt.Errorf("format VT: %w", err)
	}
	fmt.Printf("VT rendering: %d bytes, %d escape sequences\n",
		len(vtOut), strings.Count(string(vtOut), "\x1b"))

	// Search the screen and scrollback for failures, the way a find bar or a
	// status badge would.
	search, err := khostty.NewSearch(term)
	if err != nil {
		return fmt.Errorf("create search: %w", err)
	}
	defer search.Close()

	if err := search.SetNeedle("error"); err != nil {
		return fmt.Errorf("set needle: %w", err)
	}
	if err := search.Run(); err != nil {
		return fmt.Errorf("run search: %w", err)
	}
	total, viewport, err := search.MatchCounts()
	if err != nil {
		return fmt.Errorf("count matches: %w", err)
	}
	fmt.Printf("matches for %q: %d total, %d covering the viewport\n",
		"error", total, viewport)

	// Encoded snapshots are self-contained: they can be stored and decoded
	// into a fresh terminal later, which is how a session can be resumed.
	snap, err := term.Snapshot()
	if err != nil {
		return fmt.Errorf("snapshot: %w", err)
	}
	restored, err := khostty.RestoreSnapshot(snap)
	if err != nil {
		return fmt.Errorf("restore snapshot: %w", err)
	}
	defer restored.Close()

	restoredScreen, err := restored.Text()
	if err != nil {
		return fmt.Errorf("read restored screen: %w", err)
	}
	fmt.Printf("snapshot: %d bytes, round-trip identical: %v\n",
		len(snap), restoredScreen == screen)

	return nil
}
