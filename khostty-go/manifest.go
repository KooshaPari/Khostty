package khostty

import "encoding/json"

// Manifest is the decoded form of the library's versioned C type manifest.
//
// The manifest is the library's own description of every public struct, enum,
// and union in the linked build, including sizes, alignments, field offsets,
// and enum values. It is the authoritative source for ABI checks, both here
// and in the sibling Python bindings.
type Manifest struct {
	// Schema is the manifest format version. This package understands 1.
	Schema int `json:"schema"`

	// ABI describes the compiled target: pointer size, alignment, endianness.
	ABI ABIInfo `json:"abi"`

	// LibraryVersion is the library's own version string.
	LibraryVersion string `json:"library_version"`

	// Commit is the source revision the library was built from, if recorded.
	Commit string `json:"commit"`

	// Dirty reports whether the library was built from a modified tree.
	Dirty bool `json:"dirty"`

	// Types maps C type names onto their layouts.
	Types map[string]TypeLayout `json:"types"`
}

// ABIInfo describes the target the library was compiled for.
type ABIInfo struct {
	Target      string `json:"target"`
	OS          string `json:"os"`
	Environment string `json:"environment"`
	PointerSize int    `json:"pointer_size"`
	USizeSize   int    `json:"usize_size"`
	MaxAlign    int    `json:"max_alignment"`
	Endian      string `json:"endian"`
}

// TypeLayout is the layout of one C type.
type TypeLayout struct {
	Kind  string `json:"kind"`
	Size  int    `json:"size"`
	Align int    `json:"align"`

	// Fields is populated for structs and unions; keyed by C field name.
	Fields map[string]FieldLayout `json:"fields"`

	// Values is populated for enums; keyed by member name with the C prefix
	// already stripped.
	Values map[string]int `json:"values"`

	// Prefix is the enum's C member prefix, e.g. "GHOSTTY_KEY_".
	Prefix string `json:"prefix"`

	// Underlying is the enum's C integer type, e.g. "i32".
	Underlying string `json:"underlying"`
}

// FieldLayout is the position and type of one struct field.
type FieldLayout struct {
	Offset int    `json:"offset"`
	Size   int    `json:"size"`
	Type   string `json:"type"`
}

// ParseManifest decodes a manifest string produced by TypeManifest.
func ParseManifest(raw string) (*Manifest, error) {
	var m Manifest
	if err := json.Unmarshal([]byte(raw), &m); err != nil {
		return nil, err
	}
	return &m, nil
}

// SizeOf returns the manifest's size for a type, and whether it was present.
func (m *Manifest) SizeOf(name string) (int, bool) {
	t, ok := m.Types[name]
	if !ok {
		return 0, false
	}
	return t.Size, true
}

// EnumValues returns the members of a C enum, or false when the manifest has
// no such enum.
//
// Member names have the C prefix stripped, so GhosttyKey arrives as "ESCAPE",
// "ARROW_UP", and so on. The MAX_VALUE sentinel is included; callers that want
// only real members should skip it.
func (m *Manifest) EnumValues(name string) (map[string]int, bool) {
	t, ok := m.Types[name]
	if !ok || t.Kind != "enum" {
		return nil, false
	}
	return t.Values, true
}

// manifestSizes extracts just the type sizes from a raw manifest.
func manifestSizes(raw string) (map[string]int, error) {
	m, err := ParseManifest(raw)
	if err != nil {
		return nil, err
	}
	sizes := make(map[string]int, len(m.Types))
	for name, t := range m.Types {
		sizes[name] = t.Size
	}
	return sizes, nil
}
