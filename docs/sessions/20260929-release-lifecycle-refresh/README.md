# Khostty release lifecycle refresh - 2026-09-29

## Scope and evidence boundary

Read-only refresh of the Khostty release records and inherited release
automation. Observed local `main` and `origin/main` at
`666fbf8616b0af566010b3ea75efcdb852ad2369`; the worktree was clean before this
leaf was added. GitHub repository ID: `1322607630`. This note does not claim
release readiness or exercise a release. No tests, screenshots, or workflow
dispatches were run by this audit.

## Current release identity

| Item | Observation |
|---|---|
| `v0.1.0` tag object | `7e1684f60e2ab03cca3e0b653c65b1b4e1247d10` |
| Peeled target | `202aad5438c24ae0c76122e5b446d3bd774a61ca` |
| Tag form | Annotated; unsigned. `git verify-tag v0.1.0` reports `no signature found`. |
| GitHub release | Published, not draft or prerelease; published `2026-09-27T16:18:40Z`; release ID `397718820`. |
| Assets | Six, listed below with GitHub API SHA-256 and byte sizes. |
| Open PRs | None observed in the parent checkpoint. |
| Issues | Issue tracking is disabled; no issue count is inferred. |
| Dependabot | One open pytest alert (see `docs/SECURITY.md` §8). |

| GitHub release asset | Size (bytes) | GitHub API SHA-256 |
|---|---:|---|
| `CHECKSUMS.txt` | 4,273 | `96bf0b556042b2feff0daaaf46dc7750f3fe80961f43053f3c07e86c72df381e` |
| `Khostty-0.1.0-macos.zip` | 35,953,098 | `94abd2a7e7d63e790bfffd3a6e6f4e08ae80a67fbf3dbe8227e754c6104317cb` |
| `Khostty-0.1.0-windows-x86_64-setup.exe` | 19,766,307 | `4070e89e8f693c44abda13da1b718dca4e53d73279f3d945854431d76f095546` |
| `khostty-libghostty-vt-wasm-0.1.0.tar.gz` | 680,598 | `55cfc67572696db9eaf48cb69ae231ca99119aa1caf064e0c08c8c8c178604dc` |
| `khostty-vt_0.1.0_amd64.deb` | 2,320,612 | `3c080d13a74d6bf6dca9d28dc2c685f6b4350ec3130f3f3fafa5cb4d77d834cf` |
| `khostty_0.1.0_amd64.deb` | 18,143,964 | `63d4e6159d65e97db685b9eedbe19c37765f5f838279e9d5b0326ab5a7b80de0` |

The local ignored `dist-release/CHECKSUMS.txt` verifies **9/9** entries with
`shasum -a 256 -c`. The release API's five hash-covered assets plus the
`CHECKSUMS.txt` release asset agree with the already-recorded downloaded hashes
in `docs/sessions/20260927-0.1.0-reverify/README.md`; this refresh queried the
release metadata API but did not redownload those GitHub assets.

## Release automation actually present

`.github/workflows/release-tag.yml` is inherited Ghostty release automation,
not a Khostty distribution pipeline:

1. It starts on a tag matching `v[0-9]+.[0-9]+.[0-9]+`, or manual dispatch
   requiring a version input. The manual `upload` input defaults false.
2. It builds Ghostty's source tarballs and macOS app/DMG, signs source
   tarballs with minisign, codesigns and notarizes the macOS output, generates
   a Sparkle appcast, and stages these artifacts for the inherited
   `ghostty-release` R2 bucket.
3. Its `upload` job runs on tag push, or on manual dispatch only when
   `inputs.upload == 'true'`. The job uploads the listed upstream Ghostty
   objects and stores the generated feed as `appcast-staged.xml`.
4. `.github/workflows/publish-tag.yml` is manual-dispatch only. It checks that
   eight staged upstream Ghostty URLs return HTTP 200, fetches the staged
   appcast, then uploads that feed as `appcast.xml`.

Neither workflow creates Khostty's six GitHub release assets, builds the
Khostty-specific macOS zip / Windows installer / Debian packages / WASM archive,
or publishes Khostty packages. The release-tag workflow has no
`github.repository` guard. Its custom `namespace-profile-ghostty-*` runners
are required. Workflow run history currently has zero runs for both
`release-tag.yml` and `publish-tag.yml`, so neither staged upload nor feed
publication is evidenced as executed for Khostty.

The staged Ghostty object URLs under `release.files.ghostty.org/0.1.0/` returned
HTTP 403 for each checked object during this refresh. Consequently remote R2
object existence, bytes, checksums, and appcast publication are **UNKNOWN**;
the 403 is not evidence of absence. `publish-tag.yml` contains availability
checks but has no content hash comparison or signature/SBOM/provenance check.

## Signing, checksum, SBOM, and provenance findings

- The Khostty Git tag is annotated but unsigned.
- The six GitHub release assets include a checksum manifest. Current local
  verification is 9/9; the Windows installer itself is not a manifest entry
  (the two Windows payload files are).
- The inherited release workflow creates minisign signatures for its two
  Ghostty source archives and codesigns/notarizes the Ghostty macOS products.
  Those signatures do not cover Khostty's six release assets.
- No SBOM or build-provenance attestation appears in either release workflow,
  and none of the six Khostty GitHub release assets is an SBOM or attestation.
- GitHub's release metadata API supplied SHA-256 digests for all six current
  assets. These are remote metadata observations, distinct from independently
  downloading and hashing every asset in this refresh.

## Hosted CI observation

The newest inspected dispatch was CI run `36584839303`, created
`2026-09-29T14:43:47Z` on `a7bce476e184166174c5f252a0bd5aab0f0249e8`, before
current `main` (`666fbf8`). It concluded failure:

- Zig Fmt failed while `mlugg/setup-zig@v1` fetched Zig 0.16.0: configured
  mirrors returned 404/503/502 and the official builds URL returned 404; the
  formatter itself did not run.
- Gitleaks found seven findings in inherited vendor/workflow content in that
  commit. The current main later added a narrow allowlist for seven verified
  false positives (`666fbf8`); this older run does not verify that change.
- Python lint passed; `ci / test` passed. Aggregate lint failed because Zig
  Fmt failed. The macOS build job is disabled (`if: false`) under free-tier
  policy.

No hosted run for current `666fbf8` was returned by the queried workflow-run
API. Treat current hosted CI status as **UNKNOWN**, not green or failed.

## Documentation drift found

`docs/HANDOFF.md` opens with an obsolete 2026-09-18 assertion that no tag,
GitHub release, or registry package exists and that no artifacts are
published. This conflicts with its own later sections and current
`README.md` / `docs/RELEASE.md`: the tag, GitHub release, crates.io crate, and
npm package are published. Its checksum command comment says 8/8 while the
current local manifest reports 9/9. This audit records the conflict without
editing the historical handoff.

## Commands and boundaries

Read-only evidence commands included `git status`, `git log`, `git show-ref`,
`git cat-file`, `git verify-tag`, `git ls-remote`, `gh api` for the release and
workflow-run metadata, `gh run view`, and `shasum -a 256 -c
dist-release/CHECKSUMS.txt`. Workflow bodies were read from the checked-out
files. Remote staged-object probes used HTTP GET and returned 403. No source,
tag, release, workflow, or package was changed by the audit.
