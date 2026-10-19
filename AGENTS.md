# Agent Development Guide

A file for [guiding coding agents](https://agents.md/).

> **This repository is a fork.** It is a working clone of
> [`ghostty-org/ghostty`](https://github.com/ghostty-org/ghostty) maintained at
> [`KooshaPari/Khostty`](https://github.com/KooshaPari/Khostty). Everything below
> describes the fork. The fork-only rules are binding and override the inherited
> "never create an issue/PR" line at the end of this file.

---

## Commands

- **Build:** `zig build`
  - If you're on macOS and don't need to build the macOS app, use
    `-Demit-macos-app=false` to skip building the app bundle and speed up
    compilation.
- **Test (Zig):** `zig build test`
  - Prefer to run targeted tests with `-Dtest-filter` because the full
    test suite is slow to run.
- **Test filter (Zig)**: `zig build test -Dtest-filter=<test name>`
- **Formatting (Zig)**: `zig fmt .`
- **Formatting (Swift)**: `swiftlint lint --strict --fix`
- **Formatting (other)**: `prettier -w .`

## libghostty-vt

- Build: `zig build -Demit-lib-vt`
- Build WASM: `zig build -Demit-lib-vt -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall`
- Test: `zig build test-lib-vt -Dtest-filter=<filter>`
  - Prefer this when the change is in a libghostty-vt file
- All C enums in `include/ghostty/vt/` must have a `_MAX_VALUE = GHOSTTY_ENUM_MAX_VALUE`
  sentinel as the last entry to force int enum sizing (pre-C23 portability).

## Directory Structure

- Shared Zig core: `src/`
- macOS app: `macos/`
- GTK (Linux and FreeBSD) app: `src/apprt/gtk`

---

## Working with this repo

- **`docs/audits/` is untracked.** Audit working files live in `docs/audits/`
  during an investigation arc and are **never** `git add`-ed, `git commit`-ed,
  or pushed. When an audit arc closes, the snapshot is moved into a versioned,
  repo-tracked directory under `docs/audits-archive/<YYYY-MM-DD-...>/`. The
  archive is committed; the working directory stays untracked.
  - Rationale: audits are evolving work artefacts. Committing mid-arc creates
    false history and confuses blame. Archiving the final state preserves
    evidence without polluting the working tree.
  - Trigger rule: never `git add docs/audits/`; never `git add -f docs/audits/`.
    If you see staged files there, run `git restore --staged docs/audits/`
    before committing.

## Fork discipline

The fork contract lives in [`docs/FORK-DISCIPLINE.md`](docs/FORK-DISCIPLINE.md)
(maintained by the fork-discipline agent; the file documents the rules listed
here and is the canonical reference for any ambiguity).

**Contract (binding summary):**

- The fork is `KooshaPari/Khostty`. The upstream is `ghostty-org/ghostty`.
- Modifying any of the following files requires **both**:
  1. A `// FORK: <reason>` block at the top of the touched source file(s),
     pointing at the tracking issue.
  2. An open GitHub issue on `KooshaPari/Khostty` (NOT `ghostty-org/ghostty`)
     tracking the divergence, linked from the `// FORK:` block.
- Protected paths:
  - `src/terminal/`
  - `src/Surface.zig`
  - `src/Command.zig`
  - `src/runner.zig`
- Why these files: they sit on the hot path between the fork's IPC additions
  and the inherited terminal engine. Touching them carelessly breaks both the
  fork's IPC surface and the inherited engine in ways that are not visible
  until the agent exercises the runtime end to end.
- The PR-style audit guard runs `zig build check-fork-discipline` (see
  [Gates](#gates) below). It fails the build if a `// FORK:` block is missing
  on a modification to a protected path, or if the referenced issue is closed
  without a follow-up `// FORK:RESOLVED` marker.

## Phase boundaries

The IPC work (WBS G4) is split into two phases that are easy to confuse:

| Phase                            | Scope                                                                                                  | State (as of this commit)                           |
| -------------------------------- | ------------------------------------------------------------------------------------------------------ | --------------------------------------------------- |
| **Phase 0** — Build graph wiring | The agent-IPC source tree is reachable from `zig build` (compile-time graph only).                     | **DONE** at commit `ebc033eba` (merged via PR #15). |
| **Phase 1** — Runtime wire-up    | A running `zig build run` instance actually accepts agent connections and round-trips `ping` → `pong`. | **NOT DONE**. This is the actual G4 finish line.    |

The two phases share a surface (both add files under `src/apprt/ipc/`) but are
distinct deliverables. Phase 0 is necessary but not sufficient; claiming "G4
done" because Phase 0 is merged is wrong. Phase 1 requires:

- `src/apprt/ipc/server.zig` exists and exports a listenable transport.
- `src/apprt/ipc/app_host.zig` exists and bridges the transport to the
  apprt host.
- A fresh `zig build run` followed by `zig build test-agent-ipc` passes
  end-to-end against the live binary, not just the unit tests.

## Gates

Before committing to `main`, run all of the following and confirm they pass:

```bash
zig build test             # full Zig test suite (or -Dtest-filter=<...> for speed)
zig build test-agent-ipc   # fork-only agent IPC tests; refuses to run on inherited code paths
zig build check-fork-discipline  # fork-discipline guard; fails on missing/closed-issue markers
```

Optional but recommended:

- `zig fmt .` — formatting (CI also enforces this via trunk).
- `prettier -w .` — non-Zig/Swift files.

Do **not** skip `check-fork-discipline` even on a "trivial" change to a
protected path. The guard exists precisely because the failure mode is silent.

---

## Issue and PR Guidelines (fork-only override)

The upstream Ghostty `AGENTS.md` says: _never create an issue, never create a
PR._ That rule exists to keep agents from spamming upstream maintainers. **It
does not apply to this fork.** For `KooshaPari/Khostty`:

- **Issues:** agents **may** open issues on `KooshaPari/Khostty` to track fork
  work. They **must not** open issues on `ghostty-org/ghostty`.
- **PRs:** agents **may** open PRs on `KooshaPari/Khostty`. They **must not**
  open PRs, discussions, or API-mutating calls against `ghostty-org/ghostty`
  or any other upstream repo.
- **`gh pr create` in a fork:** always pass `--repo KooshaPari/Khostty`
  explicitly. `gh` otherwise defaults to the upstream repo and will silently
  create the PR against `ghostty-org/ghostty`. Verify the URL starts with
  `github.com/KooshaPari/...` before treating the call as successful.

## Forbidden actions (binding)

The following are hard-blocked. They will be rejected by policy, by the
destructive-command blocklist, or by the operator.

1. **No upstream publishing.** Never run `gh pr create`, `gh issue create`,
   `gh discussion create`, or `gh api POST/PATCH/DELETE` against
   `ghostty-org/ghostty` or any other upstream repo. Reading upstream,
   copying files, and tracking upstream branches are fine. Pushing to
   `KooshaPari/*` is fine.
2. **No force pushes to `main`.** `git push --force` and
   `git push --force-with-lease` to `main` are blocked. Fix forward
   (`git revert` for shared commits; new commits for local mistakes).
3. **No committing `docs/audits/`.** The directory is untracked by design.
   Snapshots go into `docs/audits-archive/<date>-<label>/` when an arc closes.

## Session documentation

Session work artefacts live under `docs/sessions/<YYYYMMDD>-<name>/`. Do not
create temporal-suffixed docs (`SUMMARY.md`, `STATUS_FINAL.md`, `V2.md`,
`_new.md`, `_old.md`) anywhere outside that directory. If you find one in the
working tree, consolidate it into the appropriate session doc and delete the
stray file before committing.
