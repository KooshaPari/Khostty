## Summary

<!-- One-paragraph description of the change: what + why, not how. -->

### What

### Why

### How

## Test plan

<!-- Bulleted checklist of what reviewers should run / verify. -->

- [ ] `zig build` (or `zig build -Doptimize=ReleaseSafe`) compiles cleanly on Linux/macOS.
- [ ] Unit tests pass.
- [ ] Smoke run on the affected platform(s): ___
- [ ] New code has matching tests (unit and/or integration).
- [ ] `zig fmt` produces no diff on touched Zig files.
- [ ] `prettier --check` clean on touched Markdown / YAML / JSON files.

## Risks

<!--
- [ ] Backwards incompatible (config schema, CLI flags, IPC wire format, env vars, file paths)
- [ ] Touches renderer / GPU / input / IPC boundary
- [ ] Touches build / CI workflows
- [ ] Requires rebase against current `main` because of upstream churn
- [ ] Large diff (>800 lines); consider splitting
-->

Estimated risk: **low / medium / high**.

Blast radius (which subsystems / platforms it could affect):

Rollback plan (how to revert cleanly if something breaks in CI or prod):

## References

<!-- Link to the issue, design doc, or upstream issue this PR closes. -->

- Closes #
- Related: #, #
- Design doc / session: `docs/sessions/...`
- Upstream issue (if cherry-pick or compatibility work): ghostty-org/ghostty#

---

<!-- Reminders:
- Required reviewers: at least 1 (branch protection enforces this).
- Required status checks: `ci/test` and `ci/zig-fork-tests` must pass on the up-to-date branch.
- Linear history is enforced; rebase before merging (no merge commits).
- Force-push to `main` is blocked; only force-push to your own feature branch if needed.
-->
