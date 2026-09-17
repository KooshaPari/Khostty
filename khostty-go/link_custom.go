//go:build khostty_custom_lib

package khostty

// Opt-out link configuration, selected with `go build -tags khostty_custom_lib`.
//
// It keeps only the header search path and deliberately omits every
// library flag, so the library location is entirely whatever the caller
// puts in CGO_LDFLAGS. This is the supported way to link a libghostty-vt
// that is not in `<checkout>/zig-out/lib`, and the only way to guarantee the
// in-tree copy is not also on the search path.
//
// Example:
//
//	export CGO_LDFLAGS="-L/opt/ghostty/lib -lghostty-vt -Wl,-rpath,/opt/ghostty/lib"
//	go test -tags khostty_custom_lib ./...
//
// On Linux, use `-Wl,-rpath,/opt/ghostty/lib`; on macOS the equivalent
// rpath flag is required because the shared object's install name is
// `@rpath/libghostty-vt.dylib`.

/*
#cgo CFLAGS: -I${SRCDIR}/../include
*/
import "C"
