#!/usr/bin/env bash
#
# Build script for the Khostty VT/ANSI conformance suite.
#
# Compiles conformance/harness.c against the prebuilt libghostty-vt
# produced by G1 (zig-out/lib/libghostty-vt.{dylib,so}) and emits
# zig-out/bin/conformance_test.
#
# The library name, the loader path variable, and whether a macOS SDK
# sysroot is needed all differ per platform, so the build is selected from
# `uname -s`. CI runs this on ubuntu-latest, where the library is a .so and
# there is no Xcode SDK to point -isysroot at.
#
# Usage:
#   conformance/build.sh           # build + run
#   conformance/build.sh build     # build only
#   conformance/build.sh run       # run only (assumes build done)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

case "$(uname -s)" in
    Darwin)
        LIB_NAME="libghostty-vt.dylib"
        LIB_PATH_VAR="DYLD_LIBRARY_PATH"
        SDK="${SDK:-/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.sdk}"

        if [[ ! -d "$SDK" ]]; then
            # Pick the newest MacOSX2x SDK, skipping 27+. A glob (rather than
            # `ls | grep`, which shellcheck flags as SC2010) also keeps
            # `set -euo pipefail` from aborting with no message when nothing
            # matches, which is how this step used to fail silently on Linux.
            SDK=""
            for cand in /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX2*.sdk; do
                [[ -d "$cand" ]] || continue
                case "$(basename "$cand")" in
                    MacOSX27*) continue ;;
                esac
                SDK="$cand"
            done
        fi

        if [[ -z "${SDK:-}" || ! -d "$SDK" ]]; then
            echo "error: no macOS SDK found under /Applications/Xcode.app" >&2
            echo "       install Xcode, or set SDK=/path/to/MacOSX.sdk" >&2
            exit 1
        fi

        CC_FLAGS=(-isysroot "$SDK")
        ;;
    Linux)
        LIB_NAME="libghostty-vt.so"
        LIB_PATH_VAR="LD_LIBRARY_PATH"
        CC_FLAGS=()
        ;;
    *)
        echo "error: unsupported platform '$(uname -s)'" >&2
        exit 1
        ;;
esac

LIB_PATH="$REPO_ROOT/zig-out/lib/$LIB_NAME"

if [[ ! -e "$LIB_PATH" ]]; then
    # A versioned install can ship the real file as libghostty-vt.so.0.1.0 and
    # expose the unversioned name only as a symlink, or omit the symlink
    # entirely. Fall back to whatever shared object is there so an upstream
    # naming change degrades to a clear link error rather than a false
    # "not found".
    LIB_PATH="$(find "$REPO_ROOT/zig-out/lib" -maxdepth 1 -name 'libghostty-vt.*' ! -name '*.a' 2>/dev/null | sort | head -1 || true)"
fi

if [[ -z "${LIB_PATH:-}" || ! -e "$LIB_PATH" ]]; then
    echo "error: $LIB_NAME not found at zig-out/lib/" >&2
    echo "       run 'zig build' first to produce the G1 artifacts." >&2
    exit 1
fi

mkdir -p "$REPO_ROOT/zig-out/bin"

# `${CC_FLAGS[@]+"${CC_FLAGS[@]}"}` rather than a bare `${CC_FLAGS[@]}`: on
# bash 3.2 (macOS) an empty array expands to "unbound variable" under `set -u`.
cc -I"$REPO_ROOT/include" -O2 ${CC_FLAGS[@]+"${CC_FLAGS[@]}"} \
   "$REPO_ROOT/conformance/harness.c" \
   "$LIB_PATH" \
   -o "$REPO_ROOT/zig-out/bin/conformance_test"

echo "built: $REPO_ROOT/zig-out/bin/conformance_test"

if [[ "${1:-run}" == "run" ]]; then
    env "$LIB_PATH_VAR=$REPO_ROOT/zig-out/lib" \
    "$REPO_ROOT/zig-out/bin/conformance_test"
fi
