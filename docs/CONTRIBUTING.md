# Contributing

**Observed:** 2026-09-17 · This repository is a fork of
[`ghostty-org/ghostty`](https://github.com/ghostty-org/ghostty). Two contribution
paths exist and they have **different rules**. Read the first section before you
push anything.

---

## 1. Which path are you on?

| | Fork (this repository) | Upstream Ghostty |
|---|---|---|
| Who merges | Khostty maintainers | Ghostty maintainers |
| Agent-authored PRs | Permitted for fork work | **Prohibited — see below** |
| Prerequisite | None | Vouch system ([upstream CONTRIBUTING.md](../CONTRIBUTING.md)) |
| AI disclosure | Required in the commit ledger | Required by [`AI_POLICY.md`](../AI_POLICY.md) |
| Change scope | Khostty delta + docs | Upstream core |

### Upstream rules that still bind

`AGENTS.md` in this repository is upstream's agent guide and it is explicit:

> - Never create an issue.
> - Never create a PR.

`AI_POLICY.md` is upstream's and requires AI usage to be disclosed, the
human-in-the-loop to fully understand the code, and no AI-generated media.
`CONTRIBUTING.md` at the repository root is also upstream's, and it describes the
vouch system, the denouncement list, and the "you must understand your code" rule.

**Consequence:** do not open pull requests or issues against
`ghostty-org/ghostty` from this fork without a human taking ownership of the
submission and following the vouch process. Fork-side work does not go upstream by
default.

---

## 2. Before you write code

1. **Read the gate.** `docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md` is
   the authoritative decomposition. Find the gate and task you are serving. If
   your change does not map to a task, say why in the commit.
2. **Check for in-flight work.** `git status` and `git log --oneline -10`. This
   repository is often edited by several agents at once. Do not duplicate a change
   someone else has staged.
3. **Respect the fork boundary.** Khostty changes belong in `src/apprt/windows/`,
   `src/apprt/ipc/`, `khostty-vt/`, `wasm/`, `conformance/`, `bench/`, or `docs/`.
   Do **not** modify `src/terminal/`, `src/renderer/`, `src/font/`, or
   `src/config/` — keeping those pristine is what makes upstream merges cheap.
4. **Understand your code.** You must be able to explain the change and its
   interactions without the aid of the tool that wrote it.

---

## 3. Definition of done

A change is done when it is merged, builds, and its behaviour is observed — not
when it compiles.

| Requirement | How it is demonstrated |
|---|---|
| Builds | The relevant build command runs clean; paste the command and result |
| Tested | The relevant suite passes; state which suite and the date |
| No VT regression | `conformance/build.sh` still passes (84/84) for anything touching parsing, formatting, or state |
| Documented | Public surface changes update `docs/API.md`; new gates update `docs/PLATFORMS.md` |
| Traced | Commit carries `tx-agent`, `tx-validated`, and `tx-task` (see §7) |

**Never claim a gate passed without a dated observation.** "Should work",
"probably passes", and "same as before" are not evidence. If you did not run it,
say `tx-validated: none`.

---

## 4. Tests you are expected to run

Pick by what you touched. See [TESTING.md](TESTING.md) for detail.

| You changed | Run |
|---|---|
| `src/terminal/**`, formatter, snapshot, search | `conformance/build.sh` (native), `cd wasm && npm run check` |
| Anything under `khostty-vt/` | `cd khostty-vt && cargo test && cargo clippy && cargo fmt --check` |
| `wasm/js/**`, `wasm/tools/**` | `cd wasm && npm run check` |
| `include/ghostty/**` (C ABI) | Regenerate the consolidated header, `cd wasm && npm run test:header`, and `khostty-vt/tests/abi_layout.rs` |
| Zig sources generally | `zig build test` (use `-Dtest-filter` — the full suite is slow) |
| `src/apprt/windows/**` | No suite exists yet (G3). State clearly that nothing was executed. |
| Docs only | No suite. Verify links resolve and claims match the files you cite. |

A C ABI change is a breaking change for every language wrapper. If you touch
`include/ghostty/`, expect to touch the Rust bindings, the consolidated header,
and the WASM type manifest together.

---

## 5. Style

### Zig

```bash
zig fmt .                  # format
zig fmt --check src/ build.zig   # what CI enforces
```

### C

`.clang-format` at the repository root is authoritative. C declarations in
`include/ghostty/vt/` follow upstream conventions, including the mandatory
`_MAX_VALUE = GHOSTTY_ENUM_MAX_VALUE` sentinel as the last entry of every C enum
(it forces int enum sizing for pre-C23 portability).

### Other languages

| Language | Tool | Config |
|---|---|---|
| Swift | `swiftlint lint --strict --fix` | `.swiftlint.yml` |
| Markdown / JSON / YAML | `prettier -w .` | `.prettierignore` |
| Shell | `shellcheck` | `.shellcheckrc` |
| All text | `typos` | `typos.toml` |
| Editor | `.editorconfig` | — |

Some of these tools are declared by upstream but not wired into the fork's CI, so
run them locally before you rely on them.

---

## 6. File size and modularity

- **Target ≤ 350 lines.** Hard limit **500 lines**. Exceeding 500 requires an
  explicit reason in the commit message.
- One file, one concern. If two files address the same concern, merge them; if a
  file approaches 350 lines, split it along a real boundary.
- No `_v2`, `_new`, `_old`, `_final`, `_complete`, `_helper` suffixes. Version
  history belongs in git.
- Tests are named for the concern they test (`test_entity.py`), never for
  execution speed or variant (`_fast`, `_unit`, `_e2e`). Use markers and fixtures
  for variants.
- When you split a file, update **all** callers in the same change. No compatibility
  shims, no partial migrations.

---

## 7. Commit ledger

Git history is treated as an append-only transaction ledger. Every agent-authored
commit carries metadata trailers, and history is never rewritten.

### Required trailers

| Trailer | Value | Required |
|---|---|---|
| `tx-agent` | `jcode`, `codex`, `forge`, `human` | yes |
| `tx-validated` | `lint`, `test`, `build`, `cargo-check`, `manual`, `none` | yes |
| `tx-task` | WBS task, e.g. `9.1,9.9` | recommended |
| `tx-scope` | affected components, e.g. `docs` | recommended |
| `tx-intent` | one line on what the change achieves | recommended |
| `tx-parent` | parent transaction hash | when applicable |

### Use the wrapper

```bash
git-commit "docs(g9): add ARCHITECTURE.md (WBS 9.1)"
```

`git-commit` detects the agent from the environment
(`JCODE_SESSION_ID`, `CODEX_SESSION_ID`, `FORGE_SESSION_ID`) and appends
`tx-agent` and `tx-validated`. Pass the message **positionally** — the wrapper
only injects trailers on the positional path, not on `-m`.

### Query the ledger

```bash
git lg                    # formatted log with trailers
git lg-agent jcode        # commits by one agent
git lg-task 9.1           # commits for one task
git lg-validate 50        # trailer compliance over the last 50 commits
git lg-audit              # integrity check
```

### Never rewrite history

| Forbidden | Why |
|---|---|
| `git push --force` / `--force-with-lease` | Rewrites published history |
| `git reset --hard` | Destroys uncommitted work |
| `git clean -fd` | Destroys untracked work |
| `git branch -D` | Destroys branch state |
| `gh repo delete` | Destroys the repository |

Fix forward. If a commit is wrong, add a corrective commit. Reverting a published
commit is a *new* commit, not a rewrite.

---

## 8. Documentation conventions

| Content | Location |
|---|---|
| Canonical reference (architecture, API, build, platforms, …) | `docs/*.md` |
| Session work, evidence, assessments, WBS | `docs/sessions/<YYYYMMDD-name>/` |
| Gate evidence and run outputs | the relevant session folder |

Rules:

- Session artifacts are the only place a date-stamped measurement belongs. Do not
  put run outputs in canonical docs.
- Canonical docs state an **observation date** for any status claim.
- Never create `SUMMARY.md`, `STATUS.md`, `FINAL.md`, `_V2.md`, or similar
  temporal files. Update the existing living doc.
- Cross-link. Every doc in `docs/` ends with a "See also" section.
- Deleting a stale doc is preferred over leaving a contradicting one.

---

## 9. Continuous integration

### What actually runs in this fork

`.github/workflows/ci.yml` is the fork's own workflow:

| Job | Runner | Command |
|---|---|---|
| Zig Fmt | `ubuntu-latest` | `zig fmt --check src/ build.zig` |
| Build (macOS) | `macos-latest` | `zig build -Doptimize=ReleaseSafe -Demit-macos-app=false` |

Both install Zig 0.16.0.

### What does not run

Upstream workflows are present but ineffective here:

| Workflow | Why it cannot help |
|---|---|
| `test.yml` | Every job is gated on `github.repository == 'ghostty-org/ghostty'` |
| `nix.yml`, `flatpak.yml`, `update-colorschemes.yml` | Same repository guard |
| `nix.yml` additionally | Targets `namespace-profile-ghostty-*` runners that do not exist for this repository |
| 12 other workflow files | Carry **no** repository guard and would attempt to run |

Notably there is **no Linux build job and no Linux test job**. If you are
contributing Linux support, local verification is the only verification.

### Consequence for reviewers

macOS build + Zig formatting are the only automated gates. Everything else —
conformance, Rust tests, WASM tests, Windows cross-compilation — is verified by
the contributor, on their machine, with the result recorded in the commit.
Reviewers should ask for that record.

---

## 10. Review checklist

- [ ] Change maps to a WBS task, or the commit explains why it does not
- [ ] Upstream core (`src/terminal/`, `src/renderer/`, `src/font/`, `src/config/`) untouched
- [ ] Relevant tests run; the command and result are in the commit message
- [ ] `conformance/build.sh` still passes for VT-affecting changes
- [ ] No file exceeds 350 lines without a stated reason (500 hard limit)
- [ ] No compatibility shims, no temporal file names, no dead code left commented out
- [ ] Docs updated if a public surface changed
- [ ] Commit carries `tx-agent` and `tx-validated`
- [ ] No secrets, tokens, or credentials in the diff
- [ ] Status claims are dated and observed, not inferred

---

## See also

- [TESTING.md](TESTING.md) — how to run each suite
- [BUILD.md](BUILD.md) — build commands and troubleshooting
- [FORK.md](FORK.md) — what the fork changes and what it must not
- [SECURITY.md](SECURITY.md) — disclosure and the IPC auth requirement
- [ARCHITECTURE.md](ARCHITECTURE.md) — where a change belongs
- `AI_POLICY.md`, `AGENTS.md`, `CONTRIBUTING.md` (root) — upstream policies
- `HACKING.md` — upstream's deeper development guide
