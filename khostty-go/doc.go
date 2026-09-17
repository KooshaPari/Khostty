// Package khostty provides Go (cgo) bindings for libghostty-vt, the
// virtual-terminal emulation library extracted from Ghostty.
//
// It is a thin, RAII-style wrapper: it owns opaque handles, maps
// GhosttyResult codes onto Go errors, and converts Go byte slices and
// strings to the borrowed `GhosttyString` / `GhosttyBuffer` views the C
// API expects. No terminal state is duplicated on the Go side.
//
// # Linking
//
// The cgo link flags live in link_default.go and point at the Khostty
// checkout that contains this directory:
//
//	-I${SRCDIR}/../include                      (headers)
//	-L${SRCDIR}/../zig-out/lib -lghostty-vt     (library)
//	-Wl,-rpath,${SRCDIR}/../zig-out/lib         (runtime lookup)
//
// Build the library first:
//
//	zig build install -Doptimize=ReleaseFast
//
// # Overriding the library location
//
// Four escape hatches exist, in increasing order of bluntness:
//
//  1. Copy (or symlink) the built library into `../zig-out/lib`, which is
//     what the default directives expect.
//
//  2. Set `CGO_LDFLAGS` to add extra search paths. These are appended
//     after the directives in link_default.go, so they act as a fallback
//     rather than an override:
//
//	CGO_LDFLAGS="-L/opt/ghostty/lib" go test ./...
//
//  3. Build with the `khostty_custom_lib` tag. This disables the default
//     `-L`/`-l`/`-rpath` flags entirely (see link_custom.go) and makes
//     the build depend purely on `CGO_LDFLAGS`, so an out-of-tree library
//     can be the only one on the search path:
//
//	CGO_LDFLAGS="-L/opt/ghostty/lib -lghostty-vt -Wl,-rpath,/opt/ghostty/lib" \
//	    go test -tags khostty_custom_lib ./...
//
//  4. `GHOSTTY_VT_LIB_DIR` is also honoured, but only at *test* time:
//     the same content as `CGO_LDFLAGS` can be exported once and inherited
//     by `go build`/`go test`. It is not read by the linker directives
//     themselves, because cgo cannot expand environment variables inside
//     `#cgo` lines.
//
// On macOS the shared object records `@rpath/libghostty-vt.dylib` as its
// install name, so the rpath flag above (or an equivalent
// `DYLD_LIBRARY_PATH`) is required for tests and binaries to start.
// On Linux the equivalent is `LD_LIBRARY_PATH`.
//
// # macOS toolchain caveat (darwin only)
//
// If `go test` fails at link time with `tapi error: malformed file` and
// `error: unknown architecture ... arm64e.x1-macos`, the installed
// CommandLineTools `ld` is older than the active SDK's `.tbd` text stubs.
// It is an environment problem, not a problem with these bindings. Two
// workarounds, either of which is sufficient:
//
//	# Use the Xcode toolchain and its matching SDK.
//	export CC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang
//	export SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
//
//	# Or pin an older SDK that the installed ld still understands.
//	export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
//
// `make test` applies the second automatically when it detects the
// failure. Compiling (`go build`) and `go vet` are unaffected because they
// do not invoke the system linker.
//
// # Concurrency
//
// A Terminal is not safe for concurrent use. The C library requires
// callers to serialize all access to one terminal handle; searching runs
// off search-owned memory, but `Search.Feed` itself reads the terminal.
package khostty
