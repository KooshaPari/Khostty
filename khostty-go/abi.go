package khostty

/*
#include <ghostty/vt.h>
*/
import "C"

import "unsafe"

// Layout reports the C struct sizes and offsets these bindings were compiled
// against.
//
// It exists so callers can check the bindings against the linked library
// rather than trusting the compiled-in numbers: pass TypeManifest() through
// Layout.Validate to compare the library's own view of each struct with the
// one cgo produced. That catches the failure mode where a header is swapped
// for a newer or older revision than the shared object, which would otherwise
// show up only as silently misfielded formatter options.
type Layout struct {
	PointerSize uintptr

	StringSize    uintptr
	BufferSize    uintptr
	WriterSize    uintptr
	AllocatorSize uintptr

	SelectionSize uintptr

	FormatterTerminalOptionsSize uintptr
	FormatterTerminalExtraSize   uintptr
	FormatterScreenExtraSize     uintptr

	// FormatterOptionsEmitOffset and friends are the offsets the formatter
	// wrapper relies on when it builds a sized options struct.
	FormatterOptionsSizeOffset   uintptr
	FormatterOptionsEmitOffset   uintptr
	FormatterOptionsUnwrapOffset uintptr
	FormatterOptionsTrimOffset   uintptr
	FormatterOptionsExtraOffset  uintptr
}

// LayoutInfo returns the compiled-in C struct layout.
func LayoutInfo() Layout {
	return Layout{
		PointerSize: unsafe.Sizeof(uintptr(0)),

		StringSize:    unsafe.Sizeof(C.GhosttyString{}),
		BufferSize:    unsafe.Sizeof(C.GhosttyBuffer{}),
		WriterSize:    unsafe.Sizeof(C.GhosttyWriter{}),
		AllocatorSize: unsafe.Sizeof(C.GhosttyAllocator{}),

		SelectionSize: unsafe.Sizeof(C.GhosttySelection{}),

		FormatterTerminalOptionsSize: unsafe.Sizeof(C.GhosttyFormatterTerminalOptions{}),
		FormatterTerminalExtraSize:   unsafe.Sizeof(C.GhosttyFormatterTerminalExtra{}),
		FormatterScreenExtraSize:     unsafe.Sizeof(C.GhosttyFormatterScreenExtra{}),

		FormatterOptionsSizeOffset:   unsafe.Offsetof(C.GhosttyFormatterTerminalOptions{}.size),
		FormatterOptionsEmitOffset:   unsafe.Offsetof(C.GhosttyFormatterTerminalOptions{}.emit),
		FormatterOptionsUnwrapOffset: unsafe.Offsetof(C.GhosttyFormatterTerminalOptions{}.unwrap),
		FormatterOptionsTrimOffset:   unsafe.Offsetof(C.GhosttyFormatterTerminalOptions{}.trim),
		FormatterOptionsExtraOffset:  unsafe.Offsetof(C.GhosttyFormatterTerminalOptions{}.extra),
	}
}

// abiFields maps manifest type names onto the corresponding Layout field, for
// the size comparison performed by the tests and by ABI consumers.
var abiFields = []struct {
	name string
	get  func(Layout) uintptr
}{
	{"GhosttyString", func(l Layout) uintptr { return l.StringSize }},
	{"GhosttyBuffer", func(l Layout) uintptr { return l.BufferSize }},
	{"GhosttyWriter", func(l Layout) uintptr { return l.WriterSize }},
	{"GhosttyAllocator", func(l Layout) uintptr { return l.AllocatorSize }},
	{"GhosttySelection", func(l Layout) uintptr { return l.SelectionSize }},
	{"GhosttyFormatterTerminalOptions", func(l Layout) uintptr { return l.FormatterTerminalOptionsSize }},
	{"GhosttyFormatterTerminalExtra", func(l Layout) uintptr { return l.FormatterTerminalExtraSize }},
	{"GhosttyFormatterScreenExtra", func(l Layout) uintptr { return l.FormatterScreenExtraSize }},
}

// ABIMismatch reports one struct whose compiled-in size disagrees with the
// library's manifest.
type ABIMismatch struct {
	Type     string
	Compiled int
	Library  int
}

// Validate compares the compiled-in layout against a type manifest produced by
// TypeManifest, returning one entry per disagreeing struct.
//
// An empty result means the bindings and the linked library agree on every
// struct this package depends on. It is worth calling after deploying with a
// library that may differ from the headers the package was built against.
func (l Layout) Validate(manifest string) ([]ABIMismatch, error) {
	sizes, err := manifestSizes(manifest)
	if err != nil {
		return nil, err
	}

	var out []ABIMismatch
	for _, f := range abiFields {
		lib, ok := sizes[f.name]
		if !ok {
			out = append(out, ABIMismatch{Type: f.name, Compiled: int(f.get(l)), Library: -1})
			continue
		}
		if compiled := int(f.get(l)); compiled != lib {
			out = append(out, ABIMismatch{Type: f.name, Compiled: compiled, Library: lib})
		}
	}
	return out, nil
}
