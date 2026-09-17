module github.com/KooshaPari/Khostty/khostty-go

go 1.23

// This module uses cgo exclusively; there are no third-party Go
// dependencies. The only external requirement is the prebuilt
// libghostty-vt shared library, located by the linker directives in
// link_default.go (or overridden per the build tag documented in
// doc.go).
