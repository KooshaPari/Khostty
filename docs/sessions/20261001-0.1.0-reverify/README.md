# Khostty 0.1.0 — Second Post-Release Re-Verify (WBS 10.9)

**Executed:** 2026-10-01 17:56–18:20Z by session_calf (backstop `sched_998a502a`,
fired 17:00Z; this session resumed on operator "proc").
**Repo:** `/Users/kooshapari/CodeProjects/Phenotype/repos/khostty`
**HEAD at entry:** `e6490dada` (local, ahead of origin by 1 — pushed as part of
this re-verify).

## Check results (8 checks)

| # | Check | Observed | Verdict |
|---|---|---|---|
| 1 | `shasum -a 256 -c dist-release/CHECKSUMS.txt` | **9/9 OK** | PASS |
| 2 | `git ls-remote --tags origin v0.1.0` | `7e1684f60e2ab03cca3e0b653c65b1b4e1247d10` (peels to `202aad543`) | PASS |
| 3 | crates.io API `khostty-vt` | `newest=0.1.0`, `yanked=False` (UA header required; bare curl gets rejected) | PASS |
| 4 | PyPI JSON probe | **`404`** — still credential-blocked; `khostty-vt` unpublished | BLOCKED (expected) |
| 5 | npm `khostty-libghostty-vt-wasm` | `dist-tags.latest = 0.1.0`, integrity `sha512-+hPNpxxFA4ZERHmfDDx5/qKvUQCH9Ub4DHKcalugX+RYCM54M3uQ8…` | PASS |
| 6 | `gh release view v0.1.0` | draft=false, **exactly 6 assets**: CHECKSUMS.txt 4,273 / macos.zip 35,953,098 / setup.exe 19,766,307 / wasm tarball 680,598 / lib `.deb` 2,320,612 / GTK `.deb` 18,143,964 — byte sizes match §7 expectations | PASS |
| 7 | WSL mirror / desk | `kooshapari-desk` **offline, last seen 6d** (Tailscale); host no longer resolves via MagicDNS. Per rule: noted, **no retry, no reschedule**; r4 stays pending. | BLOCKED (hardware) |
| 8 | Evidence doc + commit + push | this file | DONE |

`docs/RELEASE.md` §7 status table matches observed reality after these checks —
no reconciliation edits required (PyPI row already states the credential block).

## CI status (major change since 09-29)

**GitHub Actions is now enabled on the fork** (the 09-29 blocker is gone; the
first post-enable run `36628566922` on `882d6cd4a` executed all 12 jobs).

Run `36628566922` (2026-09-29, 1h23m — runner queue was saturated by a parallel
session's PR storms; 52 runs cancelled repo-wide that day):

| Job | Result | Root cause |
|---|---|---|
| Zig Fmt | failure | `install-zig` step ran `zig version` in the same step that wrote `GITHUB_PATH`; PATH only applies to later steps → `command not found` (exit 127). **Fixed 10-01:** inline `export PATH`. |
| Security Scan | failure | gitleaks SARIF (artifact 11064598652) = 2 findings: `src/input/Binding.zig:4886` secret `chain=close_surface` (a test keybinding literal) and `src/terminal/snapshot/terminal.zig:1035` secret `header.modify_other_keys_2` (a struct field). The 09-29 allowlist comment mischaracterized both. **Fixed 10-01:** two secret-anchored regexes; local gitleaks 8.30.0 rescan → `no leaks found` on both files. |
| TS/JS | failure | `setup-node` `cache: 'npm'` hard-fails because **no lockfile exists anywhere in the tree** and the job ran at repo root (root has no package.json; TS project is `wasm/`). **Fixed 10-01:** dropped cache input, `defaults.run.working-directory: wasm`, plain `npm install`. |
| ci / lint | failure | aggregate: only `zig-fmt: failure` gated it; `typescript`/`security` reported `success` because `continue-on-error: true` absorbs them into the needs context. |
| Detect, Rust, Go, Python, ci / test | **success** | ecosystem-detection fix from 09-29 confirmed working — nested Rust/Go/TS jobs now run. |

Note: despite the 4 job failures, `ci / lint` failing on zig-fmt was the only
gating failure; fixes above are all three root causes.

## PyPI publication path (unchanged, still the one human step)

- Browser upload form no longer exists in Warehouse (documented 09-29,
  `docs/sessions/khostty-0.1.0-release/01_RESEARCH_pypi-publication.md`).
- Two viable paths, both needing the operator:
  1. **Trusted Publishing (preferred):** register a publisher on PyPI for
     `khostty-vt` → owner `KooshaPari`, repo `Khostty`, workflow
     `publish-pypi.yml`, environment `pypi`; then push tag `khostty-v0.1.0`.
     Workflow is repaired as of `e6490dada` (id-token: write, split
     build/publish jobs, dispatch-gate fix — see bear's audit).
  2. **Token:** project-scoped token + `read -rs T` twine command staged in
     Ghostty.
- `publish-pypi.yml` never triggers on the existing `v0.1.0` tag by design.

## Open items after this re-verify

1. **r2b / PyPI** — operator action (trusted publisher registration or token).
2. **r4 / WSL mirror** — desk hardware offline 6d; sole backstop consumed; no
   further probes scheduled per rule. Origin authoritative.
3. **CI green run** — three fixes pushed 10-01; awaiting the post-push run to
   confirm Zig Fmt / Security Scan / TS/JS go green.

## Evidence artifacts

- `evidence/zig-checksum-verification.txt` (09-29): full 55,478,392-byte Zig
  tarball SHA-256 matches official `index.json`.
- gitleaks SARIF from run 36628566922 downloaded to scratch
  (`$JCODE_SCRATCH_DIR/gitleaks-artifact/work/Khostty/Khostty/results.sarif`).
