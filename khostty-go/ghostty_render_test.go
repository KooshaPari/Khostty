package khostty

import (
	"errors"
	"strings"
	"testing"
)

// Tests for formatter output.
// TestFormatterOutputFormats pins the three output encodings against real
// terminal content.
func TestFormatterOutputFormats(t *testing.T) {
	term := newTestTerminal(t, 20, 3)
	term.WriteString("\x1b[1mBold\x1b[0m\r\n")

	cases := []struct {
		format Format
		want   string
	}{
		{FormatPlain, "Bold"},
		{FormatVT, "\x1b[0m\x1b[1mBold\x1b[0m"},
		{FormatHTML, `<div style="font-family: monospace; white-space: pre;">`},
	}
	for _, tc := range cases {
		f, err := NewFormatter(term, FormatterOptions{Format: tc.format, Trim: true})
		if err != nil {
			t.Fatalf("NewFormatter(%d): %v", int(tc.format), err)
		}
		out, err := f.Format()
		if err != nil {
			f.Close()
			t.Fatalf("Format(%d): %v", int(tc.format), err)
		}
		got := string(out)
		f.Close()

		if tc.format == FormatVT || tc.format == FormatHTML {
			if !strings.Contains(got, tc.want) {
				t.Errorf("format %d output %q does not contain %q", int(tc.format), got, tc.want)
			}
		} else if got != tc.want {
			t.Errorf("format %d output = %q, want %q", int(tc.format), got, tc.want)
		}
	}
}

// TestFormatterTrimAndUnwrap checks the two content-shaping flags.
func TestFormatterTrimAndUnwrap(t *testing.T) {
	term := newTestTerminal(t, 10, 6)

	term.WriteString("pad       \r\n")
	plain, err := term.Text()
	if err != nil {
		t.Fatalf("Text: %v", err)
	}
	if strings.HasSuffix(plain, " ") {
		t.Errorf("default Text() left trailing spaces: %q", plain)
	}

	f, err := NewFormatter(term, FormatterOptions{Format: FormatPlain, Trim: false})
	if err != nil {
		t.Fatalf("NewFormatter: %v", err)
	}
	defer f.Close()
	untrimmed, err := f.Text()
	if err != nil {
		t.Fatalf("Format: %v", err)
	}
	if !strings.Contains(untrimmed, "pad ") {
		t.Errorf("untrimmed output = %q, want the padding preserved", untrimmed)
	}

	term.Reset()
	term.WriteString("0123456789ABCDEFGHIJ\r\n")
	unwrapped, err := NewFormatter(term, FormatterOptions{
		Format: FormatPlain, Trim: true, Unwrap: true,
	})
	if err != nil {
		t.Fatalf("NewFormatter(unwrap): %v", err)
	}
	defer unwrapped.Close()
	got, err := unwrapped.Text()
	if err != nil {
		t.Fatalf("Format(unwrap): %v", err)
	}
	if !strings.Contains(got, "0123456789ABCDEFGHIJ") {
		t.Errorf("unwrapped output = %q, want the soft-wrapped line joined", got)
	}
}

// TestFormatterReuse checks that one formatter reflects terminal changes on
// each call rather than caching the first result.
func TestFormatterReuse(t *testing.T) {
	term := newTestTerminal(t, 40, 4)
	f, err := NewFormatter(term, FormatterOptions{Format: FormatPlain, Trim: true})
	if err != nil {
		t.Fatalf("NewFormatter: %v", err)
	}
	defer f.Close()

	term.WriteString("first\r\n")
	first, err := f.Text()
	if err != nil {
		t.Fatalf("Format: %v", err)
	}
	term.WriteString("second\r\n")
	second, err := f.Text()
	if err != nil {
		t.Fatalf("Format: %v", err)
	}
	if first == second {
		t.Errorf("formatter did not observe the new write: %q == %q", first, second)
	}
	if !strings.Contains(second, "second") {
		t.Errorf("second format = %q, want it to contain the new line", second)
	}
}

// TestFormatterUseAfterClose checks the guard on a released formatter.
func TestFormatterUseAfterClose(t *testing.T) {
	term := newTestTerminal(t, 40, 4)
	f, err := NewFormatter(term, FormatterOptions{Format: FormatPlain})
	if err != nil {
		t.Fatalf("NewFormatter: %v", err)
	}
	if err := f.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if err := f.Close(); err != nil {
		t.Fatalf("second Close: %v", err)
	}
	if _, err := f.Format(); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("Format after Close = %v, want ErrInvalidValue", err)
	}
	var nilFormatter *Formatter
	if err := nilFormatter.Close(); err != nil {
		t.Errorf("Close on nil = %v, want nil", err)
	}
}
