#!/usr/bin/env bash
# Resolve the Khostty release version and the upstream base it sits on.
#
#   packaging/version.sh            # human-readable block
#   packaging/version.sh --json     # machine-readable, for the manifest
#   packaging/version.sh --print    # just the Khostty version, no newline noise
#
# Version scheme (WBS 10.1)
# -------------------------
# Khostty versions itself independently of the Ghostty release it tracks:
#
#   <major>.<minor>.<patch>[-<pre>][+ghostty.<upstream-base-version>.<base-sha7>]
#
#   * major.minor.patch  SemVer 2.0.0 for the *Khostty* deliverable, not for
#                        upstream Ghostty. 0.x means the agent-facing surfaces
#                        (IPC v1, the polyglot bindings) are not yet frozen.
#   * -pre               Optional prerelease tag (`-rc.1`, `-dev`).
#   * +ghostty.<...>     Build metadata naming the upstream commit the fork is
#                        based on. Build metadata is ignored for precedence, so
#                        it does not change how the version sorts.
#
# The number that matters for ABI consumers is `lib_version` in `build.zig`,
# because it becomes the shared-library SONAME (`libghostty-vt.0.1.0.dylib`).
# This script reads it and strips the `-dev` marker rather than keeping a
# second copy of the number somewhere that can drift.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# --- single source of truth: build.zig's lib_version -----------------------

lib_version_raw="$(
  sed -n 's/^const lib_version = "\(.*\)";$/\1/p' "$REPO_ROOT/build.zig"
)"
[[ -n "$lib_version_raw" ]] || die "could not read lib_version from build.zig"

# `0.1.0-dev` -> version `0.1.0`, prerelease `dev`. A bare `0.1.0` has none.
if [[ "$lib_version_raw" == *-* ]]; then
  KHOSTTY_VERSION="${lib_version_raw%%-*}"
  KHOSTTY_PRERELEASE="${lib_version_raw#*-}"
else
  KHOSTTY_VERSION="$lib_version_raw"
  KHOSTTY_PRERELEASE=""
fi

# --- upstream base ---------------------------------------------------------

# `build.zig.zon` carries upstream Ghostty's version, not Khostty's.
UPSTREAM_VERSION="$(
  sed -n 's/^ *\.version = "\(.*\)",$/\1/p' "$REPO_ROOT/build.zig.zon" | head -1
)"
[[ -n "$UPSTREAM_VERSION" ]] || UPSTREAM_VERSION="UNKNOWN"

if git -C "$REPO_ROOT" rev-parse --verify --quiet upstream/main >/dev/null; then
  UPSTREAM_BASE_COMMIT="$(git -C "$REPO_ROOT" merge-base main upstream/main)"
else
  UPSTREAM_BASE_COMMIT="UNKNOWN"
fi
if [[ "$UPSTREAM_BASE_COMMIT" != "UNKNOWN" ]]; then
  UPSTREAM_BASE_SHA7="${UPSTREAM_BASE_COMMIT:0:7}"
  UPSTREAM_BASE_DATE="$(git -C "$REPO_ROOT" log -1 --format=%ad --date=short "$UPSTREAM_BASE_COMMIT")"
else
  UPSTREAM_BASE_SHA7="UNKNOWN"
  UPSTREAM_BASE_DATE="UNKNOWN"
fi

# The exact tree that gets built, so the manifest can be tied to a revision.
if git -C "$REPO_ROOT" rev-parse --verify --quiet HEAD >/dev/null; then
  SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  SOURCE_COMMIT_SHA7="${SOURCE_COMMIT:0:7}"
  SOURCE_DIRTY=no
  git -C "$REPO_ROOT" diff --quiet HEAD -- . >/dev/null 2>&1 || SOURCE_DIRTY=yes
else
  SOURCE_COMMIT="UNKNOWN"; SOURCE_COMMIT_SHA7="UNKNOWN"; SOURCE_DIRTY=unknown
fi

# --- cross-manifest agreement check ---------------------------------------
# The Rust crate and the Python package each declare their own version. If one
# of them drifts from build.zig the release is inconsistent, and it is much
# cheaper to find that here than in a published artifact.

check_agreement() {
  local problems=0 cargo_ver py_ver

  cargo_ver="$(sed -n 's/^version = "\(.*\)"$/\1/p' "$REPO_ROOT/khostty-vt/Cargo.toml" | head -1)"
  if [[ -n "$cargo_ver" && "$cargo_ver" != "$KHOSTTY_VERSION" ]]; then
    warn "khostty-vt/Cargo.toml version=$cargo_ver != build.zig lib_version=$KHOSTTY_VERSION"
    problems=$((problems + 1))
  fi

  py_ver="$(sed -n 's/^version = "\(.*\)"$/\1/p' "$REPO_ROOT/khostty-python/pyproject.toml" | head -1)"
  if [[ -n "$py_ver" && "$py_ver" != "$KHOSTTY_VERSION" ]]; then
    warn "khostty-python/pyproject.toml version=$py_ver != build.zig lib_version=$KHOSTTY_VERSION"
    problems=$((problems + 1))
  fi

  return "$problems"
}

case "${1:---human}" in
  --print) printf '%s\n' "$KHOSTTY_VERSION" ;;
  --json)
    check_agreement || true
    cat <<JSON
{
  "version": "$KHOSTTY_VERSION",
  "prerelease": "$KHOSTTY_PRERELEASE",
  "lib_version_raw": "$lib_version_raw",
  "upstream_version": "$UPSTREAM_VERSION",
  "upstream_base_commit": "$UPSTREAM_BASE_COMMIT",
  "upstream_base_date": "$UPSTREAM_BASE_DATE",
  "source_commit": "$SOURCE_COMMIT",
  "source_dirty": "$SOURCE_DIRTY"
}
JSON
    ;;
  --human | *)
    cat <<HUMAN
Khostty version        $KHOSTTY_VERSION${KHOSTTY_PRERELEASE:+ ($KHOSTTY_PRERELEASE)}
  from                 build.zig lib_version = "$lib_version_raw"
  ABI soname           libghostty-vt.$KHOSTTY_VERSION
Upstream base          ghostty $UPSTREAM_VERSION @ $UPSTREAM_BASE_SHA7 ($UPSTREAM_BASE_DATE)
Source revision        $SOURCE_COMMIT_SHA7 (dirty: $SOURCE_DIRTY)
HUMAN
    check_agreement || warn "version manifests disagree (see above)"
    ;;
esac
