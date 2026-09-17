#!/usr/bin/env bash
# Build libghostty-vt for wasm32 and install it as wasm/khostty-vt.wasm.
#
# The upstream build.zig already knows how to emit wasm: when the target
# architecture is wasm it routes through GhosttyLibVt.initWasm(), which
# produces a freestanding module with rdynamic exports, a growable indirect
# function table, no entrypoint, and a 128 KB stack. This script only pins the
# target, isolates the build cache, and verifies the artifact.
#
# Usage:
#   wasm/build.sh                 # ReleaseSmall (default)
#   wasm/build.sh --debug         # Debug build, much larger
#   wasm/build.sh --optimize ReleaseFast
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
out="$here/khostty-vt.wasm"

optimize="ReleaseSmall"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) optimize="Debug"; shift ;;
    --optimize) optimize="$2"; shift 2 ;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v zig >/dev/null 2>&1 || {
  echo "error: zig is not on PATH (libghostty-vt needs zig 0.16+)" >&2
  exit 1
}
echo "zig $(zig version)"

# Use a dedicated cache directory. Two reasons:
#   1. The wasm and host targets share no compilation artifacts, so a shared
#      cache only adds lock contention with concurrent native builds.
#   2. A cached build runner generated against a different zig-pkg layout can
#      go stale and fail at startup with `unable to open .../zig-pkg/<dep>:
#      FileNotFound`, which is unrelated to this build.
cache="${KHOSTTY_WASM_CACHE:-$root/.zig-cache/wasm}"
prefix="$root/.zig-cache/wasm-out"
mkdir -p "$cache" "$prefix"

echo "building libghostty-vt for wasm32-freestanding ($optimize)"
zig build \
  -Demit-lib-vt \
  -Dtarget=wasm32-freestanding \
  -Doptimize="$optimize" \
  --cache-dir "$cache" \
  --prefix "$prefix"

built="$prefix/bin/ghostty-vt.wasm"
[[ -f "$built" ]] || { echo "error: $built was not produced" >&2; exit 1; }

# Validate the artifact rather than trusting the build's exit code: it must
# start with the WebAssembly magic + version 1 preamble.
if [[ "$(head -c 4 "$built" | od -An -tx1 | tr -d ' \n')" != "0061736d" ]]; then
  echo "error: $built is not a WebAssembly module (bad magic)" >&2
  exit 1
fi
if [[ "$(dd if="$built" bs=1 skip=4 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')" != "01000000" ]]; then
  echo "error: $built is not WebAssembly version 1" >&2
  exit 1
fi

cp "$built" "$out"

bytes="$(wc -c <"$out" | tr -d ' ')"
sha="$(shasum -a 256 "$out" | awk '{print $1}')"
echo "wrote wasm/khostty-vt.wasm  ${bytes} bytes  sha256 ${sha}"
