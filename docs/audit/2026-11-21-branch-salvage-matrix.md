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
| recover/pr-30 | 1 | none | — | adds **NEW** `.github/workflows/windows-desk.yml` (absent from main) | KEEP (unique) |
| recover/pr-77 | 6 | none | — | `src/App.zig`, `src/apprt/ipc/app_host.zig` DIFFER; 6 commits | UNVERIFIED-UNIQUE (main may be newer) |
| recover/pr-84 | 10 | none | — | adds **NEW** `nix/ipc-storm-diagnose.sh`; 4 other files DIFFER | KEEP (unique) |
| sess-triage | 1 | none | — | 2 docs DIFFER from main | UNVERIFIED-UNIQUE (docs only) |
| ci-unsched | 1 | none | — | `infisical.yml`, `milestone.yml` DIFFER from main | UNVERIFIED-UNIQUE (main may carry the fix) |

## Correction to an earlier method

An earlier pass classified branches with a whitespace-stripped keyline grep and reported
`feat/zig-coverage` as `keylines 0/3` = absent. That test was invalid: stripping spaces makes
exact lines unmatchable, so it produced a **false negative** — PR #136 was MERGED on 2026-11-17
and `tools/coverage.py` + the `coverage` step are on main. The authoritative tests used here are
PR state by head branch (`gh api .../pulls/N`), remote presence of the named file/step, and
workflow-file inspection. A keyline grep is not evidence of absence.

## Why `DIFFERS` is not `missing`

A file that exists on main but differs from the branch can mean main moved ahead and already
absorbed the branch's change. Only a file **absent from main** proves the branch adds content.
Exactly three branches add an absent file: `recover/pr-30`, `recover/pr-84` (both KEEP), and
none of the eleven deletion candidates. The four `UNVERIFIED-UNIQUE` rows need a per-file diff
before any verdict.

## Deletion commands (NOT executed — awaiting authorisation)

```bash
# 11 absorbed/superseded/probe branches, SHAs above are recoverable from this document
git push origin --delete feat/zig-coverage fix/aggregate-fail-closed fix/fork-disc-guard \
  fix/install-zig-macos ci/118-fork-discipline-strict ci/119-concurrency-group \
  ci/deinert-fork-gates ci/zig-test-gate-98 ci/zig-push-unfiltered fix/ci-rust-test-gate \
  fix/126-ruff-clean recover/ci-98-red-proof recover/pr-101
```

---

## Triage outcome — 2026-11-21 (per-file diff pass)

This section is the per-file verification the "verify-then-delete" rows above deferred.
Main measured at `8360da710e9b1d164b376abfa32145ad87e71746` (unchanged by this pass).

Method, applied once per branch: `git rev-list --count origin/main..origin/<b>`,
`git log --oneline origin/main..origin/<b>`, `git diff --stat origin/main...origin/<b>`,
`git diff --name-status origin/main origin/<b>` (direction main-to-branch, so `A` means
**main lacks that path**), `git cherry origin/main origin/<b>` (`-` = a patch-equivalent
commit is already upstream), and line-subset containment for documentation files.
`DIFFERS` is still not `missing`: a path listed as `M` exists on main and was compared by content.

| branch | ahead | classification | unique paths / measured evidence | action |
|---|---|---|---|---|
| recover/pr-101 | 1 | PROBE (trivial) | `650395a0a` "probe: 94 annotation rule" adds 2 comment lines to `src/Command.zig`; no path absent from main; recorded as a probe above | **deleted** |
| recover/pr-104 | 1 | FULLY-MERGED | `git cherry` = `-` for `5c7455650`; main's later revision keeps the FORK annotation this branch removes; residue is a `docs/FORK.md` table reflow | **deleted** |
| recover/pr-105 | 2 | ALREADY-SUPERSEDED | `bad114c0c` landed on main as `148f74095` "(#105)"; all three lane-B paths exist on main and were edited further by #109/#122/#123; no path absent from main | **deleted** |
| recover/pr-107 | 1 | FULLY-MERGED | `git cherry` = `-` for `f49af906d`; main's `a8553b32d` carries the same subject "(#107)"; only `README.md` differs, by prose reflow | **deleted** |
| recover/pr-30 | 1 | UNIQUE-WORK | adds `.github/workflows/windows-desk.yml`, `src/apprt/windows/renderer.zig`, `src/apprt/windows/win32api.zig`, all **ABSENT** from main; 343 insertions / 8 files | **kept** |
| recover/pr-77 | 6 | UNIQUE-WORK | `src/App.zig` (+269) and `src/apprt/ipc/app_host.zig` split/poll work; `zz_race_probe.zig` absent from main; 353 insertions | **kept** |
| recover/pr-84 | 10 | UNIQUE-WORK | superset of `recover/pr-77` (all six of its commits) plus `nix/ipc-storm-diagnose.sh` (ABSENT from main) and `src/ipc_probe.zig`; 571 insertions | **kept** |
| ci-unsched | 1 | SUPERSEDED, NOT PROVABLY CONTAINED | main's `infisical.yml` already carries `runs-on: ubuntu-latest`, `timeout-minutes: 5` and the `INFISICAL_SYNC` gate, and `milestone.yml` already has the open-milestone pre-check; the branch instead removes the triggers and also carries `zz_race_probe.zig` (ABSENT from main) | **kept — human decision** |
| sess-triage | 1 | SUPERSEDED, NOT PROVABLY CONTAINED | both documents exist on main via `12c581faa` "(#90)"; the 28/12 non-identical lines are markdown separator rows plus one reflowed sentence; the branch tree also carries `src/apprt/windows/renderer.zig` and `win32api.zig`, ABSENT from main | **kept — human decision** |

### Deleted this pass

```text
git push origin --delete recover/pr-101 recover/pr-104 recover/pr-105 recover/pr-107
```

All four are recoverable from the SHAs in this document (`650395a0a`, `5c7455650`,
`bad114c0c`/`16028406c`, `f49af906d`) and from GitHub's ref log.

### Branch still holding unique work that a human must decide on

- `recover/pr-30` — Windows desk installer gate and the two Win32 source files main lacks.
- `recover/pr-84` — superset of `recover/pr-77`; storm diagnostic, `ipc_probe.zig`, `zz_race_probe.zig`. If the IPC split work is wanted, `recover/pr-84` is the branch to take; `recover/pr-77` is then redundant but was not deleted here because its content is in another branch, not in main.
- `ci-unsched` — the CI outcome is already on main in a different form; only `zz_race_probe.zig` is absent from main.
- `sess-triage` — reports are on main in a later revision; the two Win32 source files are absent from main but belong to the windows-desk lane, not to this docs commit.

### Out of scope, untouched

- `recover/ci-98-red-proof` — still on the remote but **not** in the authorised list for this pass; left alone.
- Local `pr137` and upstream `pluie/jj-vspwwsuolrrr` — local/upstream only, never pushed to origin by this pass.
