# Khostty 0.1.0 post-release re-verify (WBS 10.9) — 2026-09-27

Scheduled task `sched_983cf93b` (one week after the 2026-09-24 release push).
Executed by the ambient cycle of 2026-09-27, ~16:07–17:16 UTC.

Verdict: **all six success criteria PASS.** The one gap observed during the run
(the GitHub release did not yet exist at 16:17Z) closed mid-cycle: the phinbox
gate answered the canonical §7.1 command at 16:18:40Z and a concurrent session
recorded it (commit `f0a5e405c`).

## 1. Evidence per success criterion

| # | Criterion | Result | Evidence |
|---|---|---|---|
| 1 | `git tag v0.1.0` still resolves on origin | **PASS** | `git ls-remote --tags origin v0.1.0` → `7e1684f60e2ab03cca3e0b653c65b1b4e1247d10` (peels to `202aad543`), observed 2026-09-27 16:16Z |
| 2 | `shasum -a 256 -c dist-release/CHECKSUMS.txt` | **PASS — 9/9 OK** | executed in repo root 16:16Z, exit 0: macos.zip, wasm tarball, `dist/khostty-vt_0.1.0_amd64.deb`, `zig-out/bin/ghostty.exe`, `zig-out/bin/ghostty-vt.dll`, both stage-windows payload files, `dist-release/khostty_0.1.0_amd64.deb`, wasm verify `khostty-vt.wasm` |
| 3 | crates.io `khostty-vt` newest = 0.1.0, `.crate` checksum matches | **PASS** | crates.io API: `newest_version=0.1.0`, version present, `yanked=false`, API checksum `ec5e549c5b7460398e806597d914ea240c71d5abf9d2a51437e9cdbd20441858`. Downloaded `https://crates.io/api/v1/crates/khostty-vt/0.1.0/download` → sha256 identical |
| 4a | PyPI publish state re-probed | **STILL BLOCKED (expected)** | `https://pypi.org/pypi/khostty-vt/json` → HTTP 404; `khostty` → 404. Both names free; publish still needs an operator-provided token (no `.pypirc`/keyring/env/OIDC on machine) |
| 4b | npm publish state re-probed | **PASS — published** | `https://registry.npmjs.org/khostty-libghostty-vt-wasm` → HTTP 200; versions `["0.1.0"]`, `dist-tags.latest=0.1.0`, created `2026-09-24T10:47:28Z`, `dist.shasum=2754b0a423ee035b421dc232ceb6f8fc6c85b57d` — matches the staged-package shasum recorded in RELEASE.md §7. No longer credential-blocked |
| 5 | GitHub release exists with 6 assets, hashes match CHECKSUMS.txt | **PASS** (closed mid-cycle) | `gh release view v0.1.0` → `release not found` at 16:17Z; **published 2026-09-27T16:18:40Z** (not draft, not prerelease). Exactly 6 assets, sizes: CHECKSUMS.txt 4,273 B; Khostty-0.1.0-macos.zip 35,953,098 B; …-windows-x86_64-setup.exe 19,766,307 B; wasm tarball 680,598 B; `khostty-vt_0.1.0_amd64.deb` 2,320,612 B; `khostty_0.1.0_amd64.deb` 18,143,964 B — all equal the §7.2 expected byte counts. Downloaded 4 hash-covered assets + CHECKSUMS.txt from the release URL and compared sha256 (see §2): **5/5 match**. The windows `…setup.exe` is not listed in CHECKSUMS.txt (only its payload `ghostty.exe`/`ghostty-vt.dll` are); its size matches the §7.2 expectation |
| 6 | RELEASE.md §7 status table matches reality | **PASS** (reconciled mid-cycle) | At cycle start the GitHub-release row still named expired `hook-a683332d…` as PENDING. Concurrent session `f0a5e405c` (16:24:58Z, now origin/main) rewrote it to **PUBLISHED 2026-09-27** with §7.2 numbers. I re-read the table post-push: tag/crates.io/PyPI/npm/GitHub rows all match my independent observations. §7.1 comment correctly names `hook-ea20989dca45c9e2c6c1c915ba817571` as the superseding gate |

## 2. Asset hash verification (criterion 5 detail)

`gh release download v0.1.0 --repo KooshaPari/Khostty` → local sha256 vs
`dist-release/CHECKSUMS.txt` lines:

| Release asset | sha256 (downloaded from release) | CHECKSUMS.txt line | Match |
|---|---|---|---|
| Khostty-0.1.0-macos.zip | `94abd2a7e7d63e790bfffd3a6e6f4e08ae80a67fbf3dbe8227e754c6104317cb` | same | ✅ |
| khostty-libghostty-vt-wasm-0.1.0.tar.gz | `55cfc67572696db9eaf48cb69ae231ca99119aa1caf064e0c08c8c8c178604dc` | same | ✅ |
| khostty-vt_0.1.0_amd64.deb | `3c080d13a74d6bf6dca9d28dc2c685f6b4350ec3130f3f3fafa5cb4d77d834cf` | same | ✅ |
| khostty_0.1.0_amd64.deb | `63d4e6159d65e97db685b9eedbe19c37765f5f838279e9d5b0326ab5a7b80de0` | same | ✅ |
| CHECKSUMS.txt (asset) | `96bf0b556042b2feff0daaaf46dc7750f3fe80961f43053f3c07e86c72df381e` | equals local `dist-release/CHECKSUMS.txt` | ✅ |

## 3. Timeline of the approval gate this cycle (phinbox, read-only GETs only)

- `hook-a683332d46ba9fff95e5a91b0f239118` (original): **expired** — detail page says it can no longer be answered.
- `hook-ea20989dca45c9e2c6c1c915ba817571` (superseding, named in §7.1): served an answerable form at 16:18:42Z but was absent from the inbox index — it was in fact answered seconds earlier: the canonical `gh release create v0.1.0 …` executed **2026-09-27 16:18:40Z**, uploading all 6 assets.
- No hook was ever self-approved by this session; all phinbox access was GET-only.

## 4. Repository state at end of check

- `main` = `f0a5e405c` = `origin/main`, working tree clean (after `git pull --rebase`).
- `docs/RELEASE.md` §7 table reconciled by `f0a5e405c`; this session doc is the only file added here.
- Open blocker unchanged: **PyPI `khostty-vt` publish needs an operator token.**
- Not attempted (out of success-criteria scope): WSL `/root/khostty` sync to `f0a5e405c` (§7.2 step 6 remainder) — recommend the owning session run it.
  - **Owning-session follow-up, 2026-09-27 17:20 UTC:** five SSH attempts (16:25, 16:26, 16:41, 17:16, 17:20 UTC) all timed out to `desk`. Tailscale reports `kooshapari-desk` (100.96.135.160) **offline, last seen 2 days ago** — the box is powered off/asleep; no remote wake is possible. Stopped retrying per scheduled task `sched_839d2c8d` instructions. The WSL mirror remains at `5cca58661`; origin (then `2a615b53a`) is authoritative. **The 2026-10-01 re-verify should attempt the sync once** (`ssh desk "wsl -d FedoraLinux-44 -u root -- bash -s" < /Users/kooshapari/.jcode/scratch/wsl_sync.sh`) in case the box is back.

## 5. Commands used (reproducible)

```bash
git ls-remote --tags origin v0.1.0
shasum -a 256 -c dist-release/CHECKSUMS.txt
curl -s https://crates.io/api/v1/crates/khostty-vt -H 'User-Agent: jcode-ambient-check'
curl -sL -o /tmp/k.crate https://crates.io/api/v1/crates/khostty-vt/0.1.0/download
shasum -a 256 /tmp/k.crate
curl -s -o /dev/null -w '%{http_code}' https://pypi.org/pypi/khostty-vt/json
curl -s https://registry.npmjs.org/khostty-libghostty-vt-wasm
gh release view v0.1.0 --repo KooshaPari/Khostty --json assets,createdAt,publishedAt
gh release download v0.1.0 --repo KooshaPari/Khostty --pattern ... --clobber
shasum -a 256 <downloaded assets>   # compare to dist-release/CHECKSUMS.txt
curl -s http://127.0.0.1:7117/inbox/hook-<id>   # GET only, never answered
```

## 6. Addendum — 2026-09-29 drift sweep and first CI run

Re-probed every published surface and swept the shipped docs for claims that had
drifted from reality. All registry/tag/asset checks re-confirmed unchanged
(crates.io `0.1.0` not yanked, npm `latest=0.1.0`, `v0.1.0` tag `7e1684f6`,
release not draft with the same 6 assets, PyPI still 404).

Four real defects were found and fixed rather than merely reported:

| # | Defect | Evidence | Fix |
|---|---|---|---|
| 1 | `docs/HANDOFF.md` §6 still said the Rust crate was "not published to crates.io" | contradicted the 2026-09-20 publish; crates.io API returns `newest_version=0.1.0` | `5d5f023b2` |
| 2 | `docs/RELEASE.md` step 6 still labelled an already-executed tag step `DO NOT RUN YET` | tag has been live since 2026-09-24 | `44a1f892d` |
| 3 | `.github/workflows/ci.yml` had **no runs in the repo's history** and no `workflow_dispatch`, so the released tree's pipeline was unverifiable | `actions/workflows/ci.yml/runs` → `total_count: 0`; dispatch returned HTTP 422 | `1cf505ebd` |
| 4 | `ci.yml` declared the job key `lint` **twice** (line 21 `Zig Fmt`, line 228 aggregate gate). YAML last-wins silently collapsed the map, and GitHub rejected the file outright | dispatch after #3 returned `Line: 228: 'lint' is already defined` | `a7bce476e` |

Defect 4 also carried a second bug: the aggregate gate read
`needs.dependency-review.result`, which never matched the `dep-review` job id, so
that row would have rendered empty. Both were corrected; the graph now validates as
12 jobs with no dangling `needs` and no duplicate keys, and the Zig Fmt job is
reachable again.

### 6.1 Dependabot alert #1 — triaged, deliberately left open

`CVE-2025-71176` / `GHSA-6w46-j5rx-g56g`, `pytest` "vulnerable tmpdir handling"
(medium), manifest `khostty-python/uv.lock`.

The advisory covers pytest **through 9.0.2**; the fix line is **9.0.3**, which
requires **Python >=3.10**, and **no patched 8.x exists** (8.4.2 is the final 8.x).
This package declares `Requires-Python: >=3.8`, so the vulnerable resolution cannot
be removed without dropping 3.8/3.9 support. Scope is bounded: `pytest` is a `test`
**extra**, not a runtime dependency — the wheel's `METADATA` carries only
`Requires-Dist: cffi>=1.15` plus `pytest>=7; extra == "test"`, and no pytest file is
present in the shipped artifact. The 3.10+ lane already resolves to the patched
9.1.1, and CI runs Python 3.11, so the pipeline is unaffected. Recorded in
`docs/SECURITY.md` §8 with re-triage conditions.

### 6.2 Commands used for this addendum

```bash
gh api repos/KooshaPari/Khostty/dependabot/alerts --jq '.[] | {number, ...}'
gh api repos/KooshaPari/Khostty/actions/workflows/ci.yml/runs?per_page=5 --jq '.total_count'
gh workflow run ci.yml --repo KooshaPari/Khostty --ref main
python3 -c "import yaml; ..."   # job-graph validation: duplicates + dangling needs
curl -s https://pypi.org/pypi/pytest/json   # confirms 8.4.2 is the last 8.x, 9.0.3 needs >=3.10
unzip -p khostty-python/dist/khostty_vt-0.1.0-py3-none-any.whl '*/METADATA'   # pytest is test-extra only
```
