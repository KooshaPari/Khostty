# Inert CI gate audit — 2026-11-12

**Provenance.** This report was produced by a delegated subagent (route
`minimax-direct:MiniMax-M3.1-Flash`) working read-only in this checkout at `8029918c8`, then
spot-checked by the orchestrator. It is committed because it is the evidence behind PR #125, not
because every line was independently re-measured. The findings below are the audit as written,
unedited apart from this header.

**Independently re-verified by the orchestrator** (command run, result observed):

| claim                                         | check                                                      | result                                                                                                  |
| --------------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `cargo fmt --check` passes in `khostty-vt`    | `cargo fmt --all -- --check`                               | exit 0                                                                                                  |
| `ruff check .` is red                         | `ruff 0.16.7`, `ruff check .`                              | exit 1, 131 errors (63 auto-fixable)                                                                    |
| `ruff format --check .` is red                | same                                                       | exit 1, 13 files would be reformatted                                                                   |
| `wasm/package.json` declares no `lint` script | parsed its `scripts` block                                 | `build, test, test:header, typecheck, check, exports` — **this resolves the audit's own open question** |
| `wasm` tests pass                             | `node --test test/*.test.mjs`                              | 54 pass, 0 fail                                                                                         |
| `wasm` typecheck passes                       | `npm run typecheck`                                        | exit 0                                                                                                  |
| gitleaks genuinely passes                     | step-level conclusions, run `43155030163`                  | `gitleaks` step `success`                                                                               |
| dependency-review genuinely passes            | step-level conclusions, same run                           | step `success`                                                                                          |
| `ci.yml` is fork-authored, not upstream       | `git show upstream/main:.github/workflows/ci.yml \| wc -l` | 0 lines — upstream has no `ci.yml`                                                                      |
| no `deny.toml` anywhere in the tree           | `git ls-files \| grep -i deny`                             | empty                                                                                                   |

**Still unverified**, as the audit itself states: whether a `namespace-profile-ghostty-*` runner
exists beyond repo scope, and the exact commit that changed `test.yml`'s `on:` block.

---

# Inert CI Gates Audit — KooshaPari/Khostty

**Repo:** `/Users/kooshapari/CodeProjects/Phenotype/repos/khostty` (fork of `ghostty-org/ghostty`)
**HEAD audited:** `8029918c845bdaa9cbb4db4eaa5b76348c60b9ac` (2026-11-11 21:16:26 -0800)
**Remote under audit:** `origin` = `https://github.com/KooshaPari/Khostty.git` (upstream remote present but never targeted by any command in this audit)
**Date:** 2026-11-11 (session 2026-11-12T05:29Z)
**Mode:** read-only. Nothing was modified, committed, or pushed.

**Question:** which CI gates either (a) can never fail, or (b) never run at all on this fork, and therefore report a false sense of safety?

**Scope read:** all 27 files in `.github/workflows/` (verified by `ls .github/workflows/`). Every workflow was read; only the ones with an inert gate are reported below.

---

## Summary table

| workflow                | line | pattern                                                           | can it fail?                             | does it run?                  |
| ----------------------- | ---- | ----------------------------------------------------------------- | ---------------------------------------- | ----------------------------- |
| ci.yml                  | 507  | aggregate gate treats `success`/`skipped` as pass (cross-cutting) | it fails only if a _non_-inert job fails | yes                           |
| ci.yml                  | 51   | `if: ${{ vars.ENABLE_MACOS_BUILD == 'true' }}` (b)                | n/a — never runs                         | **no**                        |
| ci.yml                  | 163  | step `\|\| echo "::warning::… (advisory)"` (a)                    | **no**                                   | yes                           |
| ci.yml                  | 167  | step `\|\| echo "::warning::… (advisory)"` (a)                    | **no**                                   | yes                           |
| ci.yml                  | 291  | job-level `continue-on-error: true` (a) + no `deny.toml` (b)      | **no**                                   | **no** (skipped)              |
| ci.yml                  | 305  | job-level `continue-on-error: true` (a)                           | **no**                                   | yes                           |
| ci.yml                  | 448  | job-level `continue-on-error: true` (a)                           | **no**                                   | yes                           |
| ci.yml                  | 480  | job-level `continue-on-error: true` (a)                           | **no**                                   | yes                           |
| ci.yml                  | 500  | job-level `continue-on-error: true` (a)                           | **no**                                   | yes (PRs only)                |
| sonar.yml               | 68   | job-level `continue-on-error: true` (a)                           | **no**                                   | yes (job runs, gate does not) |
| sonar.yml               | 102  | step `if: env.SONAR_TOKEN_PRESENT == 'true'`, secret absent (b)   | **no**                                   | **no**                        |
| infisical.yml           | 37   | `if: vars.INFISICAL_SYNC == 'true'` (b)                           | n/a — never runs                         | **no**                        |
| test.yml                | 24   | `on: workflow_dispatch: {}` only (b)                              | n/a                                      | **no** (auto triggers)        |
| test.yml                | 39   | `if: github.repository == 'ghostty-org/ghostty'` (b)              | n/a — never runs                         | **no**                        |
| test.yml                | 40   | `runs-on: namespace-profile-ghostty-*` (b)                        | n/a                                      | **no**                        |
| nix.yml                 | 35   | `if: github.repository == 'ghostty-org/ghostty'` (b)              | n/a — never runs                         | **no**                        |
| flatpak.yml             | 17   | `if: github.repository == 'ghostty-org/ghostty'` (b)              | n/a — never runs                         | **no**                        |
| update-colorschemes.yml | 9    | `if: github.repository == 'ghostty-org/ghostty'` (b)              | n/a — never runs                         | **no**                        |
| release-tag.yml         | 32   | `if: github.repository == 'ghostty-org/ghostty'` (b)              | n/a — never runs                         | **no**                        |
| release-tip.yml         | 23   | `github.repository_owner == 'ghostty-org'` guard (b)              | n/a — never runs                         | **no**                        |
| publish-tag.yml         | 18   | `runs-on: namespace-profile-ghostty-sm` (b)                       | n/a                                      | **no**                        |
| vouch-check-pr.yml      | 24   | `runs-on: namespace-profile-ghostty-xsm` (b)                      | n/a                                      | **no**                        |

**22 findings.** No fixes are recommended — this document is an audit only.

### Repo-wide facts the findings depend on

| fact                                             | value                       | how measured                                                                                           |
| ------------------------------------------------ | --------------------------- | ------------------------------------------------------------------------------------------------------ |
| Repository **variables**                         | **zero**                    | `gh variable list --repo KooshaPari/Khostty` → empty output, exit 0                                    |
| Repository **secrets**                           | **zero**                    | `gh secret list --repo KooshaPari/Khostty` → empty output, exit 0                                      |
| **Self-hosted runners** registered for this repo | **0**                       | `gh api repos/KooshaPari/Khostty/actions/runners --jq '.total_count'` → `0`                            |
| Required status checks on `main`                 | `["ci / lint","ci / test"]` | `gh api repos/KooshaPari/Khostty/branches/main/protection --jq '.required_status_checks.contexts'`     |
| `deny.toml` anywhere in tree                     | **absent**                  | `find . -name deny.toml -not -path '*/node_modules/*'` → empty; `git ls-files \| grep -i deny` → empty |
| `wasm/package.json`                              | present                     | `find . -maxdepth 3 -name package.json` → `./wasm/package.json`                                        |
| `khostty-python/pyproject.toml`                  | present                     | filesystem check                                                                                       |
| `orgs/KooshaPari/actions/runners`                | HTTP 404                    | `gh api orgs/KooshaPari/actions/runners` → `{"message":"Not Found"}`                                   |
| `users/KooshaPari/actions/runners`               | HTTP 404                    | `gh api users/KooshaPari/actions/runners` → `{"message":"Not Found"}`                                  |

The org/user runner endpoints 404, so a runner attached at some scope other than this repository cannot be **excluded** from the evidence. What _is_ established: the repository has **zero** self-hosted runners registered, and every job pinned to a `namespace-profile-*` label has been observed to never start (see per-finding run evidence). The absence of any other runner scope is **UNVERIFIED**.

---

## F1 — `ci.yml:507` — the only two required status checks read green regardless of the inert gates

**Workflow:** `.github/workflows/ci.yml`
**Line:** 507 (`lint:` job), aggregate step "Aggregate lint gate" (the `for pair in …` loop immediately below)
**Pattern:** a gate step whose failure is never surfaced (cross-cutting mechanism)

```yaml
lint:
  name: ci / lint
  if: always()
  needs:
    [
      zig-fmt,
      detect,
      rust,
      cargo-deny,
      python,
      go,
      typescript,
      security,
      dep-review,
      pytest,
    ]
  runs-on: ubuntu-latest
  steps:
    - name: Aggregate lint gate
      run: |
        failed=0
        for pair in \
          "zig-fmt:${{ needs.zig-fmt.result }}" \
          …
          "cargo-deny:${{ needs.cargo-deny.result }}" \
          "python:${{ needs.python.result }}" \
          …
        ; do
          name="${pair%%:*}"
          result="${pair#*:}"
          if [ "$result" = "failure" ] || [ "$result" = "cancelled" ]; then
            echo "  ✗ $name: $result"
            failed=$((failed + 1))
          elif [ "$result" = "success" ] || [ "$result" = "skipped" ]; then
            echo "  ✓ $name: $result"
          else
            echo "  ? $name: $result"
            failed=$((failed + 1))
          fi
        done
        if [ "$failed" -gt 0 ]; then
          …
          exit 1
        fi
```

**Why inert:** this aggregate job _is_ one of the two required status checks on `main` (the other is `ci / test` at `ci.yml:559`, which aggregates `lint` + `pytest`). It decides pass/fail purely from `needs.<job>.result`. GitHub reports a job whose `continue-on-error: true` fired as **`success`**, and a job skipped by an always-false `if:` as **`skipped`**. The loop counts both `success` and `skipped` as `✓` and only fails on `failure`/`cancelled`. Therefore the five jobs listed below (F5–F9) — plus the macOS build (F2) — cannot turn `ci / lint` red, and `ci / lint` and `ci / test` stay green while they are broken. This is the mechanism that converts the individual inert gates into a **false sense of safety**: the required check is green, so the failure is invisible at the merge gate.

Note the `build` (macOS) job at `ci.yml:43` is not even in this `needs:` list, so it can never influence the aggregate at all.

**Evidence:**

- `gh api repos/KooshaPari/Khostty/branches/main/protection --jq '.required_status_checks.contexts'` → `["ci / lint","ci / test"]` — these are the _only_ required checks.
- `ci.yml` read in full (lines 1–620); the aggregate loop quoted verbatim above.
- `gh run list --workflow=ci.yml --repo KooshaPari/Khostty --limit 1` → run `43160284305`, status `queued` (2026-11-12T05:16:30Z) — the workflow does execute; its verdict is the question, not its execution.
- The `continue-on-error` → `success` and `skipped` → pass semantics are the documented GitHub Actions job-result behaviour; each affected job is additionally evidenced at F5–F9.

---

## F2 — `ci.yml:51` — the macOS build job never runs

**Workflow:** `.github/workflows/ci.yml`
**Line:** 51
**Pattern:** (b) job-level `if:` that is always false on this fork

```yaml
build:
  name: Build (macOS)
  # Billed macOS runners are disabled by repository policy, so this job is
  # opt-in rather than unconditionally dead. `vars` IS a permitted context in
  # a job-level `if`; set repository variable ENABLE_MACOS_BUILD=true to run
  # it.
  if: ${{ vars.ENABLE_MACOS_BUILD == 'true' }}
  runs-on: macos-latest
```

**Why inert:** `vars.ENABLE_MACOS_BUILD` resolves to the empty string because the repository has **no variables at all**. `'' == 'true'` is false, so the job is skipped on every run. The comment describes an intended opt-in that has never been exercised. This is the macOS build gate for a macOS-first terminal emulator, and it is additionally absent from the `ci / lint` aggregate's `needs:` list (F1), so there is no path by which a macOS build failure could ever surface.

**Evidence:**

- `gh variable list --repo KooshaPari/Khostty` → empty output, exit 0 → zero variables.
- `ci.yml:43-53` read verbatim.
- `ci.yml:507-521` — `build` is not in the `lint` job's `needs:` list.

---

## F3 — `ci.yml:163` — `cargo fmt --check` can never fail

**Workflow:** `.github/workflows/ci.yml`
**Line:** 163
**Pattern:** (a) a gate step whose failure is never surfaced

```yaml
- name: cargo fmt --check
  working-directory: khostty-vt
  run: |
    cargo fmt --all -- --check 2>&1 || echo "::warning::cargo fmt issues (advisory)"
```

**Why inert:** the `||` short-circuits any non-zero exit from `cargo fmt --check` and replaces it with `echo`, whose exit status is 0. The step therefore always succeeds regardless of formatting violations, and the enclosing `rust` job is not `continue-on-error` but has nothing to fail on for this step. The job reports `success`, so F1's aggregate prints `✓ rust: success`.

**Evidence:** `ci.yml:161-163` read verbatim; `grep -n "warning::\|cargo fmt --all\|cargo clippy" ci.yml` → `163: cargo fmt --all -- --check 2>&1 || echo "::warning::cargo fmt issues (advisory)"`. The `rust` job header at `ci.yml:146` has no job-level `continue-on-error` (the only `continue-on-error` lines in `ci.yml` are 291, 305, 448, 480, 500), so the inertness is entirely the `|| echo`.

---

## F4 — `ci.yml:167` — `cargo clippy -D warnings` can never fail

**Workflow:** `.github/workflows/ci.yml`
**Line:** 167
**Pattern:** (a) a gate step whose failure is never surfaced

```yaml
- name: cargo clippy
  working-directory: khostty-vt
  run: |
    cargo clippy --all-targets -- -D warnings 2>&1 || echo "::warning::clippy issues (advisory)"
```

**Why inert:** identical mechanism to F3. `-D warnings` promotes lints to errors and makes clippy exit non-zero, but `|| echo "::warning::…"` discards that exit status and the step exits 0. Clippy warnings — including the `clippy::needless_bool` class of lint — cannot fail this job, and therefore cannot fail `ci / lint`.

**Evidence:** `ci.yml:164-167` read verbatim; `grep -n` confirms line 167. The same `rust` job does contain genuinely blocking steps (`cargo test` at line 200, and the "assert the linked integration tests were collected" guard at line ~193 which does `exit 1`), which is why the `rust` job as a whole can still fail — this finding is scoped to the two advisory steps.

---

## F5 — `ci.yml:291` — `cargo-deny` advisory gate: cannot fail **and** never runs

**Workflow:** `.github/workflows/ci.yml`
**Line:** 291
**Pattern:** (a) job-level `continue-on-error: true` on a gating job, **and** (b) the job's `if:` is false on this fork

```yaml
cargo-deny:
  name: Cargo Deny (Advisories + Licenses)
  needs: detect
  if: needs.detect.outputs.has_deny == 'true'
  runs-on: ubuntu-latest
  continue-on-error: true
  steps:
    - uses: actions/checkout@v4
    - uses: dtolnay/rust-toolchain@stable
    - name: cargo-deny check
      uses: EmbarkStudios/cargo-deny-action@v1
      with:
        arguments: --all-features
```

**Why inert, twice over:**

- (a) `continue-on-error: true` at the job level means a failing `cargo-deny check` still reports `success`. The aggregate at F1 counts `success` as a pass.
- (b) The `if:` reads `needs.detect.outputs.has_deny`, which the `detect` job sets **only** if a `deny.toml` file is found in the tree (`ci.yml:103-109`: `if find . -name deny.toml … ; then echo "has_deny=true" …`). **No `deny.toml` exists anywhere in this repository**, so `has_deny` is never set, the expression is empty/false, and the job is **skipped** on every run.

A supply-chain advisory gate therefore provides no signal at all on this fork.

**Evidence:**

- `find . -name deny.toml -not -path '*/node_modules/*' -not -path './.git/*'` → empty output.
- `git ls-files | grep -i deny` → empty output (not merely untracked).
- `ci.yml:286-298` read verbatim; `ci.yml:100-110` read verbatim for the `has_deny` derivation.
- `grep -n "continue-on-error" ci.yml` → line 291.

---

## F6 — `ci.yml:305` — the Python lint job cannot fail

**Workflow:** `.github/workflows/ci.yml`
**Line:** 305 (job-level `continue-on-error`); the two gated steps at 314 and 316
**Pattern:** (a) job-level `continue-on-error: true` **plus** step-level `|| echo`

```yaml
python:
  name: Python
  needs: detect
  if: needs.detect.outputs.has_python == 'true'
  runs-on: ubuntu-latest
  continue-on-error: true
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-python@v5
      with:
        python-version: "3.11"
    - name: Install ruff
      run: pip install ruff
    - name: ruff check
      run: ruff check . 2>&1 || echo "::warning::ruff issues (advisory)"
    - name: ruff format --check
      run: ruff format --check . 2>&1 || echo "::warning::format issues (advisory)"
```

**Why inert:** two independent layers. Each step's `|| echo` turns a ruff failure into exit 0, and the job-level `continue-on-error: true` would neutralise the job even if a step did fail. The job reports `success` → F1 prints `✓ python: success`.

Scope note: this job is **lint only** — it runs ruff, not tests. The Python _test_ gate is the separate `pytest` job at `ci.yml:318`, which has no `continue-on-error` and is genuinely blocking. This finding is scoped to the ruff lint/format gate.

**Evidence:** `ci.yml:300-317` read verbatim; `grep -n "warning::" ci.yml` → lines 314 and 316 both end in `|| echo "::warning::… (advisory)"`. `ci.yml:318` (`pytest:`) confirmed to have no `continue-on-error` — the only `continue-on-error` lines in `ci.yml` are 291, 305, 448, 480, 500.

---

## F7 — `ci.yml:448` — the TypeScript/JS job cannot fail

**Workflow:** `.github/workflows/ci.yml`
**Line:** 448 (job-level `continue-on-error`); the gated steps at 467 and 472
**Pattern:** (a) job-level `continue-on-error: true` **plus** step-level `|| echo`

```yaml
  typescript:
    name: TS/JS
    needs: detect
    if: needs.detect.outputs.has_typescript == 'true'
    runs-on: ubuntu-latest
    continue-on-error: true
    defaults:
      run:
        working-directory: wasm
    steps:
      …
      - name: lint
        run: |
          if [ -f package.json ] && grep -q '"lint"' package.json; then
            npm run lint 2>&1 || echo "::warning::lint issues (advisory)"
          fi
      - name: test
        run: |
          if [ -f package.json ] && grep -q '"test"' package.json; then
            npm test 2>&1 || echo "::warning::test failures (advisory)"
          fi
```

**Why inert:** the job-level `continue-on-error: true` alone is sufficient — a failed `npm test` still reports `success`. Independently, each step additionally swallows the exit code with `|| echo`. A further degradation: each step is additionally gated on `package.json` declaring the corresponding script, so a missing `"lint"`/`"test"` key in `wasm/package.json` makes the step a no-op rather than a pass. (Whether `wasm/package.json` declares those two scripts was **not** verified in this audit; the `|| echo` defect stands regardless.)

**Evidence:** `ci.yml:443-474` read verbatim; `grep -n "warning::" ci.yml` → 467 and 472. `wasm/package.json` confirmed present (so the job does run — `has_typescript=true` via `ci.yml` detect logic on `find . -name package.json`).

---

## F8 — `ci.yml:480` — the secret-scanning (gitleaks) gate cannot fail

**Workflow:** `.github/workflows/ci.yml`
**Line:** 480
**Pattern:** (a) job-level `continue-on-error: true` on a gating job

```yaml
security:
  name: Security Scan
  needs: detect
  if: needs.detect.outputs.has_security == 'true'
  runs-on: ubuntu-latest
  continue-on-error: true
  steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0
    - name: gitleaks
      uses: gitleaks/gitleaks-action@v2
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Why inert:** `continue-on-error: true` at the job level means a gitleaks detection is reported as `success`. The job therefore cannot fail, and F1's aggregate counts it as a pass. The `has_security` output is unconditionally `true` (`ci.yml:137`: `echo "has_security=true"`), so the job does run on every CI run — it simply cannot go red. A committed credential would not block a merge.

**Evidence:** `ci.yml:475-495` read verbatim; `grep -n "continue-on-error" ci.yml` → 480. `ci.yml:137` confirms `has_security=true` is unconditional, so the job is not skipped.

---

## F9 — `ci.yml:500` — the dependency-review gate cannot fail

**Workflow:** `.github/workflows/ci.yml`
**Line:** 500
**Pattern:** (a) job-level `continue-on-error: true` on a gating job

```yaml
dep-review:
  name: Dependency Review
  if: github.event_name == 'pull_request'
  runs-on: ubuntu-latest
  continue-on-error: true
  steps:
    - uses: actions/checkout@v4
    - uses: actions/dependency-review-action@v4
      with:
        fail-on-severity: low
```

**Why inert:** the action is configured with `fail-on-severity: low` — i.e. it is explicitly meant to fail on any low-severity or higher advisory — but the job-level `continue-on-error: true` discards that failure. The job reports `success` on a PR and F1 counts it as a pass. (On non-PR events the job is skipped, which F1 also counts as a pass, so this gate is inert on push events as well.)

**Evidence:** `ci.yml:496-506` read verbatim; `grep -n "continue-on-error" ci.yml` → 500; `ci.yml:498` shows the `github.event_name == 'pull_request'` restriction.

---

## F10 — `sonar.yml:68` — the SonarCloud job can never fail

**Workflow:** `.github/workflows/sonar.yml`
**Line:** 68 (also 110)
**Pattern:** (a) job-level `continue-on-error: true` on the workflow's only job

```yaml
jobs:
  sonarcloud:
    name: Scan (advisory, never blocks)
    runs-on: ubuntu-latest
    timeout-minutes: 15
    continue-on-error: true
```

and, at line 110, inside the scan step:

```yaml
args: >
  -Dsonar.qualitygate.breakBuildOnQualityGateFailure=false
  -Dsonar.qualitygate.wait=false
```

**Why inert:** two layers. The job-level `continue-on-error: true` means the job reports `success` whatever happens. Even without it, `sonar.qualitygate.breakBuildOnQualityGateFailure=false` instructs the scanner CLI to exit 0 on a quality-gate failure. The file's own header states this at lines 18-22 ("`continue-on-error: true` means the workflow job NEVER fails the PR"). SonarCloud therefore produces a dashboard signal only; it is not a gate and is not represented as one in the required-check list.

**Evidence:** `sonar.yml` read in full with `cat -n`; lines 18-22 and 68 and 109-115 quoted verbatim. `gh api .../branches/main/protection --jq '.required_status_checks.contexts'` → `["ci / lint","ci / test"]` — SonarCloud is not a required check, consistent with the design.

---

## F11 — `sonar.yml:102` — the SonarCloud scan step never runs (the secret does not exist)

**Workflow:** `.github/workflows/sonar.yml`
**Line:** 102 (derived from line 85)
**Pattern:** (b) a gate step whose condition is always false on this fork

```yaml
    env:
      SONAR_TOKEN_PRESENT: ${{ secrets.SONAR_TOKEN != '' }}      # line 85
    steps:
      …
      - name: SonarCloud Scan
        if: ${{ env.SONAR_TOKEN_PRESENT == 'true' }}               # line 102
        uses: sonarsource/sonarqube-scan-action@…
```

**Why inert:** the repository has **zero secrets**, so `secrets.SONAR_TOKEN` evaluates to the empty string and `'' != ''` is `false` — `SONAR_TOKEN_PRESENT` is `'false'`, the step-level `if:` is false, and the scan step is **skipped on every run**. The job still runs (checkout, then an artifact upload of a file that was never produced, since `if-no-files-found: ignore`). The workflow's entire stated purpose — scanning the code — therefore never executes on this fork. The file's own comment at lines 69-83 records that two previous guards for this same step were also always-false; this is the third variant, still inert.

**Evidence:**

- `gh secret list --repo KooshaPari/Khostty` → empty output, exit 0 → zero secrets, so `SONAR_TOKEN` is unset.
- `sonar.yml` read in full; lines 84-85 and 96-103 quoted verbatim.
- `gh run list --workflow=sonar.yml --repo KooshaPari/Khostty --limit 1` → run `43160284257`, status `queued` (2026-11-12T05:16:30Z) — the workflow does trigger; it is the scan step that is skipped.

---

## F12 — `infisical.yml:37` — the Infisical secret-sync job never runs

**Workflow:** `.github/workflows/infisical.yml`
**Line:** 37
**Pattern:** (b) job-level `if:` referencing a `vars.` value that does not exist

```yaml
  sync-secrets:
    …
    if: vars.INFISICAL_SYNC == 'true'
    runs-on: ubuntu-latest
```

**Why inert:** the repository has **zero variables**, so `vars.INFISICAL_SYNC` is the empty string and `'' == 'true'` is false. The job — the entire body of this workflow — is skipped on every trigger. The workflow file triggers on `push` to `main`/`master`, `pull_request`, `workflow_dispatch` and `workflow_call`, so it appears in the Actions list and resolves as a run, but it performs no work.

**Evidence:**

- `gh variable list --repo KooshaPari/Khostty` → empty output, exit 0.
- `infisical.yml:30-40` read verbatim.
- `gh run list --workflow=infisical.yml --repo KooshaPari/Khostty --limit 1` → run `43155030180`, conclusion **`skipped`** (2026-11-12T04:28:29Z) — direct confirmation from run history that the job does not execute.

---

## F13 — `test.yml:24` — the entire upstream test suite is manual-dispatch-only

**Workflow:** `.github/workflows/test.yml`
**Line:** 24
**Pattern:** (b) the workflow never runs on automatic triggers

```yaml
on:
  workflow_dispatch: {}
```

**Why inert:** the only trigger is `workflow_dispatch`. No `push`, no `pull_request`, no `schedule`. Consequently a push or a PR to `main` triggers **no** upstream test job at all. This confirms and extends the known context: the belief that `test.yml` "is unable to run on this fork" is **true**, and there are two further independent reasons (F14, F15) beyond the trigger restriction.

Evidence that the trigger restriction is recent, and therefore that pre-2026-11-10 runs are not evidence of a working workflow: the five most recent runs of `test.yml` on this fork were all `push` events (2026-11-10), i.e. they predate the current `on:` block. The workflow's own header comment (lines 1-22) documents the change: "FORK: DISABLED for automatic triggers. Manual dispatch only."

**Evidence:**

- `test.yml:24-25` read verbatim via `sed -n '20,32p' test.yml | nl -ba -v20`.
- `gh run list --workflow=test.yml --repo KooshaPari/Khostty --limit 5` → all five runs are `push` events dated 2026-11-10T08:24–08:26Z, all `completed / cancelled`.

---

## F14 — `test.yml:39` — the `skip` job is pinned to the upstream repository

**Workflow:** `.github/workflows/test.yml`
**Line:** 39
**Pattern:** (b) job-level `if: github.repository == 'ghostty-org/ghostty'`

```yaml
skip:
  if: github.repository == 'ghostty-org/ghostty'
  runs-on: namespace-profile-ghostty-xsm
  outputs:
    skip: ${{ steps.determine.outputs.skip }}
    actions_pins: …
    blueprints: …
    macos: …
    nix: …
    shell: …
    zig: …
```

**Why inert:** on `KooshaPari/Khostty` the expression is always false, so the `skip` job never runs and never publishes its six outputs. Every downstream job that consults those outputs is gated on `needs.skip.outputs.skip != 'true'` — and the `skip` output is therefore empty, so `'' != 'true'` is true. That rescues the _output_ condition but not the _repository_ condition: 15 further job guards combine it with `github.repository == 'ghostty-org/ghostty'`, so those jobs are skipped as well.

**The upstream-repository guard sites in `test.yml`** — all always false on this fork.
`grep -n "github.repository == 'ghostty-org/ghostty'" test.yml` returns **17** matching lines: **16 live job-level `if:` expressions** plus **1 comment** at line 7 (which quotes the pattern in prose). The 16 live guard lines are:

> 39, 206, 1461, 1525, 1561, 1619, 1883, 1912, 1944, 1972, 2002, 2030, 2058, 2091, 2119, 2218

Line 39 is the `skip` job itself; the other 15 are downstream jobs that combine the repository guard with `needs.skip.outputs.<x> == 'true'` conditions.

Of the file's 52 jobs, the ones not carrying an explicit upstream guard (e.g. `build-bench` at 175, `list-examples` at 205, `build-linux` at 1003, `required` at 101) all depend on `skip` or are themselves pinned to `namespace-profile-*` runners (F15).

**Evidence:**

- `test.yml:38-45` read verbatim; the grep above yields the 16 live guard lines.
- `gh run view 42782592087 --repo KooshaPari/Khostty --json jobs` → every job's `conclusion` is `skipped` except `Required Checks: Test` which is `cancelled`. No job ever executed a step.

---

## F15 — `test.yml:40` — every job is pinned to a `namespace-profile-ghostty-*` runner this repo cannot schedule

**Workflow:** `.github/workflows/test.yml`
**Line:** 40 (and every other `runs-on:` in the file)
**Pattern:** (b) `runs-on:` a runner label this fork cannot schedule

```yaml
  skip:
    …
    runs-on: namespace-profile-ghostty-xsm
```

**Why inert:** the repository has **zero self-hosted runners registered** (`gh api repos/KooshaPari/Khostty/actions/runners --jq '.total_count'` → `0`). The `namespace-profile-ghostty-*` labels are Namespace Cloud self-hosted profile labels belonging to the upstream `ghostty-org/ghostty` setup; no runner carrying them is attached to this repository, so a job pinned to one is never scheduled. `test.yml` contains **52** such references across its 52 jobs, on labels `namespace-profile-ghostty-xsm`, `-sm`, `-md`, `-lg`, `-macos-tahoe` and `-windows`.

This is the mechanism behind the observed symptom recorded in the file's own header (lines 9-13): "20 consecutive runs of this workflow, 0 completed (6 pending, 14 queued). Every push and every PR adds another unschedulable run, which occupies the workflow queue and starves the checks that actually matter."

**Evidence:**

- `gh api repos/KooshaPari/Khostty/actions/runners --jq '.total_count'` → `0`.
- `gh api orgs/KooshaPari/actions/runners` → HTTP 404 `Not Found`; `gh api users/KooshaPari/actions/runners` → HTTP 404 `Not Found`. (Whether a runner exists at some other scope is **UNVERIFIED**; the repository-level API reports 0.)
- `gh run list --workflow=test.yml --repo KooshaPari/Khostty --limit 5` → all five runs `completed / cancelled` (2026-11-10T08:24:34Z … 08:26:01Z), none `success`.
- `gh run view 42782592087 --repo KooshaPari/Khostty --json jobs --jq '.jobs[] | "\(.name) | \(.status) | \(.conclusion) | \(.startedAt)"'` → all jobs `completed | skipped` with `startedAt` equal to the run start time; `Required Checks: Test | completed | cancelled`.
- `grep -n "runs-on:" test.yml` → 52 `namespace-profile-*` lines.

---

## F16 — `nix.yml:35` — the Nix cache-hash gate never runs

**Workflow:** `.github/workflows/nix.yml`
**Line:** 35 (and 11)
**Pattern:** (b) job-level `if: github.repository == 'ghostty-org/ghostty'`, plus an unschedulable runner

```yaml
  required:
    name: "Required Checks: Nix"
    runs-on: namespace-profile-ghostty-sm
    needs:
      - check-zig-cache-hash
    …
  check-zig-cache-hash:
    if: github.repository == 'ghostty-org/ghostty'
    runs-on: namespace-profile-ghostty-sm
```

**Why inert, twice over:** `check-zig-cache-hash` is skipped by the upstream-repository guard, and the `required` aggregate job depends on it (with no `if:`, so GitHub skips it too when its dependency is skipped) — the whole workflow therefore resolves to `skipped`. Independently, both jobs are pinned to `namespace-profile-ghostty-sm`, a label this repository cannot schedule (0 self-hosted runners, F15). The Nix gate that validates the Zig cache hash therefore never executes on this fork.

**Evidence:**

- `nix.yml` read in full (60 lines).
- `gh run list --workflow=nix.yml --repo KooshaPari/Khostty --limit 1` → run `43160284319`, conclusion **`skipped`** (2026-11-12T05:16:30Z).
- Runner count 0 as per F15.

---

## F17 — `flatpak.yml:17` — the Flatpak build never runs

**Workflow:** `.github/workflows/flatpak.yml`
**Line:** 17
**Pattern:** (b) job-level `if: github.repository == 'ghostty-org/ghostty'`, plus unschedulable runners

```yaml
build:
  if: github.repository == 'ghostty-org/ghostty'
  name: "Flatpak"
  container:
    image: ghcr.io/flathub-infra/flatpak-github-actions:gnome-47
    options: --privileged
  strategy:
    fail-fast: false
    matrix:
      variant:
        - arch: x86_64
          runner: namespace-profile-ghostty-md
        - arch: aarch64
          runner: namespace-profile-ghostty-md-arm64
  runs-on: ${{ matrix.variant.runner }}
```

**Why inert:** the sole job of the workflow is skipped by the upstream-repository guard. Its matrix runners (`namespace-profile-ghostty-md`, `namespace-profile-ghostty-md-arm64`) are also unschedulable from this repository. The workflow is additionally `workflow_dispatch`-only, so it requires a manual dispatch — which then skips.

**Evidence:**

- `flatpak.yml` read in full (50 lines).
- `gh run list --workflow=flatpak.yml --repo KooshaPari/Khostty --limit 1` → **no runs at all** (the API returned `null` for the first entry; the workflow has never been dispatched on this fork).

---

## F18 — `update-colorschemes.yml:9` — the weekly iTerm2 colorscheme updater never runs

**Workflow:** `.github/workflows/update-colorschemes.yml`
**Line:** 9
**Pattern:** (b) job-level `if: github.repository == 'ghostty-org/ghostty'`, plus an unschedulable runner

```yaml
jobs:
  update-iterm2-schemes:
    if: github.repository == 'ghostty-org/ghostty'
    runs-on: namespace-profile-ghostty-sm
    permissions:
      contents: write
      pull-requests: write
```

**Why inert:** the weekly cron (`0 0 * * 0`) fires and produces a visible workflow run, but the only job is skipped by the upstream-repository guard. Its `namespace-profile-ghostty-sm` runner is also unschedulable here. The result is a recurring **skipped** run every Sunday — which reads as "the automation ran and found nothing to do" rather than "the automation has never executed a single step". It also requires `secrets.CACHIX_AUTH_TOKEN`, `secrets.CF_R2_DEPS_*`, none of which exist on this repository (zero secrets), so even if the guard were lifted the job could not complete.

**Evidence:**

- `update-colorschemes.yml` read in full.
- `gh run list --workflow=update-colorschemes.yml --repo KooshaPari/Khostty --limit 1` → run `42447937225`, conclusion **`skipped`** (2026-11-08T04:43:16Z, i.e. a Sunday cron tick).
- `gh secret list --repo KooshaPari/Khostty` → empty output.

---

## F19 — `release-tag.yml:32` — the release-tag pipeline never runs

**Workflow:** `.github/workflows/release-tag.yml`
**Line:** 32
**Pattern:** (b) job-level `if: github.repository == 'ghostty-org/ghostty'`, plus unschedulable runners

```yaml
  setup:
    …
    if: github.repository == 'ghostty-org/ghostty'
    runs-on: namespace-profile-ghostty-sm
```

**Why inert:** the `setup` job is the root of this release pipeline; every other job depends on it. Skipping it skips the entire workflow. The runner label is also unschedulable. The workflow's triggers are `workflow_dispatch` and `push` on tags — a fork tag push would create a run that resolves to `skipped`, i.e. a tag that looks released but produced no artifacts.

**Evidence:**

- `release-tag.yml:1-45` read verbatim.
- `gh run list --workflow=release-tag.yml --repo KooshaPari/Khostty --limit 1` → **no runs at all** (API returned `null`).
- Runner count 0 as per F15.

---

## F20 — `release-tip.yml:23` — the release-from-main pipeline never runs

**Workflow:** `.github/workflows/release-tip.yml`
**Line:** 23
**Pattern:** (b) job-level `if:` containing `github.repository_owner == 'ghostty-org'`, plus unschedulable runners

```yaml
setup:
  if: |
    github.event_name == 'workflow_dispatch' ||
    github.repository_owner == 'ghostty-org' &&
    …
  runs-on: namespace-profile-ghostty-sm
```

**Why inert:** the automatic trigger for this workflow is `workflow_run` on `main`. On that trigger `github.event_name` is `workflow_run`, not `workflow_dispatch`, so the first clause is false; and `github.repository_owner` is `KooshaPari`, so the second clause is false. The `setup` job is skipped, and since all other jobs depend on it (`needs.setup.outputs.should_skip != 'true'`), the entire workflow resolves to `skipped`. The manual-dispatch path would evaluate the first clause as true, but every job in the file is pinned to a `namespace-profile-ghostty-*` runner, which this repository cannot schedule (0 self-hosted runners) — so the dispatch path is blocked by F15's mechanism instead.

**Evidence:**

- `release-tip.yml:22-30` read verbatim; `grep -n "ghostty-org" release-tip.yml` → the guard appears at lines 26, 206, 260, 334, 419, 548, 727, 761, 770, 804, 1001.
- `gh run list --workflow=release-tip.yml --repo KooshaPari/Khostty --limit 1` → run `39181813239`, conclusion **`skipped`** (2026-10-19T00:40:12Z).
- Runner count 0 as per F15.

---

## F21 — `publish-tag.yml:18` — the tag-publish pipeline cannot be scheduled

**Workflow:** `.github/workflows/publish-tag.yml`
**Line:** 18 (and 40)
**Pattern:** (b) `runs-on:` a runner label this fork cannot schedule

```yaml
  setup:
    runs-on: namespace-profile-ghostty-sm
    …
  upload:
    runs-on: namespace-profile-ghostty-sm
```

**Why inert:** both jobs of the workflow are pinned to `namespace-profile-ghostty-sm`. The repository has zero self-hosted runners, so neither job is ever scheduled. The workflow is `workflow_dispatch`-only, so no automatic trigger exists to mask the failure — but the workflow has in fact **never been dispatched** on this fork.

**Evidence:**

- `publish-tag.yml:1-45` read verbatim.
- `gh run list --workflow=publish-tag.yml --repo KooshaPari/Khostty --limit 1` → **no runs at all** (API returned `null`).
- Runner count 0 as per F15.

---

## F22 — `vouch-check-pr.yml:24` — the six Vouch workflows cannot be scheduled

**Workflow:** `.github/workflows/vouch-check-pr.yml` (and 5 siblings)
**Line:** 24 (and 28 in the four `vouch-manage*`/`vouch-sync*` files)
**Pattern:** (b) `runs-on:` a runner label this fork cannot schedule

```yaml
jobs:
  check:
    runs-on: namespace-profile-ghostty-xsm
```

Affected files and lines:

| file                             | job       | line |
| -------------------------------- | --------- | ---- |
| `vouch-check-pr.yml`             | `check:`  | 24   |
| `vouch-check-issue.yml`          | `check:`  | 24   |
| `vouch-manage-by-issue.yml`      | `manage:` | 28   |
| `vouch-manage-by-discussion.yml` | `manage:` | 28   |
| `vouch-sync-codeowners.yml`      | `sync:`   | 28   |

(The two `vouch-manage-*` workflows additionally share a `vouch-manage` concurrency group; this does not affect their inertness.)

**Why inert:** every job in all six workflows is pinned to `namespace-profile-ghostty-xsm`. With zero self-hosted runners registered on this repository, no such job is ever scheduled. The two workflows that have been dispatched show the signature directly: their runs conclude **`cancelled`** rather than `success` or `failure`, i.e. they sat queued until cancelled and never executed a step. These workflows implement the Vouch required-checks mechanism, so Vouch checks never actually execute on this fork.

**Evidence:**

- `vouch-check-pr.yml:17-35`, `vouch-check-issue.yml:17-30`, `vouch-manage-by-issue.yml:17-35`, `vouch-manage-by-discussion.yml:17-35`, `vouch-sync-codeowners.yml:17-35` read (triggers are all `workflow_dispatch: {}`).
- `gh run list --workflow=vouch-check-pr.yml --repo KooshaPari/Khostty --limit 1` → run `39328626439`, conclusion **`cancelled`** (2026-10-19T21:35:02Z).
- `gh run list --workflow=vouch-check-issue.yml --repo KooshaPari/Khostty --limit 1` → run `39014861069`, conclusion **`cancelled`** (2026-10-17T07:46:02Z).
- Runner count 0 as per F15.

---

## Commands used (read-only; all scoped to `KooshaPari/Khostty`)

```
ls -la .github/workflows/
git log -1 --format='%H %ad' ; git remote -v
gh variable list  --repo KooshaPari/Khostty      # -> empty (zero variables)
gh secret list    --repo KooshaPari/Khostty      # -> empty (zero secrets)
gh api repos/KooshaPari/Khostty/actions/runners --jq '.total_count'          # -> 0
gh api orgs/KooshaPari/actions/runners                                        # -> 404
gh api users/KooshaPari/actions/runners                                       # -> 404
gh api repos/KooshaPari/Khostty/branches/main/protection --jq '.required_status_checks.contexts'
gh run list --workflow=<each of 26 workflows> --repo KooshaPari/Khostty --limit 1
gh run list --workflow=test.yml --repo KooshaPari/Khostty --limit 5
gh run view 42782592087 --repo KooshaPari/Khostty --json jobs
grep -n "continue-on-error|vars\.|ghostty-org|runs-on:|^\s*if:" .github/workflows/*
```

No write, commit, push, or PR operation was performed. No command was issued against `ghostty-org/ghostty`.

## Unverified items (stated rather than guessed)

- Whether a `namespace-profile-ghostty-*` runner exists at any scope other than this repository. The repo-level API reports `0`; the org/user endpoints 404. The observed behaviour (all such jobs `skipped`/`cancelled`) is consistent with "no runner available", but the API evidence is repo-level only.
- Whether `wasm/package.json` declares `"lint"` and/or `"test"` scripts (relevant only to F7's additional no-op degradation; the `|| echo` defect is certain regardless).
- Whether the `test.yml` `on:` block was changed _before_ or _after_ the 2026-11-10 runs. The runs are `push` events, so the change post-dates them; the exact commit was not identified.

---

## Remediation log — 2026-11-12 (a later layer, not part of the read-only audit)

The audit above is a snapshot of a tree that was not modified. This section records what has since
changed, so each finding can be checked against a commit and a CI run instead of taken on trust.

| Finding                                                     | Status                      | Evidence                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ----------------------------------------------------------- | --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| F2 — macOS build never runs                                 | **OPEN by policy**          | `ci.yml:44-50`: billed macOS runners are disabled by repository policy, and the job is now opt-in on `vars.ENABLE_MACOS_BUILD` rather than `if: ${{ false }}`, so it can be enabled without editing the file. It is still `skipped` in run `43203165855` because the variable is unset.                                                                                                                                                                                                                                                                            |
| F3 — `cargo fmt --check` cannot fail                        | **RESOLVED**                | The step's `\|\| echo` mask is gone and it runs `cargo +nightly-2026-11-11 fmt --all -- --check` against a date-pinned nightly, because `khostty-vt/rustfmt.toml` sets the unstable `ignore` key. Run `43203165855`: step `cargo fmt --check` **success**.                                                                                                                                                                                                                                                                                                         |
| F4 — `cargo clippy -D warnings` cannot fail                 | **RESOLVED**                | `213ce07c2` removed the `\|\| echo` mask and moved the step after `zig build -Demit-lib-vt`, so `--all-targets` linted the 130 `ghostty_vt_linked` integration tests and both examples instead of a silent subset. `5b479f600` added `components: clippy`, which the pinned toolchain had dropped. Run `43203165855`: step `cargo clippy` **success**, and the next step in the same job printed `collected Rust tests: 199`, so the linked targets really were compiled.                                                                                          |
| F5 — `cargo-deny` cannot fail **and** never runs            | **RESOLVED**                | `6e979333c` added `khostty-vt/deny.toml` (which is what makes `has_deny` true), removed `continue-on-error`, and pinned cargo-deny `0.20.2`. Run `43203165855`, job `Cargo Deny (Advisories + Licenses)` **success**, output `advisories ok, bans ok, licenses ok, sources ok`. Negative control: with no config the same command exits 1 on the crate's own MIT licence.                                                                                                                                                                                          |
| F6 — Python lint job cannot fail                            | **RESOLVED**                | `4701ffec1` gave the repo a `ruff.toml`, fixed 32 of 33 first-party findings and kept one documented inline `noqa`; `bf9b4e017` corrected the counts and dropped three inert ignore entries. Run `43194362720`: job `Python` **success** with `ruff check` and `ruff format --check` unmasked. The negative control is in `docs/audit/2026-11-12-python-lint-gate/REPORT.md`.                                                                                                                                                                                      |
| F7 — TS/JS job cannot fail                                  | **RESOLVED**                | The `\|\| echo` masks were removed in the `ba506c86e`..`bf9b4e017` arc; run `43203165855` job `TS/JS` **success** with no mask in the file (verified: `grep -n 'continue-on-error\|\|\| echo' .github/workflows/ci.yml` returns only comments).                                                                                                                                                                                                                                                                                                                    |
| F8 — gitleaks cannot fail                                   | **RESOLVED**                | Mask removed in the same arc; run `43203165855` job `Security Scan` **success**.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| F9 — dependency-review cannot fail                          | **RESOLVED, PR-only**       | Mask removed in the same arc. The job is `pull_request`-scoped, so it is `skipped` on a push run like `43203165855`; that is the trigger, not a mask.                                                                                                                                                                                                                                                                                                                                                                                                              |
| F10 / F11 — SonarCloud cannot fail, and its scan never runs | **F10 resolved / F11 open** | `sonar.yml` no longer carries `continue-on-error`: the job was renamed from "Scan (advisory, never blocks)" to "Scan (blocking on scan errors; quality gate advisory)", so a scanner that crashes or cannot authenticate now fails the workflow, while the quality-gate result stays advisory via `breakBuildOnQualityGateFailure=false`. F11 remains: the repository still has no `SONAR_TOKEN`, so the scan step is skipped and a new notice step says so in the run log. Making the scan actually execute needs a token - an operator decision, not a refactor. |
| F12 — Infisical sync never runs                             | **OPEN by design**          | Gated on `vars.INFISICAL_SYNC == 'true'`, with the reason and the required secret written above the `if:`. It is not a required context, so gating it removes no gate.                                                                                                                                                                                                                                                                                                                                                                                             |
| F13–F22 — upstream `test.yml` / release suites              | **OPEN, upstream-owned**    | Those jobs are pinned to `namespace-profile-ghostty-*` runners and/or `if: github.repository == 'ghostty-org/ghostty'`, so they cannot be scheduled from this fork. Editing them is divergence on an upstream surface, which `docs/FORK-DISCIPLINE.md` requires to be bracketed and justified; the honest state is "cannot run here", not "green".                                                                                                                                                                                                                 |

### Remaining `continue-on-error` sites, measured not assumed

`grep -rn '^[[:space:]]*continue-on-error: true' .github/workflows/` returns exactly two, both deliberate:

| File:line                                     | What it masks                                 | Verdict                                                                                                                                                                                         |
| --------------------------------------------- | --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.github/workflows/ci-fork-discipline.yml:94` | Posting the discipline report as a PR comment | Intentional: the check that can fail is the previous step; publishing the report must not fail the job.                                                                                         |
| `.github/workflows/test.yml:1564`             | Upstream's `test-esctest` job                 | Upstream-owned and upstream-report-only (`nix develop -c zig build run > esctest.log \|\| true`), and it is guarded by `if: github.repository == 'ghostty-org/ghostty'`, so it never runs here. |

### One measurement trap worth recording

`zig run tools/check-fork-discipline.zig -- --strict` does **not** reproduce CI. It diffs against the
moving `upstream/main` tip, and on 2026-11-12 that reported **1905 violations across 1181 diverged
files / 137 upstream-owned surfaces** — all of it upstream's own newer commits. CI runs
`zig build check-fork-discipline -Dfork-discipline-strict=true`, whose baseline is
`git merge-base HEAD upstream/main` (`b3dc3d79` here), and that reports **419 diverged files, 3
upstream-owned surfaces, 0 violations, exit 0**. Any local "the fork is dirty" result from the
`zig run` form is an artifact of the baseline, not a finding.
