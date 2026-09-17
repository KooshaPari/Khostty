#!/usr/bin/env bash
# Verify wasm/include/ghostty-vt.h: that it is in sync with include/ghostty/,
# that it compiles standalone with no include path, and that it exposes exactly
# the same set of GHOSTTY_API function names as the real headers.
#
# Usage: wasm/tools/verify-header.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
header="$root/wasm/include/ghostty-vt.h"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

[[ -f "$header" ]] || fail "$header missing; run: node wasm/tools/gen-consolidated-header.mjs"

# 1. Drift check: regenerating must be a no-op.
before="$(shasum -a 256 "$header" | awk '{print $1}')"
node "$here/gen-consolidated-header.mjs" >/dev/null
after="$(shasum -a 256 "$header" | awk '{print $1}')"
if [[ "$before" != "$after" ]]; then
  fail "wasm/include/ghostty-vt.h is stale; commit the regenerated file"
fi
ok "in sync with include/ghostty/ (sha256 ${after:0:12})"

# 2. Standalone syntax check: must need no -I at all.
#
# -Wunused-function is suppressed because the upstream headers ship
# `static inline` accessors (ghostty_mode_new and friends) that any given
# consumer uses only a subset of. That is inherent to the public headers, not
# to consolidation, and the same warnings appear when including <ghostty/vt.h>
# directly.
warn_flags=(-Wall -Wextra -Wno-unused-function)

if command -v clang >/dev/null 2>&1; then
  clang -fsyntax-only "${warn_flags[@]}" -x c "$header" \
    || fail "clang -fsyntax-only rejected the consolidated header"
  ok "compiles standalone (clang -fsyntax-only, warnings enabled)"
fi

# Also confirm it works as an included header in a real TU, with C++ linkage.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/tu.c" <<EOF
#include "ghostty-vt.h"
int main(void) { return (int)(ghostty_type_json() != 0) - 1; }
EOF
if command -v clang >/dev/null 2>&1; then
  clang -fsyntax-only "${warn_flags[@]}" -x c "$tmp/tu.c" -I"$(dirname "$header")" \
    || fail "C translation unit including the header failed"
  ok "usable from a C translation unit (clang)"
fi
if command -v zig >/dev/null 2>&1; then
  # `zig cc -fsyntax-only` cannot compile with no -o target (it reports
  # FileNotFound), so compile to a real object file instead.
  zig cc -c "${warn_flags[@]}" -x c "$tmp/tu.c" -I"$(dirname "$header")" -o "$tmp/tu.o" \
    || fail "zig cc rejected a translation unit including the header"
  ok "usable from a zig cc translation unit"
fi

# 3. Symbol-set equality against the real headers.
# The upstream headers and the consolidated header both spell declarations
# `GHOSTTY_API <ret> ghostty_name(`. Slurp-and-regex handles wrapped
# signatures that a line-oriented grep would miss.
symbols_from() {
  python3 - "$1" <<'PY'
import re, sys, pathlib
text = pathlib.Path(sys.argv[1]).read_text()
pat = re.compile(r"GHOSTTY_API\b[^;{}#]*?\b(ghostty_[A-Za-z0-9_]+)\s*\(", re.S)
print("\n".join(sorted(set(pat.findall(text)))))
PY
}

# Collect declarations from every header libghostty-vt publishes, since
# <ghostty/vt.h> is only an umbrella over them.
real="$(python3 - "$root" <<'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1]) / "include" / "ghostty"
pat = re.compile(r"GHOSTTY_API\b[^;{}#]*?\b(ghostty_[A-Za-z0-9_]+)\s*\(", re.S)
names = set()
for path in sorted(root.rglob("*.h")):
    names |= set(pat.findall(path.read_text()))
print("\n".join(sorted(names)))
PY
)"
consolidated="$(symbols_from "$header")"

missing="$(comm -23 <(printf '%s\n' "$real") <(printf '%s\n' "$consolidated") || true)"
extra="$(comm -13 <(printf '%s\n' "$real") <(printf '%s\n' "$consolidated") || true)"

[[ -z "$missing" ]] || fail "declarations missing from consolidated header:"$'\n'"$missing"
[[ -z "$extra" ]] || fail "declarations present only in consolidated header:"$'\n'"$extra"

count="$(printf '%s\n' "$real" | grep -c . || true)"
[[ "$count" -gt 0 ]] || fail "symbol extraction found nothing; the check is not running"
ok "public API surface identical: $count ghostty_* functions"
