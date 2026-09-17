package khostty

// Tests for the cgo boundary itself: the type manifest, the cgo struct layout
// against the library's own view of it, and the Go error surface.

import (
	"errors"
	"strings"
	"testing"
	"unsafe"
)

// TestTypeManifest checks that the linked library answers the type-manifest
// query. It is the cheapest possible proof that the header search path, the
// library search path, and the runtime rpath all resolve, which is why the
// Makefile's `smoke` target runs it by name.
func TestTypeManifest(t *testing.T) {
	raw := TypeManifest()
	if raw == "" {
		t.Fatal("TypeManifest() returned an empty string")
	}

	m, err := ParseManifest(raw)
	if err != nil {
		t.Fatalf("ParseManifest: %v", err)
	}
	if m.Schema != 1 {
		t.Errorf("manifest schema = %d, want 1", m.Schema)
	}
	if m.LibraryVersion == "" {
		t.Error("manifest has no library_version")
	}
	if m.ABI.PointerSize != int(unsafe.Sizeof(uintptr(0))) {
		t.Errorf("manifest pointer_size = %d, want %d", m.ABI.PointerSize, unsafe.Sizeof(uintptr(0)))
	}
	if len(m.Types) == 0 {
		t.Fatal("manifest declares no types")
	}

	for _, name := range []string{
		"GhosttyString", "GhosttyBuffer", "GhosttyWriter", "GhosttyAllocator",
		"GhosttySelection", "GhosttyFormatterTerminalOptions",
		"GhosttyFormatterTerminalExtra", "GhosttyFormatterScreenExtra",
		"GhosttyColorRgb",
	} {
		if _, ok := m.SizeOf(name); !ok {
			t.Errorf("manifest is missing type %s", name)
		}
	}
}

// TestStructSizesMatchManifest guards the hand-written cgo struct layout
// against the library's own view of it.
//
// The sized-struct options (formatter, selection) are passed by value with a
// `size` field the library validates, so a mismatch between cgo's layout and
// the library's would make formatter options fail outright or, worse, be read
// with the wrong field offsets.
func TestStructSizesMatchManifest(t *testing.T) {
	raw := TypeManifest()
	layout := LayoutInfo()

	mismatches, err := layout.Validate(raw)
	if err != nil {
		t.Fatalf("Layout.Validate: %v", err)
	}
	for _, mm := range mismatches {
		if mm.Library < 0 {
			t.Errorf("%s: absent from the library manifest (compiled size %d)", mm.Type, mm.Compiled)
			continue
		}
		t.Errorf("%s: cgo size %d, library size %d", mm.Type, mm.Compiled, mm.Library)
	}

	m, err := ParseManifest(raw)
	if err != nil {
		t.Fatalf("ParseManifest: %v", err)
	}

	// Spot-check the offsets the formatter wrapper writes when it builds a
	// sized options struct.
	opts, ok := m.Types["GhosttyFormatterTerminalOptions"]
	if !ok {
		t.Fatal("manifest is missing GhosttyFormatterTerminalOptions")
	}
	wantOffsets := map[string]uintptr{
		"size":   layout.FormatterOptionsSizeOffset,
		"emit":   layout.FormatterOptionsEmitOffset,
		"unwrap": layout.FormatterOptionsUnwrapOffset,
		"trim":   layout.FormatterOptionsTrimOffset,
		"extra":  layout.FormatterOptionsExtraOffset,
	}
	for field, compiled := range wantOffsets {
		f, ok := opts.Fields[field]
		if !ok {
			t.Errorf("GhosttyFormatterTerminalOptions is missing field %s", field)
			continue
		}
		if uintptr(f.Offset) != compiled {
			t.Errorf("GhosttyFormatterTerminalOptions.%s offset: cgo %d, library %d",
				field, compiled, f.Offset)
		}
	}
}

// TestLayoutValidateDetectsDrift confirms the ABI check actually fails when
// the numbers disagree, so a green run carries information.
func TestLayoutValidateDetectsDrift(t *testing.T) {
	drifted := `{"schema":1,"types":{"GhosttyString":{"size":99}}}`
	mismatches, err := LayoutInfo().Validate(drifted)
	if err != nil {
		t.Fatalf("Validate: %v", err)
	}
	if len(mismatches) == 0 {
		t.Fatal("Validate accepted a manifest with a wrong GhosttyString size")
	}

	var sawWrongSize, sawMissing bool
	for _, mm := range mismatches {
		if mm.Type == "GhosttyString" && mm.Library == 99 {
			sawWrongSize = true
		}
		if mm.Library < 0 {
			sawMissing = true
		}
	}
	if !sawWrongSize {
		t.Error("Validate did not report the fabricated GhosttyString size")
	}
	if !sawMissing {
		t.Error("Validate did not report the types absent from the drifted manifest")
	}

	if _, err := LayoutInfo().Validate("not json"); err == nil {
		t.Error("Validate accepted malformed JSON")
	}
}

// TestErrorStringsAndIsChecks the Go error surface.
func TestErrorStringsAndIs(t *testing.T) {
	cases := []struct {
		err  Error
		want string
	}{
		{ErrOutOfMemory, "khostty: out of memory"},
		{ErrInvalidValue, "khostty: invalid value"},
		{ErrOutOfSpace, "khostty: buffer too small"},
		{ErrNoValue, "khostty: no value"},
		{ErrIO, "khostty: io error"},
		{ErrLimitExceeded, "khostty: limit exceeded"},
		{ErrRejected, "khostty: rejected by safety check"},
	}
	for _, tc := range cases {
		if got := tc.err.Error(); got != tc.want {
			t.Errorf("Error() = %q, want %q", got, tc.want)
		}
		if !errors.Is(tc.err, tc.err) {
			t.Errorf("errors.Is(%v, %v) = false", tc.err, tc.err)
		}
	}

	if got := Error(0).Error(); got != "khostty: success" {
		t.Errorf("Error(0) = %q, want the success string", got)
	}
	if got := Error(-99).Error(); !strings.Contains(got, "-99") {
		t.Errorf("unknown code string = %q, want it to include the raw code", got)
	}
	if errors.Is(ErrNoValue, ErrInvalidValue) {
		t.Error("errors.Is conflated two distinct result codes")
	}
}
