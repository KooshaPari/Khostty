#!/usr/bin/env bash
# WBS 9.14 — package the WASM dist as a reproducible npm-style tarball.
#
#   packaging/wasm-dist.sh                 # build, clear checks, package, verify
#   packaging/wasm-dist.sh --no-build      # reuse wasm/khostty-vt.wasm
#   packaging/wasm-dist.sh --skip-source-tests
#
# This is the one packaging target that is fully verifiable on macOS, so it is
# also the one that produces a fully verified artifact: the script builds the
# module, runs the repository's own WASM suite against a *rebuilt* binary,
# assembles the dist, tars it deterministically, extracts it to a scratch
# directory, and runs `packaging/wasm-smoke.mjs` against the extracted copy.
#
# The source-tree test suite and the extracted-artifact smoke test are separate
# claims on purpose. A tarball can omit a file the suite never needed; only the
# extracted-artifact run catches that.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

BUILD=1
SOURCE_TESTS=1
for arg in "$@"; do
  case "$arg" in
    --no-build) BUILD=0 ;;
    --skip-source-tests) SOURCE_TESTS=0 ;;
    -h | --help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $arg" ;;
  esac
done

require node "run the WASM test suite and the tarball smoke test"

VERSION="$(bash "$PKG_DIR/version.sh" --print)"
PKGNAME="khostty-libghostty-vt-wasm"
STEM="$PKGNAME-$VERSION"
WASM_SRC="$REPO_ROOT/wasm"
WASM_BIN="$WASM_SRC/khostty-vt.wasm"

mkdir -p "$OUT/wasm" "$LOG_DIR"

# ---------------------------------------------------------------- 1. build --

if (( BUILD )); then
  step "building libghostty-vt for wasm32-freestanding (ReleaseSmall)"
  # wasm/build.sh owns the wasm build: it pins the target, isolates the cache,
  # and validates the module preamble. Reimplementing it here would be a second
  # source of truth for the same build.
  ( cd "$WASM_SRC" && ./build.sh ) 2>&1 | tee "$LOG_DIR/wasm-build.log"
else
  step "reusing existing $WASM_BIN (--no-build)"
  [[ -f "$WASM_BIN" ]] || die "$WASM_BIN is missing; drop --no-build"
fi

[[ -f "$WASM_BIN" ]] || die "build produced no $WASM_BIN"

# ------------------------------------------------- 2. validate the artifact --

step "validating the wasm module"
magic="$(head -c 4 "$WASM_BIN" | od -An -tx1 | tr -d ' \n')"
[[ "$magic" == "0061736d" ]] || die "not a WebAssembly module (magic $magic)"
ver="$(dd if="$WASM_BIN" bs=1 skip=4 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')"
[[ "$ver" == "01000000" ]] || die "not WebAssembly version 1 (got $ver)"

WASM_BYTES="$(wc -c <"$WASM_BIN" | tr -d ' ')"
WASM_SHA="$(sha256 "$WASM_BIN")"
ok "wasm module: $WASM_BYTES bytes, sha256 $WASM_SHA"

# ------------------------------------------------- 3. source-tree test run --

if (( SOURCE_TESTS )); then
  step "running the repository WASM suite against the rebuilt module"
  # TAP rather than the default spec reporter: the spec reporter's summary is
  # decorative ("ℹ pass 54") and its glyph changes between Node versions. TAP
  # emits "# pass N" / "# fail N", which is stable enough to assert on.
  set +e
  ( cd "$WASM_SRC" && node --test --test-reporter=tap test/ ) >"$LOG_DIR/wasm-source-tests.log" 2>&1
  tests_exit=$?
  set -e
  t_pass="$(sed -n 's/^# pass \([0-9][0-9]*\)$/\1/p' "$LOG_DIR/wasm-source-tests.log" | tail -1)"
  t_fail="$(sed -n 's/^# fail \([0-9][0-9]*\)$/\1/p' "$LOG_DIR/wasm-source-tests.log" | tail -1)"
  [[ -n "$t_pass" && -n "$t_fail" ]] \
    || die "could not parse the TAP summary (exit $tests_exit); see $LOG_DIR/wasm-source-tests.log"
  [[ "$tests_exit" == "0" && "$t_fail" == "0" && "$t_pass" -gt 0 ]] \
    || die "repository WASM suite failed: $t_pass passed, $t_fail failed (exit $tests_exit); see $LOG_DIR/wasm-source-tests.log"
  SOURCE_TEST_SUMMARY="$t_pass passed, 0 failed"
  ok "repository WASM suite: $SOURCE_TEST_SUMMARY"
else
  SOURCE_TEST_SUMMARY="skipped"
  unverified "repository WASM suite skipped (--skip-source-tests); the tarball smoke test still runs"
fi

# ------------------------------------------------------------- 4. assemble --

step "assembling the dist"
STAGE="$OUT/wasm/stage"
rm -rf "$OUT/wasm/stage"
mkdir -p "$STAGE/$STEM/tools" "$STAGE/$STEM/include"

cp "$WASM_SRC/khostty-vt.wasm"      "$STAGE/$STEM/khostty-vt.wasm"
cp -R "$WASM_SRC/js"                "$STAGE/$STEM/js"
cp "$WASM_SRC/include/ghostty-vt.h" "$STAGE/$STEM/include/ghostty-vt.h"
cp "$WASM_SRC/README.md"            "$STAGE/$STEM/README.md"
cp "$WASM_SRC/tools/wasm-exports.mjs" "$STAGE/$STEM/tools/wasm-exports.mjs"
cp "$PKG_DIR/wasm-smoke.mjs"        "$STAGE/$STEM/smoke.mjs"
cp "$REPO_ROOT/LICENSE"             "$STAGE/$STEM/LICENSE"

# The source manifest is `private: true` with version 0.0.0, which is correct
# for an unpublished working tree and wrong for a release tarball. Patch it
# here rather than in `wasm/` so the source tree keeps one manifest.
step "patching package.json for release (version $VERSION, private removed)"
node --input-type=module -e '
  import { readFileSync, writeFileSync } from "node:fs";
  const [src, dst, version] = process.argv.slice(1);
  const pkg = JSON.parse(readFileSync(src, "utf8"));
  pkg.version = version;
  delete pkg.private;
  pkg.name = "khostty-libghostty-vt-wasm";
  pkg.description =
    "WebAssembly bindings for libghostty-vt, the Ghostty virtual terminal " +
    "emulator library, carried in the Khostty fork";
  pkg.files = ["js/", "tools/", "include/", "khostty-vt.wasm", "smoke.mjs", "README.md"];
  pkg.scripts = { test: "node smoke.mjs" };
  pkg.repository = { type: "git", url: "git+https://github.com/KooshaPari/Khostty.git" };
  pkg.homepage = "https://github.com/KooshaPari/Khostty#readme";
  pkg.bugs = { url: "https://github.com/KooshaPari/Khostty/issues" };
  writeFileSync(dst, JSON.stringify(pkg, null, 2) + "\n");
' "$WASM_SRC/package.json" "$STAGE/$STEM/package.json" "$VERSION"

# Provenance travels with the artifact so a consumer can tell which commit and
# which upstream base they are holding without network access.
bash "$PKG_DIR/version.sh" --json >"$STAGE/$STEM/khostty-version.json"
printf '%s\n' "$WASM_SHA" >"$STAGE/$STEM/khostty-vt.wasm.sha256"

# ------------------------------------------------------- 5. deterministic tar --

step "creating the tarball"
TARBALL="$OUT/wasm/$STEM.tar.gz"
det_tar "$TARBALL" "$STAGE" "$STEM"
TAR_SHA="$(sha256 "$TARBALL")"
ok "tarball: $(human_size "$TARBALL"), sha256 $TAR_SHA"

# Reproducibility is a claim, not an assumption: build the same tar twice and
# compare. If the bytes differ the manifest hash is not reproducible and the
# operator needs to know now, not after publishing.
step "re-checking determinism (second identical tar)"
TARBALL2="$OUT/wasm/$STEM.repack.tar.gz"
det_tar "$TARBALL2" "$STAGE" "$STEM"
TAR2_SHA="$(sha256 "$TARBALL2")"
if [[ "$TAR_SHA" == "$TAR2_SHA" ]]; then
  ok "byte-identical on repack"
else
  die "tarball is NOT deterministic: $TAR_SHA != $TAR2_SHA"
fi
rm -f "$TARBALL2"

# ---------------------------------------- 6. verify against the extracted copy --

step "extracting to scratch and running the consumer smoke test"
VERIFY="$OUT/wasm/verify"
rm -rf "$OUT/wasm/verify"
mkdir -p "$VERIFY"
( cd "$VERIFY" && tar -xzf "$TARBALL" )
[[ -f "$VERIFY/$STEM/smoke.mjs" ]] || die "extracted tarball has no smoke.mjs"

set +e
( cd "$VERIFY/$STEM" && node smoke.mjs --json ) >"$LOG_DIR/wasm-tarball-smoke.json" 2>&1
smoke_exit=$?
set -e
# Parse the JSON report rather than scraping the pretty output: the number of
# passing checks has to be compared against the number of failures, so a
# "13/14 checks passed" line can never be mistaken for success.
read -r smoke_total smoke_failed < <(node --input-type=module -e '
  import { readFileSync } from "node:fs";
  const [file] = process.argv.slice(1);
  const r = JSON.parse(readFileSync(file, "utf8")).results;
  process.stdout.write(`${r.length} ${r.filter((x) => !x.ok).length}\n`);
' "$LOG_DIR/wasm-tarball-smoke.json" 2>/dev/null || echo "0 0")
[[ "$smoke_total" -gt 0 ]] || die "smoke test produced no parseable report (exit $smoke_exit); see $LOG_DIR/wasm-tarball-smoke.json"
[[ "$smoke_failed" == "0" && "$smoke_exit" == "0" ]] \
  || die "$smoke_failed/$smoke_total tarball smoke checks failed (exit $smoke_exit); see $LOG_DIR/wasm-tarball-smoke.json"
ok "extracted-tarball smoke test: $smoke_total/$smoke_total checks passed"

# An `npm pack`-style integrity file, since npm consumers check this format.
( cd "$OUT/wasm" && printf '%s  %s\n' "$TAR_SHA" "$STEM.tar.gz" >"$STEM.tar.gz.sha256" )

step "done"
cat >&2 <<SUMMARY
  artifact      $TARBALL
  size          $(human_size "$TARBALL")
  sha256        $TAR_SHA
  wasm module   $WASM_BYTES bytes, sha256 $WASM_SHA
  repo suite    $SOURCE_TEST_SUMMARY
  tarball check $smoke_total/$smoke_total consumer checks passed (extracted copy)
  logs          $LOG_DIR/
SUMMARY
