#!/usr/bin/env bash
#
# Build the Khostty benchmark harness.
#
# Mirrors conformance/build.sh: the harness is plain C compiled against the
# prebuilt libghostty-vt, so the numbers measure the shipped library rather
# than a separate reimplementation.
#
# Usage:
#   bench/build.sh                 # build bench_khostty against zig-out/lib
#   bench/build.sh khostty         # same, explicit
#   bench/build.sh upstream        # build bench_upstream against upstream Ghostty
#   bench/build.sh upstream /path/to/ghostty/zig-out/lib
#
# Environment:
#   UPSTREAM_REPO     upstream Ghostty checkout (default: sibling ../ghostty)
#   UPSTREAM_LIB_DIR  override the upstream lib directory directly
#
# Preconditions:
#   zig build must have produced zig-out/lib/libghostty-vt.dylib (and the same
#   for the upstream checkout when building the comparison binary).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VARIANT="${1:-khostty}"
LIB_DIR_ARG="${2:-}"
BUILD_DIR="$REPO_ROOT/bench/.build"

# Use the newest macOS SDK in the active Xcode install. Passing -isysroot
# explicitly keeps the build working in environments where the command line
# tools default to a different SDK than the one libghostty-vt was built against.
SDK_PATTERN=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk
SDK="${SDK:-$(ls -d $SDK_PATTERN 2>/dev/null | sort | tail -1)}"

# Deliberately unquoted: bash 3.2 (macOS) errors on an empty array expansion
# under set -u, and the Xcode SDK path contains no spaces.
SDK_FLAGS=""
if [[ -n "$SDK" && -d "$SDK" ]]; then
    SDK_FLAGS="-isysroot $SDK"
fi

case "$VARIANT" in
    khostty)
        LIB_DIR="$REPO_ROOT/zig-out/lib"
        LABEL="khostty"
        ;;
    upstream)
        if [[ -n "$LIB_DIR_ARG" ]]; then
            LIB_DIR="$LIB_DIR_ARG"
        elif [[ -n "${UPSTREAM_LIB_DIR:-}" ]]; then
            LIB_DIR="$UPSTREAM_LIB_DIR"
        else
            UPSTREAM_REPO="${UPSTREAM_REPO:-$(cd "$REPO_ROOT/.." && pwd)/ghostty}"
            LIB_DIR="$UPSTREAM_REPO/zig-out/lib"
        fi
        LABEL="upstream"
        ;;
    *)
        echo "error: unknown variant '$VARIANT' (expected khostty or upstream)" >&2
        exit 2
        ;;
esac

if [[ ! -e "$LIB_DIR/libghostty-vt.dylib" ]]; then
    echo "error: $LIB_DIR/libghostty-vt.dylib not found" >&2
    echo "       run 'zig build' in the corresponding checkout first" >&2
    exit 1
fi

mkdir -p "$BUILD_DIR"
OUT="$BUILD_DIR/bench_$LABEL"

# The search API is newer than some upstream revisions. Detect it in the target
# library and swap in the "unavailable" translation unit rather than failing to
# link, so a comparison against an older revision still produces honest results
# for every other section.
SEARCH_SRC="$REPO_ROOT/bench/bench_search.c"
if ! nm -gU "$LIB_DIR/libghostty-vt.dylib" 2>/dev/null | grep -q "_ghostty_search_new"; then
    SEARCH_SRC="$REPO_ROOT/bench/bench_search_stub.c"
    echo "note: $LIB_DIR/libghostty-vt.dylib has no ghostty_search_* API;" >&2
    echo "      bench 8.4 will be reported as unavailable" >&2
fi

cc -I"$REPO_ROOT/include" -O2 -Wall -Wextra -std=c11 \
   $SDK_FLAGS \
   "$REPO_ROOT/bench/main.c" \
   "$REPO_ROOT/bench/bench_util.c" \
   "$REPO_ROOT/bench/bench_vt.c" \
   "$REPO_ROOT/bench/bench_snapshot.c" \
   "$SEARCH_SRC" \
   "$REPO_ROOT/bench/bench_memory.c" \
   "$REPO_ROOT/bench/bench_resize.c" \
   -L"$LIB_DIR" -lghostty-vt -Wl,-rpath,"$LIB_DIR" \
   -o "$OUT"

# Stamp the exact library that was linked, so run.sh can record the resolved
# path and its digest without duplicating the variant-to-directory logic here.
printf '%s\n' "$LIB_DIR/libghostty-vt.dylib" > "$BUILD_DIR/$LABEL.libpath"

echo "built: $OUT  (label=$LABEL, library=$LIB_DIR/libghostty-vt.dylib)"
