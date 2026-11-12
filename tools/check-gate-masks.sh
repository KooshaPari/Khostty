#!/usr/bin/env bash
# Assert that the CI gates in this fork can actually fail.
#
# Background: every gate in `docs/audit/2026-11-12-inert-ci-gates/REPORT.md` was
# at some point decorative - `continue-on-error: true`, a trailing
# `|| echo "::warning::..."`, or a job that never ran at all - and each one
# reported green while the underlying tool was red. Those were fixed one at a
# time, individually, with no check that stops the next person from re-adding a
# mask "just to get CI green". This script is that check.
#
# It is deliberately a static check on the workflow files, because that is the
# property we care about: the mask is visible in the YAML long before the tool
# that it hides has anything to say.
#
# Usage:
#   bash tools/check-gate-masks.sh            # exit 0 clean / 1 masked-or-missing
#   bash tools/check-gate-masks.sh --list     # print every mask found, ignore allowlist
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

list_only=false
if [[ "${1:-}" == "--list" ]]; then
  list_only=true
fi

# Workflows whose masks are deliberate, with the reason. An entry here is a
# decision that has been written down, not a way to silence this check: if the
# reason stops being true, the entry must go.
#
#   ci-fork-discipline.yml  the only masked step publishes the report as a PR
#                           comment; the check that can fail is the step before
#                           it, and a read-only token on a fork PR must not fail
#                           the run.
#   test.yml                upstream-owned. `test-esctest` is upstream
#                           report-only and is additionally guarded by
#                           `if: github.repository == 'ghostty-org/ghostty'`, so
#                           it never runs from this fork.
allowed_paths=(
  ".github/workflows/ci-fork-discipline.yml"
  ".github/workflows/test.yml"
)

is_allowed() {
  local path=$1 candidate
  for candidate in "${allowed_paths[@]}"; do
    [[ "$path" == "$candidate" ]] && return 0
  done
  return 1
}

# Two idioms. `continue-on-error: true` swallows a non-zero exit at the step or
# job level; `|| echo "::warning::..."` swallows it inside a `run:` block. A bare
# `|| true` is NOT flagged: it is used legitimately for cleanup and for greps
# that are allowed to match nothing, and flagging it would make this check noise.
masks=$(grep -rn --include='*.yml' --include='*.yaml' -E \
  '^[[:space:]]*continue-on-error:[[:space:]]*true[[:space:]]*$|\|\|[[:space:]]*echo[[:space:]]+"?::warning' \
  .github/workflows \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)

if $list_only; then
  if [[ -z "$masks" ]]; then
    echo "no mask idioms found in .github/workflows"
  else
    echo "$masks"
  fi
  exit 0
fi

fail=0
echo "== mask idioms =="
if [[ -z "$masks" ]]; then
  echo "  none"
else
  while IFS= read -r line; do
    path=${line%%:*}
    if is_allowed "$path"; then
      echo "  ok (documented): $line"
    else
      echo "  MASKED: $line"
      fail=1
    fi
  done <<<"$masks"
fi

# The gates that were repaired. Each entry is the exact command line that must be
# present, verbatim, in the workflow named after it. Asserting the command rather
# than "the step exists" is what makes this fail if someone downgrades the gate
# (drops `--all-targets`, drops `-- -D warnings`, or points clippy back at a
# subset of targets).
required_ci=(
  "cargo +nightly-2026-11-11 fmt --all -- --check"
  "cargo clippy --all-targets -- -D warnings"
  "cargo deny --manifest-path khostty-vt/Cargo.toml check"
  "ruff check ."
  "ruff format --check ."
)

echo "== required gate commands in ci.yml =="
# Match the command anywhere on a non-comment line, ignoring indentation: the
# cargo-deny command sits inside a `run: |` block, and pinning the exact leading
# whitespace would make this check fail on a reformat rather than on a real
# regression.
for cmd in "${required_ci[@]}"; do
  if awk -v cmd="$cmd" '
    /^[[:space:]]*#/ { next }
    index($0, cmd) { found = 1; exit }
    END { exit(found ? 0 : 1) }
  ' .github/workflows/ci.yml; then
    echo "  ok: $cmd"
  else
    echo "  MISSING: $cmd"
    fail=1
  fi
done

# `has_deny` is the switch that decides whether the cargo-deny job runs at all,
# and the detect job only sets it when a deny.toml exists. Without the file the
# job silently skips, which is the original defect.
echo "== cargo-deny is switched on =="
if [[ -f khostty-vt/deny.toml ]]; then
  echo "  ok: khostty-vt/deny.toml exists"
else
  echo "  MISSING: khostty-vt/deny.toml (the cargo-deny job will be skipped)"
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo
  echo "A CI gate is masked or missing. See"
  echo "docs/audit/2026-11-12-inert-ci-gates/REPORT.md for why each gate must be"
  echo "able to fail, and add the reason to this script's allowlist if the mask is"
  echo "genuinely correct."
  exit 1
fi

echo
echo "All CI gates are unmasked and present."
