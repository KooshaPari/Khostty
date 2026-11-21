# Branch salvage matrix — measured 2026-11-21

Repo `KooshaPari/Khostty` @ `main` `b8510f28c`. 21 remote branches besides `main`; **0 open PRs**.
Every row below was measured, not inferred. `ahead` = `git rev-list --count origin/main..origin/<b>`.

| branch | ahead | PR | PR state | content already on main | disposition |
|---|---|---|---|---|---|
| feat/zig-coverage | 5 | #136 | MERGED `f73964f65` | `tools/coverage.py` present; `coverage` step `build.zig:143` | delete (absorbed) |
| fix/aggregate-fail-closed | 3 | #129 | MERGED | yes (squash) | delete (absorbed) |
| fix/fork-disc-guard | 1 | #128 | MERGED | yes (squash) | delete (absorbed) |
| fix/install-zig-macos | 2 | #137 | MERGED | yes (squash) | delete (absorbed) |
| ci/118-fork-discipline-strict | 2 | #120 | CLOSED 11-11 | `7e5b29232` strict-gate subject on main | delete (superseded) |
| ci/119-concurrency-group | 1 | #121 | CLOSED 11-11 | `74cc09d2b` concurrency-key subject on main | delete (superseded) |
| ci/deinert-fork-gates | 3 | #125 | CLOSED 11-12 | `6e979333c` `9c285e5c3` `2586ae72c` inert-gate remediation | delete (superseded) |
| ci/zig-test-gate-98 | 2 | #132 | CLOSED 11-12 | `zig-test` job present in `zig-fork-tests.yml:235` | delete (superseded) |
| ci/zig-push-unfiltered | 1 | #134 | CLOSED 11-12 | `paths:` filter absent under `push:` (`zig-fork-tests.yml:58`) | delete (superseded) |
| fix/ci-rust-test-gate | 2 | #133 | CLOSED 11-12 | `example-tests` job `zig-fork-tests.yml:353` | delete (superseded) |
| fix/126-ruff-clean | 1 | #127 | CLOSED 11-12 | `ci.yml:395-403` measured-ruff rewrite; `bf9b4e017` | delete (superseded) |
| recover/ci-98-red-proof | 1 | none | — | self-labelled "deliberate-red probe - do not merge" | delete (probe) |
| recover/pr-101 | 1 | none | — | "probe: 94 annotation rule" | delete (probe) |
| recover/pr-104 | 1 | none | — | #104 landed earlier; `chore(94)` annotation | verify-then-delete |
| recover/pr-105 | 2 | none | — | #105 landed earlier; audit table additions | verify-then-delete |
| recover/pr-107 | 1 | none | — | #107 landed earlier; prettier fix | verify-then-delete |
| recover/pr-30 | 1 | none | — | "build/windows: add desk installer gate" — **not** on main | KEEP (unique) |
| recover/pr-77 | 6 | none | — | "fix(ipc): bound the split poll by wall clock" — not on main | KEEP (unique, 2 files) |
| recover/pr-84 | 10 | none | — | storm-diagnostic CI work — not on main | KEEP (unique, 5 files) |
| sess-triage | 1 | none | — | docs-only triage STOP report | KEEP or absorb to docs |
| ci-unsched | 1 | none | — | unschedulable-Infisical fix — not on main | KEEP (unique, 2 files) |

## Correction to an earlier method

An earlier pass classified branches with a whitespace-stripped keyline grep and reported
`feat/zig-coverage` as `keylines 0/3` = absent. That test was invalid: stripping spaces makes
exact lines unmatchable, so it produced a **false negative** — PR #136 was MERGED on 2026-11-17
and `tools/coverage.py` + the `coverage` step are on main. The authoritative tests used here are
PR state by head branch (`gh api .../pulls/N`), remote presence of the named file/step, and
workflow-file inspection. A keyline grep is not evidence of absence.

## Deletion commands (NOT executed — awaiting authorisation)

```bash
# 11 absorbed/superseded/probe branches, SHAs above are recoverable from this document
git push origin --delete feat/zig-coverage fix/aggregate-fail-closed fix/fork-disc-guard \
  fix/install-zig-macos ci/118-fork-discipline-strict ci/119-concurrency-group \
  ci/deinert-fork-gates ci/zig-test-gate-98 ci/zig-push-unfiltered fix/ci-rust-test-gate \
  fix/126-ruff-clean recover/ci-98-red-proof recover/pr-101
```
