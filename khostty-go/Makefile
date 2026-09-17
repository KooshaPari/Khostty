# Convenience targets for the Go bindings.
#
# `go build` and `go vet` need nothing beyond a built libghostty-vt. On
# macOS, linking a *test binary* pulls in the system linker, which on some
# CommandLineTools installations is older than the active SDK and fails
# with `tapi error: malformed file`. `SDK_FALLBACK` below pins an older SDK
# when that happens; see doc.go for details and the Xcode-toolchain
# alternative.

GO ?= go
LIB_DIR := $(CURDIR)/../zig-out/lib
SDK_FALLBACK ?= /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk

UNAME_S := $(shell uname -s)

.PHONY: all build vet test clean lib smoke

all: vet test

lib:
	cd .. && zig build install -Doptimize=ReleaseFast

build:
	$(GO) build ./...

vet:
	$(GO) vet ./...

# Link a test binary, applying the macOS SDK workaround only if the plain
# attempt fails. On Linux and on healthy darwin toolchains the first
# attempt succeeds and the fallback is never used.
test:
	@if $(GO) test ./... ; then \
		exit 0; \
	fi; \
	if [ "$(UNAME_S)" = "Darwin" ] && [ -d "$(SDK_FALLBACK)" ]; then \
		echo "retrying with SDKROOT=$(SDK_FALLBACK)"; \
		SDKROOT="$(SDK_FALLBACK)" $(GO) test ./... ; \
	else \
		exit 1; \
	fi

# Prove the shared library resolves and the headers agree with the binary.
smoke:
	@test -f "$(LIB_DIR)/libghostty-vt.dylib" -o -f "$(LIB_DIR)/libghostty-vt.so" \
		|| { echo "missing libghostty-vt in $(LIB_DIR); run 'make lib'"; exit 1; }
	$(GO) test -run TestTypeManifest -v .

clean:
	$(GO) clean ./...
