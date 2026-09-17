package khostty

import (
	"errors"
	"testing"
)

// Tests for snapshot encode and restore.
// TestSnapshotRoundTrip encodes terminals of several shapes and restores them,
// requiring the restored screen to render identically.
func TestSnapshotRoundTrip(t *testing.T) {
	cases := []struct {
		name            string
		cols, rows      int
		writes          []string
		expectUntracked bool
	}{
		{
			name: "simple text",
			cols: 40, rows: 6,
			writes: []string{"alpha\r\n", "beta\r\n", "gamma"},
		},
		{
			name: "styled text",
			cols: 60, rows: 8,
			writes: []string{
				"\x1b[1;31mred bold\x1b[0m\r\n",
				"\x1b[4munder\x1b[0m\r\n",
				"\x1b]0;title\x07rest",
			},
		},
		{
			name: "cursor repositioned",
			cols: 80, rows: 12,
			writes: []string{"one\r\n", "two\r\n", "\x1b[5;10Hplaced"},
		},
		{
			name: "wrapped line",
			cols: 10, rows: 6,
			writes: []string{"0123456789ABCDEFGHIJ\r\n"},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			term := newTestTerminal(t, tc.cols, tc.rows)
			for _, w := range tc.writes {
				term.WriteString(w)
			}
			want := screenText(t, term)

			snap, err := term.Snapshot()
			if err != nil {
				t.Fatalf("Snapshot: %v", err)
			}
			if len(snap) == 0 {
				t.Fatal("Snapshot returned no bytes")
			}

			size, err := term.SnapshotSize()
			if err != nil {
				t.Fatalf("SnapshotSize: %v", err)
			}
			if size != len(snap) {
				t.Errorf("SnapshotSize = %d, Snapshot produced %d bytes", size, len(snap))
			}

			restored, err := RestoreSnapshot(snap)
			if err != nil {
				t.Fatalf("RestoreSnapshot: %v", err)
			}
			defer restored.Close()

			if got := screenText(t, restored); got != want {
				t.Errorf("restored screen mismatch:\n got %q\nwant %q", got, want)
			}
			if c, _ := restored.Cols(); int(c) != tc.cols {
				t.Errorf("restored Cols = %d, want %d", c, tc.cols)
			}
			if r, _ := restored.Rows(); int(r) != tc.rows {
				t.Errorf("restored Rows = %d, want %d", r, tc.rows)
			}
		})
	}
}

// TestSnapshotInto exercises the two-call buffer pattern and the too-small
// buffer error.
func TestSnapshotInto(t *testing.T) {
	term := newTestTerminal(t, 40, 6)
	term.WriteString("some content here\r\nand more")

	want, err := term.Snapshot()
	if err != nil {
		t.Fatalf("Snapshot: %v", err)
	}

	if _, err := term.SnapshotInto(make([]byte, 8)); !errors.Is(err, ErrOutOfSpace) {
		t.Errorf("SnapshotInto(8 bytes) = %v, want ErrOutOfSpace", err)
	}

	buf := make([]byte, len(want)+64)
	n, err := term.SnapshotInto(buf)
	if err != nil {
		t.Fatalf("SnapshotInto: %v", err)
	}
	if n != len(want) {
		t.Fatalf("SnapshotInto wrote %d bytes, want %d", n, len(want))
	}
	if string(buf[:n]) != string(want) {
		t.Error("buffer-encoded snapshot differs from allocated snapshot")
	}

	restored, err := RestoreSnapshot(buf[:n])
	if err != nil {
		t.Fatalf("RestoreSnapshot: %v", err)
	}
	defer restored.Close()
	if got, want := screenText(t, restored), screenText(t, term); got != want {
		t.Errorf("restored screen = %q, want %q", got, want)
	}
}

// TestRestoreSnapshotRejectsEmpty checks the argument guard.
func TestRestoreSnapshotRejectsEmpty(t *testing.T) {
	if _, err := RestoreSnapshot(nil); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("RestoreSnapshot(nil) = %v, want ErrInvalidValue", err)
	}
	if _, err := RestoreSnapshot([]byte{}); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("RestoreSnapshot(empty) = %v, want ErrInvalidValue", err)
	}
}
