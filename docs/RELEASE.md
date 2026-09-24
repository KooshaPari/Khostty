# Releasing Khostty

**Observed:** 2026-09-18 · **Version:** `0.1.0` (`-dev` prerelease) · **Source revision:** `7fcb769`

This document is the release procedure for the Khostty fork: the version scheme, how
the version number is *derived* rather than declared, what `0.1.0` means, the exact
commands a maintainer runs to cut a release, and the checksum manifest of the
artifacts as they exist on this host.

Three rules, the same ones [INSTALL.md](INSTALL.md) uses:

1. **Every claim carries its observation date.** A hash verified yesterday is not
   verified today, and this repository is under concurrent edit.
2. **Nothing is called VERIFIED unless the check was executed on this host and the
   command is shown.** Where a check cannot run here, the row says so and names the
   missing tool or host rather than implying the step is merely untested.
3. **`packaging/version.sh` is the authority for the version number.** This document
   never restates a version by hand where a script can answer.

---

## 1. Version scheme

```
<major>.<minor>.<patch>[-<pre>][+ghostty.<upstream-base-version>.<base-sha7>]
```

| Field | Meaning |
|---|---|
| `major.minor.patch` | SemVer 2.0.0 for the **Khostty** deliverable, not for upstream Ghostty. |
| `-<pre>` | Optional prerelease tag (`-rc.1`, `-dev`). Sorts below the matching release. |
| `+ghostty.<...>` | Build metadata naming the upstream commit the fork sits on. SemVer ignores build metadata for precedence, so it never changes how the version sorts. |

Khostty versions itself independently of the Ghostty release it tracks. A string like
`0.1.0+ghostty.1.3.2-dev.d4c88d8` reads: *Khostty 0.1.0, based on upstream Ghostty
1.3.2-dev at commit `d4c88d8`.*

The scheme is implemented in [`packaging/version.sh`](../packaging/version.sh). The
comment block at the top of that script is the normative description; this section
restates it so a reader does not have to open the script to understand a tag.

## 2. Where the version comes from — one source of truth

**`build.zig` line 11: `const lib_version = "0.1.0-dev";`** is the single source of
truth. `packaging/version.sh` reads that value and splits it:

```
"0.1.0-dev"  →  KHOSTTY_VERSION = "0.1.0",  KHOSTTY_PRERELEASE = "dev"
"0.1.0"      →  KHOSTTY_VERSION = "0.1.0",  KHOSTTY_PRERELEASE = ""
```

The same value becomes the shared-library SONAME (`libghostty-vt.0.1.0.dylib` /
`.so`), so the ABI number cannot drift from the release number: one edit to
`lib_version` moves both.

Two cross-manifest copies exist and must agree, or the release is inconsistent:

| Manifest | Value | Checked by |
|---|---|---|
| `build.zig` `lib_version` | `0.1.0-dev` → **0.1.0** | authority |
| `khostty-vt/Cargo.toml` `version` | `0.1.0` | `packaging/version.sh` agreement check |
| `khostty-python/pyproject.toml` `version` | `0.1.0` | `packaging/version.sh` agreement check |

`build.zig.zon` holds upstream Ghostty's version (`1.3.2-dev`), not Khostty's. It is
the source for the `+ghostty.<version>` build metadata, not for the release number.

Ask the script rather than trusting this table:

```bash
bash packaging/version.sh           # human-readable block + agreement check
bash packaging/version.sh --json    # machine-readable, for a manifest
bash packaging/version.sh --print   # just the version, no newline noise
```

Executed here on 2026-09-18 (`bash packaging/version.sh --human`):

```
Khostty version        0.1.0 (dev)
  from                 build.zig lib_version = "0.1.0-dev"
  ABI soname           libghostty-vt.0.1.0
Upstream base          ghostty 1.3.2-dev @ d4c88d8 (2026-09-15)
Source revision        7fcb769 (dirty: no)
```

The agreement check printed no warning, so `Cargo.toml` and `pyproject.toml` match
`0.1.0`.

## 3. What `0.1.0` means

**`0.x` means the agent-facing surfaces are not frozen.**

Pre-1.0 SemVer allows breaking changes in a *minor* bump. In this fork the two
surfaces that are explicitly unstable are:

- **IPC v1** — the line-delimited JSON agent protocol in `src/apprt/ipc/`. The
  normative spec is [`src/apprt/ipc/protocol.md`](../src/apprt/ipc/protocol.md); it
  carries an integer version check and states its own v1 non-goals.
- **The polyglot bindings** — `khostty-vt` (Rust), `khostty-go` (Go),
  `khostty-python` (Python), and `@khostty/libghostty-vt-wasm`. The type-manifest
  contract that lays out structs is stable in method but may change in shape.

What is *not* claimed by `0.1.0`:

- No API or ABI freeze. The C ABI under `include/ghostty/vt/` is inherited from
  upstream, but the wrapper surfaces above may break between `0.1.x` releases.
- No performance claim. See [FORK.md §4](FORK.md#4-what-the-evidence-does-not-support).
- No general-availability claim for the Windows or Linux GTK applications. See
  [INSTALL.md](INSTALL.md) and §6 below for the per-artifact status.

## 4. Tag naming — created 2026-09-24

The tag for this version is:

```
v0.1.0
```

`v` prefix, then the `major.minor.patch` from `packaging/version.sh --print`. The
prerelease (`-dev`) and the build metadata (`+ghostty.…`) are deliberately **not**
part of the tag name: the tag names the release, and the metadata is recorded in the
release notes and the checksum manifest instead.

**This tag now exists.** Created 2026-09-24 01:58 -0700 and pushed to origin:

```console
$ git for-each-ref refs/tags/v0.1.0 --format='%(taggerdate:iso8601) | %(objectname:short)'
2026-09-24 01:58:06 -0700 | 7e1684f60
$ git rev-list -n1 v0.1.0
202aad5438c24ae0c76122e5b446d3bd774a61ca
```

(A check on 2026-09-18 correctly found no tag; that observation is historical.)

The existing `v*` tags in this repository (`v1.0.0` … `v1.3.x`) are inherited from
upstream Ghostty and are unrelated to Khostty's own version line. Creating `v0.1.0`
is a publishing action; it was **executed on 2026-09-24 under the §7 authorization**.

## 5. Cutting a release — exact commands

Every command below is the maintainer's sequence. Commands marked **DO NOT RUN
YET** are listed for completeness because they publish. **[Updated 2026-09-24]**
Under the §7 authorization, the tag/push step and the crates.io leg of the package
step have since been executed; §7 carries the per-step state.

```bash
# 0. Resolve the version. If this is wrong, stop: everything downstream is wrong.
bash packaging/version.sh

# 1. Confirm the tree is clean and note the revision that will be tagged.
git status --porcelain          # expect no output
git rev-parse HEAD              # record this; the manifest carries it

# 2. Build each artifact from the SAME revision, on its required host.
bash packaging/wasm-dist.sh                     # any host: Node >= 20, zig 0.16.0
bash packaging/linux/deb-libvt.sh               # any host with dpkg-deb (library .deb)
bash packaging/macos-app.sh                     # macOS host: Xcode + Metal Toolchain
bash packaging/windows/installer.sh             # Windows host with Inno Setup (ISCC.exe)

# 3. Recompute every hash and write the manifest.
shasum -a 256 dist-release/macos/Khostty-0.1.0-macos.zip
shasum -a 256 dist-release/wasm/khostty-libghostty-vt-wasm-0.1.0.tar.gz
shasum -a 256 dist/khostty-vt_0.1.0_amd64.deb
shasum -a 256 zig-out/bin/ghostty.exe zig-out/bin/ghostty-vt.dll

# 4. Verify what can be verified, per artifact (see §6 for per-artifact status).
(cd dist-release/wasm && shasum -a 256 -c khostty-libghostty-vt-wasm-0.1.0.tar.gz.sha256)

# 5. Write the release notes.
#    docs/changelog/<version>.md   — e.g. docs/changelog/0.1.0.md

# 6. Commit the docs, then tag.        # DO NOT RUN YET — publishing
# git tag -a v0.1.0 -m "Khostty 0.1.0"
# git push origin v0.1.0
```

Probe any packaging script before trusting it on a new host; probes report readiness
and change nothing:

```bash
bash packaging/macos-app.sh --probe
bash packaging/linux/deb.sh --probe
bash packaging/linux/deb-libvt.sh --probe
bash packaging/windows/installer.sh --probe
```

### Build-host requirements, per artifact

| Artifact | Build host | Tools | Blocks release if absent |
|---|---|---|---|
| WASM tarball | macOS or Linux | `zig` 0.16.0, `node`, `tar`, `gzip` | yes |
| macOS `.app` zip | macOS | `zig`, Xcode, **Metal Toolchain component** | yes, for the macOS artifact |
| `libghostty-vt` `.deb` | macOS or Linux — cross-compiles | `zig`, `dpkg-deb` | yes, for the Linux library artifact |
| GTK application `.deb` | Linux (native x86_64) | GTK4 + libadwaita dev headers for the host | **built in WSL Fedora 44, 2026-09-19** (`9daf736e8` + `45e6d086b`); still not buildable from macOS (see §6) |
| Windows installer | Windows | `zig`, Inno Setup 6.3+ (`ISCC.exe`) | **yes, as of 2026-09-19** — compiled with Inno Setup 6.7.1 on `kooshapari-desk` and install-verified (`4070e89e…095546`) |

## 6. Artifact verification manifest

Every hash below was **recomputed on 2026-09-18 with `shasum -a 256`** on this host.
The machine-readable copy lives at `dist-release/CHECKSUMS.txt`; it is reproduced
inline here because `dist-release/` is gitignored (`.gitignore` line 42: `/dist-release/`),
so the file itself is not versioned.

### 6.1 Manifest — recomputed 2026-09-18; GTK .deb row added 2026-09-19, superseded by the install-verified rebuild same day

```
94abd2a7e7d63e790bfffd3a6e6f4e08ae80a67fbf3dbe8227e754c6104317cb  dist-release/macos/Khostty-0.1.0-macos.zip
55cfc67572696db9eaf48cb69ae231ca99119aa1caf064e0c08c8c8c178604dc  dist-release/wasm/khostty-libghostty-vt-wasm-0.1.0.tar.gz
3c080d13a74d6bf6dca9d28dc2c685f6b4350ec3130f3f3fafa5cb4d77d834cf  dist/khostty-vt_0.1.0_amd64.deb
df0b4c8772ad5de8c65078cf0ade6645ad16601b1b4ca37097e314abf028d03e  zig-out/bin/ghostty.exe
b4cff87e6ee95dd97e0872fdaf752122aceb4f7536662f6ceadf3905eae6654f  zig-out/bin/ghostty-vt.dll
08ac8ed881ffdae68b9f96f9afa6c834e57ba7ea49280d220e882938508e5bf6  dist-release/wasm/verify/khostty-libghostty-vt-wasm-0.1.0/khostty-vt.wasm
63d4e6159d65e97db685b9eedbe19c37765f5f838279e9d5b0326ab5a7b80de0  dist-release/khostty_0.1.0_amd64.deb
```

The last row was computed in WSL Fedora 44 on `kooshapari-desk` (`sha256sum`, exit
0), staged beside a sidecar `.sha256`, and copied here; it is the GTK application
`.deb` built 2026-09-19 (see §6.2 row 7). It supersedes the first same-day build
(`209ba5ed…713a`), whose stale `libc6 (>= 2.17)` dependency let `dpkg -i` install
onto glibc 2.36 with the binary then failing at load.

### 6.2 Per-artifact status, with executed checks

| # | Artifact | Bytes | Built | Status (2026-09-18) | Check executed here |
|---|---|---|---|---|---|
| 1 | `dist-release/macos/Khostty-0.1.0-macos.zip` | 35,953,098 | 2026-09-18 05:13 | **MATCH** | `shasum -a 256` → `94abd2a7…4317cb`. Matches the sidecar `.sha256` written beside it, matches the value recorded in `dist-release/macos/EVIDENCE.txt`, and matches `docs/INSTALL.md`. `codesign --verify --deep --strict` → *valid on disk*; bundled binary `--version` → exit 0. **Not notarized** (no `notarytool` credentials); GUI session + interactive keystroke round-trip verified 2026-09-20. |
| 2 | `dist-release/wasm/khostty-libghostty-vt-wasm-0.1.0.tar.gz` | 680,598 | 2026-09-18 06:12 | **MATCH** | `shasum -a 256` → `55cfc675…8604dc`; sidecar verified with `shasum -a 256 -c` → `OK`, exit 0. Inner `khostty-vt.wasm` hash matches its own sidecar. (This row previously read `2026-09-17 07:19`, the superseded dirty-tree build; the tarball was repacked 2026-09-18 as recorded in §6.3.) |
| 3 | `dist/khostty-vt_0.1.0_amd64.deb` | 2,320,612 | 2026-09-18 05:07 | **MATCH** | `shasum -a 256` → `3c080d13…d834cf`, matching the value recorded in `docs/INSTALL.md` and the WBS G9.12 evidence row. Installed-and-run evidence lives in `dist-release/evidence/deb-libvt-verify.log` (`deb-full-build.log` is the *GTK application* build attempt, which fails on missing headers). |
| 4 | `zig-out/bin/ghostty.exe` | 43,470,336 | 2026-09-18 01:23 | **EXECUTED 2026-09-19** | `shasum -a 256` → `df0b4c87…8d03e`; re-verified byte-identical on the Windows host. Identical to the staged copy at `dist-release/stage/windows/Khostty-0.1.0-win64/payload/ghostty.exe`. `file` → `PE32+ executable (GUI) x86-64`. **Run** on `kooshapari-desk` (Windows NT 10.0.28120, AMD64): `+version` → exit 0, `app runtime: .windows`, `font engine: .freetype_windows`, `libxev: iocp`, build mode `.Debug`. CLI action only — no GUI window launched. |
| 5 | `zig-out/bin/ghostty-vt.dll` | 7,545,344 | 2026-09-18 01:22 | **EXECUTED 2026-09-19** | `shasum -a 256` → `b4cff87e…5e6654f`; same hash as the staged copy. `file` → `PE32+ executable (DLL)`; ABI shape checked statically (198 exports, 0 undeclared). **Loaded and driven live** on `kooshapari-desk`: `ghostty_terminal_new` rc 0, `get COLS/ROWS` 80/24, `resize(100,40)` → 100/40, `vt_write` + OSC-0 → `CURSOR_Y` 1 / `TITLE` `Khostty-Win`, `VT_GROUND` 1, `terminal_free` clean; `ghostty_build_info(SIMD)` rc 0. 0 failures. |
| 6 | `khostty-vt.wasm` (inside the WASM dist) | 813,670 | 2026-09-16 (binary; packaged 2026-09-18) | **MATCH** | Hash matches `khostty-vt.wasm.sha256` inside the extracted package. |
| 7 | `dist-release/khostty_0.1.0_amd64.deb` (GTK application, staged copy) | 18,143,964 | 2026-09-19 (WSL Fedora 44) | **INSTALL-VERIFIED (host)** | Built natively in WSL after three blocker fixes (`9daf736e8` conditional target, `45e6d086b` hicolor icons + `Icon=@APPID@`, `65de471df` glibc floor derived from the binary: `libc6 (>= 2.43)`). **Installed on the WSL host (glibc 2.43, dpkg db via `--force-depends`):** `dpkg -s` → `install ok installed`; `dpkg -V` clean; `dpkg -L` lists the binary, `.desktop`, metainfo, 6 hicolor PNGs; `ldd` all resolved; `desktop-file-validate` OK; metainfo well-formed; installed `/usr/bin/khostty +version` → exit 0; `gio info` readable; `dpkg --purge` clean, 0 residuals. **Negative control (bookworm glibc 2.36 container):** unpack ok, configure REFUSED on the 2.43 floor. CLI build check: `+version` → exit 0, `app runtime: .gtk`, `fontconfig_freetype`, `io_uring`. Evidence `sessions/20260916-fork-assessment/evidence/gtk_deb_install_2026-09-19.txt` (250 lines). GUI launch not attempted (no desktop session on the WSL host) — that half is open. |

**Result: all recomputed hashes match the values expected for this build. No
discrepancy was found.** Five of the six rows are build-product or packaging checks;
row 1's signature check and rows 2/6's smoke evidence are runtime checks. **Rows 4 and 5
now have a runtime check too (2026-09-19):** both were executed on the Windows runner
`kooshapari-desk`, with `ghostty.exe +version` exiting 0 and `ghostty-vt.dll` driven
through its live terminal ABI (0 failures). Raw log:
`sessions/20260916-fork-assessment/evidence/windows_runtime_verify_2026-09-19.txt`. Caveat: the `ghostty.exe`
run was the CLI `+version` action, so no GUI window was launched. **Row 7 (added
2026-09-19) carries build-product, CLI runtime, and full dpkg install-verify
checks:** the install-verify ran on the WSL Fedora 44 host (glibc 2.43) and its
negative control refused on Debian 12 (glibc 2.36); the GUI-launch half is open
(no desktop session on the WSL host).

### 6.3 Manifest metadata

| Field | Value |
|---|---|
| Version | `0.1.0` (source value `0.1.0-dev`) |
| ABI soname | `libghostty-vt.0.1.0` |
| Upstream base | ghostty `1.3.2-dev` @ `d4c88d8069912b653d707191388ca98e24751f12` (2026-09-15) |
| Source revision at manifest time | `7fcb7691638ee0396cd30ad61ca6c6c779e0a362` (`7fcb769`), dirty: no |
| macOS bundle source revision | `41b24baad24227e22fefc35ae74ee5999f3591d1` (`41b24baa`) |
| WASM package recorded revision | `7cd94370ebdf8dc151a9253974271d281af150b3` (`7cd94370e`), **dirty: no** |

**Updated 2026-09-18:** this row previously read `7585c498…`, **dirty: yes**. The WASM
dist was rebuilt from a clean tracked tree, so the artifact is now attributable to a
commit. `khostty-version.json` records `source_dirty: "no"`; the rebuild was verified by
a 54/54 repository suite run, a byte-identical repack, and a 13/13 extracted-tarball
consumer check. The superseded hash `ce5d1f1d…` no longer appears in this document.

## 7. Publish authorization and execution state

Authorization for the G10 publish path ("do it all") was granted by the operator.
Execution state as of 2026-09-24:

| Step | State |
|---|---|
| Git tag `v0.1.0` | **DONE** — annotated tag at `202aad543`, pushed to origin (tag object `7e1684f6`) |
| crates.io `khostty-vt` 0.1.0 | **PUBLISHED** 2026-09-20 — API-verified: `newest_version=0.1.0`, downloaded-crate checksum matches the local `.crate`, `published_by KooshaPari`; 199/199 tests passed first |
| PyPI `khostty-vt` | **BLOCKED — no credential exists on this machine** (no `.pypirc`, keyring entry, env var, netrc, or OIDC trusted publishing). Wheel + sdist are prebuilt in `khostty-python/dist/`; `uv publish` runs as soon as an operator-provided token exists. Package name is free. |
| npm `khostty-libghostty-vt-wasm` | **PUBLISHED 2026-09-24** — the stored token had been revoked; recovery was a fresh `/opt/homebrew/bin/npm login --auth-type=web` plus one browser 2FA approval, then `npm publish`. `npm view` returns `0.1.0` with `dist.shasum 2754b0a423ee035b421dc232ceb6f8fc6c85b57d` — byte-match to the staged package (27 files, 324.6 kB) — published 2026-09-24T10:47:28Z. |
| Go module proxy | Not applicable to 0.1.0 (the Go module is scaffold only, G6.1) |
| GitHub release + 6 assets | **PENDING OPERATOR APPROVAL** — `gh release create` was deferred to the phinbox gate (`request_id=hook-a683332d46ba9fff95e5a91b0f239118`) and must be approved there, then re-run as written in §7.1 |
| Announce (10.8) | **DOCS UPDATED 2026-09-24** — README release banner + status tables, changelog §4.2 GUI-verification correction, INSTALL/HANDOFF/PLATFORMS stale-status fixes; commit + push follow in the same change |

The one **security-relevant publish caveat** worth restating: `khostty-vt` documents,
rather than vendors, its prebuilt `libghostty-vt` dependency — the crate README
spells out `GHOSTTY_VT_LIB_DIR` / the `link` feature and warns that without a
prebuilt library it typechecks but does not link. That is the resolution of open
decision 1 below; it shipped with the 2026-09-20 publish.

### 7.1 The publish runbook (partially executed)

Staged and rehearsed 2026-09-19; **step 1 executed**, crates.io leg of step 2
executed 2026-09-20. The remainder is ready to run once its blockers clear:

```bash
# 0. Preconditions (verified 2026-09-19; tag now exists)
git tag -l 'v0.1.0'             # v0.1.0 — exists (DONE)

# 1. Publish the commits and the tag                 [DONE]
git push origin main
git tag -a v0.1.0 -m "Khostty 0.1.0"                # already created
git push origin v0.1.0                              # pushed, verified [new tag]

# 2. Publish the packages  (ORDER MATTERS: run cargo test BEFORE any dry run)
#    Each line leaves the shell in the directory it enters, so step 3 returns to
#    the repository root explicitly before naming any relative path.
cd khostty-vt      && cargo test && cargo publish   # DONE 2026-09-20 (199/199, published)
cd ../khostty-python && uv publish dist/khostty_vt-0.1.0-py3-none-any.whl dist/khostty_vt-0.1.0.tar.gz   # BLOCKED: needs PyPI token
cd ../dist-release/wasm/stage/khostty-libghostty-vt-wasm-0.1.0 && npm publish   # DONE 2026-09-24 (after web re-login + browser 2FA)

# 3. GitHub release with artifacts + checksums      # PENDING phinbox approval
#    (6 assets; hook-a683332d46ba9fff95e5a91b0f239118)
cd "$(git rev-parse --show-toplevel)"   # step 2 left the shell in the npm stage dir
gh release create v0.1.0 \
  --title "Khostty 0.1.0" \
  --notes-file docs/changelog/0.1.0.md \
  dist-release/macos/Khostty-0.1.0-macos.zip \
  dist-release/wasm/khostty-libghostty-vt-wasm-0.1.0.tar.gz \
  dist/khostty-vt_0.1.0_amd64.deb \
  dist/khostty_0.1.0_amd64.deb \
  dist-release/stage/windows/Khostty-0.1.0-win64/output/Khostty-0.1.0-windows-x86_64-setup.exe \
  dist-release/CHECKSUMS.txt
```

Two open decisions, recorded in [HANDOFF.md §6](HANDOFF.md) and the WBS 10.5 row:

1. **`khostty-vt` cannot link standalone** — **RESOLVED for 0.1.0**: the crate ships
   with a README that documents the prebuilt `libghostty-vt` requirement
   (`GHOSTTY_VT_LIB_DIR`, the `link` feature, and the "typechecks but will not link"
   warning); published on that basis 2026-09-20.
2. **The macOS `.app` is not notarized** — **still open.** The bundle was built,
   signed, hash-verified, its binary executed non-interactively, **and it was launched
   in a live GUI session with an interactive keystroke round-trip on 2026-09-20**
   ([HANDOFF.md](HANDOFF.md) §2). With no `notarytool` credentials available, a first
   launch on a pristine machine may still require an explicit Gatekeeper override;
   that path remains untested.

---

## See also

- [INSTALL.md](INSTALL.md) — per-artifact install and verification, with the status vocabulary
- [BUILD.md](BUILD.md) — producing each artifact from source
- [PLATFORMS.md](PLATFORMS.md) — per-platform support matrix
- [changelog/0.1.0.md](changelog/0.1.0.md) — the release notes for this version
- [HANDOFF.md](HANDOFF.md) — how a consumer picks up each artifact
- [`packaging/version.sh`](../packaging/version.sh) — the normative scheme
- Deep WBS: [`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](sessions/20260916-fork-assessment/02_DEEP_WBS.md)
