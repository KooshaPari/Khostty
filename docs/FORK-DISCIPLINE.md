# Fork Discipline Guard

Khostty is a fork of [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty). The promise of the fork is simple: **any modification we make to upstream-owned code should remain cheap to absorb when upstream moves.** This guard enforces that promise at PR time.

## Why this exists

The risk model: a well-intentioned modification to a `src/terminal/` file (or any other upstream-owned surface) silently breaks the fork's rebase hygiene. Example: upstream moves an enum variant, the fork's synthetic harness catches the move, but the cost of that catch is proportional to how invasive the fork's local changes were.

This guard catches the *opposite* failure mode — the well-intentioned modification that didn't trigger a synthetic harness but quietly grew the rebase surface.

## What's "upstream-owned"

These paths are treated as upstream-owned. A modification to any of them triggers the guard:

| Pattern | Why |
|---|---|
| `src/terminal/` | The entire terminal subsystem. The fork's most likely rebase-conflict surface. |
| `src/Surface.zig` | The terminal surface — close to the metal for the renderer. |
| `src/Command.zig` | Command parser; structure changes here ripple widely. |
| `src/runner.zig` | The lifecycle runner (note: this file does not exist in current upstream; the guard tolerates its absence). |

The list lives at the top of `tools/check-fork-discipline.zig` as `UPSTREAM_OWNED_PATTERNS`. To add a new pattern, edit the array and re-run the test suite.

## What the guard checks

For every file in the upstream-owned surface list that diverges from upstream, the guard checks four things:

1. **Documented.** The path is mentioned in `docs/FORK.md`. A modification without a corresponding entry in FORK.md is a violation.
2. **Bracketed.** Every added line is inside a `// FORK:` block in the source file. The block starts with a comment line of the form `// FORK: ...` and runs until the first blank or non-comment line.
3. **Tracked.** Each `// FORK:` block references a tracking issue, either `#123` or `GH-123`. The reference may live on the marker line or on any subsequent comment line in the same block.
4. **Single-segment additions.** The diff parser tracks ranges of contiguous `+` lines per hunk. Modifications that span a context line (e.g., "add line, then keep a context line, then add another") are split into multiple ranges so that an upstream-owned hunk that *happens* to contain context still flags its added lines.

## Running it

### Local

```sh
zig run tools/check-fork-discipline.zig -- --upstream upstream/main
```

Add `--output artifacts/fork-discipline.md` to write the report to a file. Add `--strict` to exit 1 on violations (default is advisory: exit 0, report only).

### Via `zig build`

```sh
zig build check-fork-discipline
# Strict mode:
zig build check-fork-discipline -Dfork-discipline-strict=true
# Custom upstream ref:
zig build check-fork-discipline -Dfork-discipline-upstream=origin/main
```

The build step writes the report to `artifacts/fork-discipline.md` (gitignored).

### Tests

```sh
zig test tools/check-fork-discipline.zig
```

Nine unit tests cover: pattern matching, hunk-header parsing, FORK-marker recognition, issue-ref recognition, line splitting, and the end-to-end diff-parser case.

## CI

`.github/workflows/ci-fork-discipline.yml` runs the build step on every PR and push to `main`. By default the job is **advisory**: it always succeeds, uploads the Markdown report as a workflow artifact, and posts (or updates) a single PR comment with the report. The marker `<!-- fork-discipline-bot -->` keeps the comment count at one.

To enable **strict mode** at the repo level, set the variable `FORK_DISCIPLINE_STRICT=true` in repository settings. The job will then exit non-zero when violations are detected, after uploading the artifact for the reviewer to read.

## Output

The Markdown report has the shape:

```md
# Fork Discipline Report

Upstream base: `upstream/main`  ·  Working tree mode: advisory (CI passes; review report)

## Summary

- Total files diverged from upstream: N
- Upstream-owned surfaces diverged: M
- Documented in `docs/FORK.md`: K
- Total discipline violations: V

## Per-File Findings

### `src/terminal/mouse.zig`

- Documented in `docs/FORK.md`: **no**
- Diff hunks: 1
- Added-line ranges: L90–L90
- ⚠ 1 added range(s) are NOT inside any `// FORK:` block
- ⚠ 0 `// FORK:` block(s) have no issue reference

**Verdict:** 2 violation(s)
```

A clean report (no upstream-owned divergences) is one paragraph: "No upstream-owned files have been modified in this fork. Upstream merges will be cheap to absorb."

## Marking a modification as a fork block

When you must modify an upstream-owned file, bracket the change with a `// FORK:` block that includes a tracking issue:

```zig
// FORK: khostty adds .windows to the mouse shape set for the Win32 backend.
// Tracked in GH-14736.
.none, .windows => void,
```

The marker may also be a doc comment (`///FORK:`) or have no space (`//FORK:`). The guard recognises all three.

The block terminates at the first blank line or non-comment line. If your modification spans non-contiguous hunks in a single function, add a `// FORK:` marker before each hunk (and a tracking issue per marker, or one issue on the first marker is enough — the guard accepts either).

## Adding a new upstream-owned pattern

If you find yourself modifying an upstream file that's not in the list, you have two options:

1. **Add it to the list** in `tools/check-fork-discipline.zig` and update this doc. This is the right move if the new path is genuinely upstream-owned (i.e., upstream modifies it and we expect to absorb the changes).
2. **Document it in `docs/FORK.md`** with the same rigor you'd use for any fork-delta. The guard's documented-in-FORK.md check will then pick it up automatically.

When in doubt, treat the file as upstream-owned by default. The cost of a false positive (one extra `// FORK:` block in your code) is much lower than the cost of an uncaught rebase regression.

## Why advisory by default?

The guard is a guard, not a gate. We want it visible in every PR without blocking first-time adoption. Once the existing fork delta has been retroactively marked with `// FORK:` blocks and tracked issues (the next section), we can flip the strict mode flag at the repo level and the guard becomes a real gate.

## Retroactive marking plan

The current fork delta is small (one file, one hunk, one added line). The plan:

1. Add a `// FORK:` block to the existing divergence in `src/terminal/mouse.zig` with a tracking issue.
2. Add the corresponding entry to `docs/FORK.md`.
3. Re-run the guard; verify the report shows zero violations.
4. Enable `FORK_DISCIPLINE_STRICT=true` in repo settings.

After step 4, every new divergence is caught at PR time and the fork's rebase surface stays visible.

## Related

- `docs/FORK.md` — The fork's own changelog and rationale. Required reading before any upstream-owned modification.
- `tools/check-fork-discipline.zig` — The implementation. The doc you just read is the *what*; the source is the *how*.
- `.github/workflows/ci-fork-discipline.yml` — The CI surface.
