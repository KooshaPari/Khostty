#!/usr/bin/env bash
#
# Build script for the Khostty VT/ANSI conformance suite.
#
# Compiles conformance/harness.c against the prebuilt libghostty-vt
# produced by G1 (zig-out/lib/libghostty-vt.dylib) and emits
# zig-out/bin/conformance_test.
#
# Usage:
#   conformance/build.sh           # build + run
#   conformance/build.sh build     # build only
#   conformance/build.sh run       # run only (assumes build done)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${SDK:-/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.sdk}"

if [[ ! -d "$SDK" ]]; then
    SDK="$(ls -d /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX2*.sdk 2>/dev/null | grep -v 27 | sort | tail -1)"
fi

if [[ ! -f "$REPO_ROOT/zig-out/lib/libghostty-vt.dylib" ]]; then
    echo "error: libghostty-vt.dylib not found at zig-out/lib/" >&2
    echo "       run 'zig build' first to produce the G1 artifacts." >&2
    exit 1
fi

mkdir -p "$REPO_ROOT/zig-out/bin"

cc -I"$REPO_ROOT/include" -O2 \
   -isysroot "$SDK" \
   "$REPO_ROOT/conformance/harness.c" \
   "$REPO_ROOT/zig-out/lib/libghostty-vt.dylib" \
   -o "$REPO_ROOT/zig-out/bin/conformance_test"

echo "built: $REPO_ROOT/zig-out/bin/conformance_test"

if [[ "${1:-run}" == "run" ]]; then
    DYLD_LIBRARY_PATH="$REPO_ROOT/zig-out/lib" \
    "$REPO_ROOT/zig-out/bin/conformance_test"
fi
