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

# The aggregate merge gate (job id `test`, display name `ci / aggregate`) must
# fail closed: a skipped job is not a pass, and the three jobs that previously
# fed no aggregate (binding-freshness, actionlint, build) must appear in its
# needs: and in its result loop.
echo "== aggregate gate is fail-closed =="
if grep -n 'elif \[ "$result" = "success" \] || \[ "$result" = "skipped" \]; then' .github/workflows/ci.yml | grep -q 'aggregate'; then :; fi
agg_loop=$(awk '/name: Aggregate test gate/{f=1} f{print} /^          echo "✅ All aggregate gates passed"/{exit}' .github/workflows/ci.yml)
if echo "$agg_loop" | grep -q 'elif \[ "$result" = "success" \] || \[ "$result" = "skipped" \]; then'; then
  echo "  MASKED: aggregate result loop treats skipped as a pass"
  fail=1
else
  echo "  ok: aggregate result loop does not treat skipped as a pass"
fi
for j in binding-freshness actionlint build; do
  if echo "$agg_loop" | grep -qF "\"$j:"; then
    echo "  ok: $j in aggregate result loop"
  else
    echo "  MISSING: $j in aggregate result loop"
    fail=1
  fi
done
# needs line
needs_line=$(grep -n 'needs: \[lint, pytest, binding-freshness, actionlint, build\]' .github/workflows/ci.yml || true)
if [[ -n "$needs_line" ]]; then
  echo "  ok: three jobs in aggregate needs:"
else
  echo "  MISSING: binding-freshness/actionlint/build in aggregate needs:"
  fail=1
fi

# Both aggregators must fail closed. `ci / lint` (job id lint) and
# `ci / aggregate` (job id test) each aggregate a set of jobs; in both, a
# skipped job is a pass only when that job is named in that aggregator's own
# allow-list. The `ci / lint` aggregator still carried the mask that PR 129
# removed from `ci / aggregate`, and `detect` reached no aggregator at all, so
# a failed detect could never turn the lint gate red.
echo "== both aggregators are fail-closed =="
for gate in lint aggregate; do
  if [[ "$gate" == "lint" ]]; then
    gate_start="Aggregate lint gate"
    gate_end="All lint checks passed"
  else
    gate_start="Aggregate test gate"
    gate_end="All aggregate gates passed"
  fi
  block=$(awk -v s="$gate_start" -v e="$gate_end" '
    index($0, s) { f = 1 }
    f { print }
    f && index($0, e) { exit }
  ' .github/workflows/ci.yml)
  if [[ -z "$block" ]]; then
    echo "  MISSING: could not locate the $gate aggregate block"
    fail=1
    continue
  fi
  # A success branch that also accepts "skipped" is the mask this check
  # exists to stop, in either order.
  masked=$(printf '%s\n' "$block" | grep -cF \
    -e '[ "$result" = "success" ] || [ "$result" = "skipped" ]' \
    -e '[ "$result" = "skipped" ] || [ "$result" = "success" ]' || true)
  if [[ "$masked" != "0" ]]; then
    echo "  MASKED: $gate result loop treats skipped as a pass"
    fail=1
  else
    echo "  ok: $gate result loop does not treat skipped as a pass"
  fi
  # Each aggregator must name its allow-list explicitly, so that a job is
  # skipped only by a decision that is written down.
  allow_line=$(printf '%s\n' "$block" | grep '^[[:space:]]*allow_skip=' || true)
  if [[ -n "$allow_line" ]]; then
    echo "  ok: $gate names its allow-list: $allow_line"
  else
    echo "  MISSING: $gate does not name an allow-list (allow_skip=...)"
    fail=1
  fi
  if [[ "$gate" == "lint" ]]; then
    # Every job the lint aggregator needs must also appear in its result
    # loop, otherwise a failure in that job can never turn the gate red.
    for j in zig-fmt detect actionlint rust cargo-deny python go typescript security dep-review pytest; do
      hit=$(printf '%s\n' "$block" | grep -cF "\"$j:" || true)
      if [[ "$hit" != "0" ]]; then
        echo "  ok: $j in lint result loop"
      else
        echo "  MISSING: $j in lint result loop"
        fail=1
      fi
    done
    # security must NOT be allow-listed: detect always exports has_security=true,
    # so a skipped security scan is an anomaly, not an opt-out.
    case "$allow_line" in
      *security*)
        echo "  MASKED: security is allow-listed in the lint aggregate"
        fail=1
        ;;
      *)
        echo "  ok: security is not allow-listed in the lint aggregate"
        ;;
    esac
  fi
done

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
