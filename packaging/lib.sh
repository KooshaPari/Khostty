#!/usr/bin/env bash
# Shared helpers for the Khostty release packaging scripts.
#
# Sourced, never executed. Every script in this directory starts with:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# Design rules for everything here:
#   1. Never fabricate a result. If a step cannot run on this host, the script
#      fails loudly and names the missing tool; it never prints a success line
#      for work it did not do.
#   2. Every produced file gets a real sha256, computed from the file on disk.
#   3. Artifacts are staged under `$OUT`, which defaults to
#      `<repo>/dist-release`. Nothing is written into the source subtrees.
set -euo pipefail

# --- paths -----------------------------------------------------------------

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$PKG_DIR/.." && pwd)"
OUT="${KHOSTTY_RELEASE_OUT:-$REPO_ROOT/dist-release}"
RELEASE_DIR="$REPO_ROOT/release"
LOG_DIR="${KHOSTTY_RELEASE_LOGS:-$OUT/logs}"

# The repo-local `.zig-cache` is corrupt in this container (a stale build runner
# registers `zig-pkg/<dep>` paths that no longer exist and every Zig invocation
# dies with `FileNotFound`). Every Zig call in this directory therefore passes
# explicit cache dirs. Override with KHOSTTY_ZIG_CACHE_DIR /
# KHOSTTY_ZIG_GLOBAL_CACHE_DIR when a healthy local cache is available.
ZIG_CACHE_DIR="${KHOSTTY_ZIG_CACHE_DIR:-${JCODE_SCRATCH_DIR:-$OUT/cache}/zc/o}"
ZIG_GLOBAL_CACHE_DIR="${KHOSTTY_ZIG_GLOBAL_CACHE_DIR:-${JCODE_SCRATCH_DIR:-$OUT/cache}/zc/g}"

# --- output ----------------------------------------------------------------

if [[ -t 2 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
else
  C_RESET=''; C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''
fi

log()  { printf '%s\n' "$*" >&2; }
step() { printf '%s==>%s %s\n' "$C_BOLD" "$C_RESET" "$*" >&2; }
ok()   { printf '%s ok %s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
warn() { printf '%swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%sFAIL%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# Print a line that records something the operator must not mistake for a pass.
unverified() {
  printf '%sUNVERIFIED ON THIS HOST%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2
}

have() { command -v "$1" >/dev/null 2>&1; }

require() {
  local tool="$1" why="${2:-}"
  have "$tool" || die "missing required tool \`$tool\`${why:+ — needed to $why}"
}

# --- hashing ---------------------------------------------------------------

# sha256 of a file, lowercase hex, no filename.
sha256() {
  [[ -f "$1" ]] || die "sha256: not a file: $1"
  if have shasum; then shasum -a 256 "$1" | awk '{print $1}'
  elif have sha256sum; then sha256sum "$1" | awk '{print $1}'
  else die "no sha256 tool (need shasum or sha256sum)"
  fi
}

# `sha256sum`-format line: "<hash>  <basename>" for a file inside $OUT.
sums_line() {
  local f="$1"
  printf '%s  %s\n' "$(sha256 "$f")" "$(basename "$f")"
}

human_size() {
  local bytes
  bytes="$(wc -c <"$1" | tr -d ' ')"
  if   (( bytes >= 1048576 )); then printf '%d.%d MiB' $((bytes/1048576)) $(( (bytes%1048576)*10/1048576 ))
  elif (( bytes >= 1024 ));    then printf '%d.%d KiB' $((bytes/1024)) $(( (bytes%1024)*10/1024 ))
  else printf '%d B' "$bytes"
  fi
}

# --- build helpers ---------------------------------------------------------

zig_build() {
  require zig "build libghostty-vt"
  zig build \
    --cache-dir "$ZIG_CACHE_DIR" \
    --global-cache-dir "$ZIG_GLOBAL_CACHE_DIR" \
    "$@"
}

# Fresh staging directory under $OUT.
stage() {
  local name="$1"
  local dir="$OUT/stage/$name"
  rm -rf "$dir"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

# Timestamp to stamp into archives. Defaults to the source commit time, so a
# tarball is a pure function of (content, entry order, prefix, commit). Override
# with SOURCE_DATE_EPOCH (the reproducible-builds convention).
source_epoch() {
  if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then printf '%s' "$SOURCE_DATE_EPOCH"; return; fi
  local ct
  ct="$(git -C "$REPO_ROOT" log -1 --format=%ct HEAD 2>/dev/null || true)"
  printf '%s' "${ct:-0}"
}

# Deterministic tar.gz: fixed mtime, sorted entry order, zeroed ownership, no
# xattrs or resource forks, and no gzip timestamp or original filename.
#
# Written against BSD tar (the `tar` on macOS) rather than GNU tar, because the
# release is prepared on macOS and `--sort=name` / `--mtime` are GNU-only. The
# two behaviours that matter are obtained a different way:
#   * entry order  -> an explicit `LC_ALL=C sort`ed file list via `-T`
#   * mtime        -> `touch -t` on the staged tree before archiving
# The result is byte-identical across runs, which is what makes the manifest
# sha256 meaningful instead of an incidental value.
det_tar() {
  local out="$1" root="$2" prefix="$3"
  local epoch stamp list
  epoch="$(source_epoch)"
  stamp="$(date -u -r "$epoch" +%Y%m%d%H%M.%S 2>/dev/null || date -u -d "@$epoch" +%Y%m%d%H%M.%S)"

  # Normalize timestamps on every entry, deepest last so directories keep the
  # same stamp as their contents.
  ( cd "$root" && find "$prefix" -exec touch -h -t "$stamp" {} + )

  list="$(mktemp)"
  ( cd "$root" && find "$prefix" -print | LC_ALL=C sort ) >"$list"

  mkdir -p "$(dirname "$out")"
  local tmp_tar="$out.tmp.tar"
  ( cd "$root" && COPYFILE_DISABLE=1 tar \
      --format=ustar \
      --uid 0 --gid 0 \
      --no-acls --no-xattrs --no-mac-metadata \
      -cf "$tmp_tar" -T "$list" )
  rm -f "$list"
  # Compress by streaming rather than in place. macOS gzip derives its output
  # name from the input name, and `gzip foo.tar.gz` yields `foo.tar.gz.gz`, so
  # letting gzip choose the name is a trap. `-n` drops the timestamp and the
  # original filename from the gzip header, which is required for determinism.
  gzip -9 -n -c "$tmp_tar" >"$out"
  rm -f "$tmp_tar"
}

# sha256 of a tree of files, excluding per-run noise. Used to prove that a
# staged directory was packaged from the bytes we think it was.
tree_digest() {
  local dir="$1"
  ( cd "$dir" && find . -type f -print0 \
      | LC_ALL=C sort -z \
      | xargs -0 shasum -a 256 \
      | shasum -a 256 | awk '{print $1}' )
}
