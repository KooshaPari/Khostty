# Convenience targets for the Go bindings.
#
# `go build` and `go vet` need nothing beyond a built libghostty-vt. On
# macOS, linking a *test binary* pulls in the system linker, which on some
# CommandLineTools installations is older than the active SDK and fails with
# `tapi error: malformed file`. The `go_test` recipe below retries with an
# older SDK pinned via SDKROOT when that happens; see doc.go for details and
# the Xcode-toolchain alternative.

GO ?= go
LIB_DIR := $(CURDIR)/../zig-out/lib
SDK_FALLBACK ?= /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk

UNAME_S := $(shell uname -s)

# Run a go test command, falling back to a pinned macOS SDK if the first
# attempt fails to link. On Linux and on healthy darwin toolchains the first
# attempt succeeds and the fallback is never used.
define go_test
if $(GO) test $(1) ; then \
	exit 0; \
fi; \
if [ "$(UNAME_S)" = "Darwin" ] && [ -d "$(SDK_FALLBACK)" ]; then \
	echo "retrying with SDKROOT=$(SDK_FALLBACK)"; \
	SDKROOT="$(SDK_FALLBACK)" $(GO) test $(1); \
else \
	exit 1; \
fi
endef

.PHONY: all fmt build vet test smoke lib clean

all: fmt vet test

# Build the shared library this module links against.
lib:
	cd .. && zig build install -Doptimize=ReleaseFast

fmt:
	@out=$$(gofmt -l .); \
	if [ -n "$$out" ]; then echo "gofmt needed:"; echo "$$out"; exit 1; fi

build:
	$(GO) build ./...

vet:
	$(GO) vet ./...

test:
	@$(call go_test,./...)

# Prove the shared library resolves and that the headers agree with the
# binary, without running the full suite.
smoke:
	@test -f "$(LIB_DIR)/libghostty-vt.dylib" -o -f "$(LIB_DIR)/libghostty-vt.so" \
		|| { echo "missing libghostty-vt in $(LIB_DIR); run 'make lib'"; exit 1; }
	@$(call go_test,-run 'TestTypeManifest|TestStructSizesMatchManifest' -v .)

clean:
	$(GO) clean ./...
