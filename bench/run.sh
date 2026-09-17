#!/usr/bin/env bash
#
# Run the Khostty benchmark harness and capture reproducible results.
#
# Writes, under bench/results/:
#   <label>-<date>.json   machine-readable metrics plus machine spec
#   <label>-<date>.txt    raw stdout of the run (the human-readable report)
#
# The raw log and the JSON are both captured in the same invocation, so the
# numbers in the report and the numbers in the JSON cannot drift apart.
#
# Usage:
#   bench/run.sh                    # build if needed, run khostty suite
#   bench/run.sh --label khostty    # explicit label
#   bench/run.sh --only search      # single section
#   bench/run.sh --upstream         # build + run the upstream comparison binary
#
# Reproducibility: the date, machine spec, and loaded library version are
# recorded in the output itself. Results are only comparable between runs with
# the same library version and machine.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="$REPO_ROOT/bench/results"
BUILD_DIR="$REPO_ROOT/bench/.build"

LABEL="khostty"
ONLY="all"
VARIANT="khostty"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --label)    LABEL="$2"; shift 2 ;;
        --only)     ONLY="$2"; shift 2 ;;
        --upstream) VARIANT="upstream"; shift ;;
        -h|--help)
            sed -n '2,25p' "$0"
            exit 0
            ;;
        *)
            echo "error: unknown argument '$1'" >&2
            exit 2
            ;;
    esac
done

if [[ "$VARIANT" == "upstream" && "$LABEL" == "khostty" ]]; then
    LABEL="upstream"
fi

mkdir -p "$RESULTS_DIR"
"$REPO_ROOT/bench/build.sh" "$VARIANT" >/dev/null

BIN="$BUILD_DIR/bench_$VARIANT"
DATE="$(TZ=America/Los_Angeles date +%Y%m%d)"
STAMP="$(TZ=America/Los_Angeles date +%Y-%m-%dT%H:%M:%S%z)"
JSON="$RESULTS_DIR/$LABEL-$DATE.json"
RAW="$RESULTS_DIR/$LABEL-$DATE.txt"

GIT_HEAD="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
GIT_DIRTY="clean"
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]]; then
    GIT_DIRTY="dirty"
fi

# Install name recorded in the binary ("@rpath/libghostty-vt.dylib") plus the
# resolved file and its digest. A digest is what makes it impossible for two
# results files to describe the same label but different binaries.
LIB_PATH="$(otool -L "$BIN" | awk '/libghostty-vt/ {print $1; exit}')"
LIB_FILE="$(cat "$BUILD_DIR/$VARIANT.libpath" 2>/dev/null || echo unknown)"
if [[ "$LIB_FILE" != "unknown" && -f "$LIB_FILE" ]]; then
    LIB_SHA="$(shasum -a 256 "$LIB_FILE" | awk '{print $1}')"
else
    LIB_SHA="unknown"
fi

# Digest of the harness sources that produced the binary. The JSON already
# records the library version and optimize mode, which is what makes a
# Debug-vs-ReleaseSafe mistake detectable; the digest makes the harness itself
# traceable even when other agents are committing to the same branch.
HARNESS_DIGEST="$(cat "$REPO_ROOT"/bench/bench.h "$REPO_ROOT"/bench/main.c \
    "$REPO_ROOT"/bench/bench_util.c "$REPO_ROOT"/bench/bench_vt.c \
    "$REPO_ROOT"/bench/bench_snapshot.c "$REPO_ROOT"/bench/bench_search.c \
    "$REPO_ROOT"/bench/bench_search_stub.c "$REPO_ROOT"/bench/bench_memory.c \
    "$REPO_ROOT"/bench/bench_resize.c | shasum -a 256 | awk '{print $1}')"

echo "running $BIN (label=$LABEL, only=$ONLY)"
echo "  results: $RAW"
echo "  results: $JSON"

# TZ is pinned so the recorded local date is Pacific local time regardless of
# the invoking shell's environment.
TZ=America/Los_Angeles "$BIN" \
    --label "$LABEL" \
    --library "${LIB_PATH:-unknown}" \
    --only "$ONLY" \
    --note "repo=/Users/kooshapari/CodeProjects/Phenotype/repos/khostty" \
    --note "git_head=$GIT_HEAD" \
    --note "git_status=$GIT_DIRTY" \
    --note "invoked_at_local=$STAMP" \
    --note "command=bench/run.sh --label $LABEL --only $ONLY" \
    --note "build=cc -O2 -Wall -Wextra -std=c11 bench/*.c -lghostty-vt" \
    --note "harness_source_sha256=$HARNESS_DIGEST" \
    --note "library_file=$LIB_FILE" \
    --note "library_sha256=$LIB_SHA" \
    --out "$JSON" | tee "$RAW"

echo
echo "captured: $RAW"
echo "captured: $JSON"
