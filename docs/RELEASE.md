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

## 4. Tag naming — documented, not created

The tag a maintainer **would** create for this version is:

```
v0.1.0
```

`v` prefix, then the `major.minor.patch` from `packaging/version.sh --print`. The
prerelease (`-dev`) and the build metadata (`+ghostty.…`) are deliberately **not**
part of the tag name: the tag names the release, and the metadata is recorded in the
release notes and the checksum manifest instead.

**This tag does not exist.** Verified on 2026-09-18:

```console
$ git rev-parse --verify --quiet v0.1.0 && echo EXISTS || echo "v0.1.0 DOES NOT EXIST"
v0.1.0 DOES NOT EXIST
$ git tag -l 'v0.1.0'
        # (no output)
```

The existing `v*` tags in this repository (`v1.0.0` … `v1.3.x`) are inherited from
upstream Ghostty and are unrelated to Khostty's own version line. Creating `v0.1.0`
is a publishing action and is **not** part of this document's scope — see §7.

## 5. Cutting a release — exact commands

Every command below is the maintainer's sequence. Commands marked **DO NOT RUN
YET** are listed for completeness because they publish; no step in this section was
executed as part of writing this document.

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
| GTK application `.deb` | Linux | GTK4 + libadwaita dev headers for the target | **not buildable from macOS** (see §6) |
| Windows installer | Windows | `zig`, Inno Setup 6.3+ (`ISCC.exe`) | no — payload builds anywhere, installer does not |

## 6. Artifact verification manifest

Every hash below was **recomputed on 2026-09-18 with `shasum -a 256`** on this host.
The machine-readable copy lives at `dist-release/CHECKSUMS.txt`; it is reproduced
inline here because `dist-release/` is gitignored (`.gitignore` line 42: `/dist-release/`),
so the file itself is not versioned.

### 6.1 Manifest — recomputed 2026-09-18

```
94abd2a7e7d63e790bfffd3a6e6f4e08ae80a67fbf3dbe8227e754c6104317cb  dist-release/macos/Khostty-0.1.0-macos.zip
55cfc67572696db9eaf48cb69ae231ca99119aa1caf064e0c08c8c8c178604dc  dist-release/wasm/khostty-libghostty-vt-wasm-0.1.0.tar.gz
3c080d13a74d6bf6dca9d28dc2c685f6b4350ec3130f3f3fafa5cb4d77d834cf  dist/khostty-vt_0.1.0_amd64.deb
df0b4c8772ad5de8c65078cf0ade6645ad16601b1b4ca37097e314abf028d03e  zig-out/bin/ghostty.exe
b4cff87e6ee95dd97e0872fdaf752122aceb4f7536662f6ceadf3905eae6654f  zig-out/bin/ghostty-vt.dll
08ac8ed881ffdae68b9f96f9afa6c834e57ba7ea49280d220e882938508e5bf6  dist-release/wasm/verify/khostty-libghostty-vt-wasm-0.1.0/khostty-vt.wasm
```

### 6.2 Per-artifact status, with executed checks

| # | Artifact | Bytes | Built | Status (2026-09-18) | Check executed here |
|---|---|---|---|---|---|
| 1 | `dist-release/macos/Khostty-0.1.0-macos.zip` | 35,953,098 | 2026-09-18 05:13 | **MATCH** | `shasum -a 256` → `94abd2a7…4317cb`. Matches the sidecar `.sha256` written beside it, matches the value recorded in `dist-release/macos/EVIDENCE.txt`, and matches `docs/INSTALL.md`. `codesign --verify --deep --strict` → *valid on disk*; bundled binary `--version` → exit 0. **Not notarized** (no `notarytool` credentials) and **no GUI session was observed**. |
| 2 | `dist-release/wasm/khostty-libghostty-vt-wasm-0.1.0.tar.gz` | 680,598 | 2026-09-17 07:19 | **MATCH** | `shasum -a 256` → `55cfc675…8604dc`; sidecar verified with `shasum -a 256 -c` → `OK`, exit 0. Inner `khostty-vt.wasm` hash matches its own sidecar. |
| 3 | `dist/khostty-vt_0.1.0_amd64.deb` | 2,320,612 | 2026-09-18 05:07 | **MATCH** | `shasum -a 256` → `3c080d13…d834cf`, matching the value recorded in `docs/INSTALL.md` and the WBS G9.12 evidence row. Installed-and-run evidence lives in `dist-release/evidence/deb-full-build.log`. |
| 4 | `zig-out/bin/ghostty.exe` | 43,470,336 | 2026-09-18 01:23 | **HASHED, NOT EXECUTED** | `shasum -a 256` → `df0b4c87…8d03e`. Identical to the staged copy at `dist-release/stage/windows/Khostty-0.1.0-win64/payload/ghostty.exe`. `file` → `PE32+ executable (GUI) x86-64`. **Never run**: macOS cannot execute PE binaries, `wine` is absent, and every Homebrew wine cask is disabled by Gatekeeper. |
| 5 | `zig-out/bin/ghostty-vt.dll` | 7,545,344 | 2026-09-18 01:22 | **HASHED, NOT EXECUTED** | `shasum -a 256` → `b4cff87e…5e6654f`. Same hash as the staged copy. `file` → `PE32+ executable (DLL)`; ABI shape checked statically (198 exports, 0 undeclared). **Never run.** |
| 6 | `khostty-vt.wasm` (inside the WASM dist) | 813,670 | 2026-09-16 | **MATCH** | Hash matches `khostty-vt.wasm.sha256` inside the extracted package. |

**Result: all recomputed hashes match the values expected for this build. No
discrepancy was found.** Five of the six rows are build-product or packaging checks;
row 1's signature check and rows 2/6's smoke evidence are runtime checks. Rows 4 and 5
have no runtime check anywhere in this repository's evidence.

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

## 7. What this document does not authorize

This document defines the scheme and lists the commands. It performs **no** publishing
action, and running it does not either:

- **No git tag** is created. `v0.1.0` does not exist.
- **No push**, to any remote, of any branch or tag.
- **No GitHub release** and no asset upload.
- **No package published** to crates.io, PyPI, the Go module proxy, or npm.
- **No deployment** of any kind.

Those are the WBS G10 tasks **10.5** (publish FFI packages), **10.6** (create the
GitHub release), and **10.8** (announce), and they remain **NOT STARTED** pending
explicit publish authorization. The WBS rows record this.

---

## See also

- [INSTALL.md](INSTALL.md) — per-artifact install and verification, with the status vocabulary
- [BUILD.md](BUILD.md) — producing each artifact from source
- [PLATFORMS.md](PLATFORMS.md) — per-platform support matrix
- [changelog/0.1.0.md](changelog/0.1.0.md) — the release notes for this version
- [HANDOFF.md](HANDOFF.md) — how a consumer picks up each artifact
- [`packaging/version.sh`](../packaging/version.sh) — the normative scheme
- Deep WBS: [`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](sessions/20260916-fork-assessment/02_DEEP_WBS.md)
