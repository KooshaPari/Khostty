# Ecosystem Handoff — Khostty 0.1.0

**Observed:** 2026-09-18 · **Version:** `0.1.0` · **Source revision:** `7fcb769`

Who this is for: anyone outside this repository who wants to *consume* a Khostty
artifact — as a library, a package, a binary, or a service. It answers three questions
per artifact: how do I get it, what has been verified, and what has **not**.

**First, read this:** nothing in `0.1.0` is published. There is no git tag, no GitHub
release, no crates.io / PyPI / npm / Go-module artifact. See
[RELEASE.md §7](RELEASE.md) for the exact list of actions that have not been taken.

Practical consequence: `dist-release/` is gitignored (`.gitignore` line 42), so
**a fresh clone of this repository contains none of the built artifacts.** A consumer
either receives the files out of band from this host, or rebuilds them — every artifact
has a script that reproduces it.

---

## 1. Pick-up matrix

| Artifact | Path on this host | Published? | Build command | Reproducible? |
|---|---|---|---|---|
| macOS `.app` zip | `dist-release/macos/Khostty-0.1.0-macos.zip` | no | `bash packaging/macos-app.sh` | yes, on macOS |
| Linux library `.deb` | `dist/khostty-vt_0.1.0_amd64.deb` | no | `bash packaging/linux/deb-libvt.sh` | yes, from macOS or Linux |
| WASM npm-style tarball | `dist-release/wasm/khostty-libghostty-vt-wasm-0.1.0.tar.gz` | no | `bash packaging/wasm-dist.sh` | yes, byte-identical from a cold cache |
| Windows PE payload | `dist-release/stage/windows/Khostty-0.1.0-win64/payload/` (`.exe`, `.dll`) | no | cross-build via `packaging/windows/installer.sh` | yes, cross-compile |
| Rust crate | `khostty-vt/` | no | `cd khostty-vt && cargo test` | source tree, in-repo |
| Go module | `khostty-go/` | no | `cd khostty-go && go test ./...` | source tree, in-repo |
| Python package | `khostty-python/` | no | `pip install -e khostty-python` | source tree, in-repo |

Checksums for every built artifact are in
[RELEASE.md §6](RELEASE.md) and `dist-release/CHECKSUMS.txt`. Verify before consuming:

```bash
shasum -a 256 -c dist-release/CHECKSUMS.txt     # 8/8 OK, exit 0, no warnings
```

---

## 2. macOS application

**Get it:** `dist-release/macos/Khostty-0.1.0-macos.zip` (35,953,098 B,
`sha256 94abd2a7…4317cb`), or rebuild with `bash packaging/macos-app.sh` on a macOS
host with Xcode and the Metal Toolchain component.

**Verified (2026-09-18):**
- SHA-256 matches its sidecar `.sha256`, `shasum -c` OK.
- `codesign --verify --deep --strict` → *valid on disk* / *satisfies its Designated
  Requirement*.
- The bundled binary runs non-interactively:
  `Contents/MacOS/ghostty --version` → `Ghostty 1.3.2-main-+41b24baad`, exit 0.

**Unverified:**
- **No GUI session was ever observed.** No window has been seen opening; the bundle was
  never copied outside the source tree and launched. The bundle's own evidence file
  records `launch_verified: NO`.
- **Not notarized.** No Developer ID Application identity and no `notarytool`
  credentials. On another machine Gatekeeper will warn or block until overridden.
- The `.app` is the inherited **macOS/AppKit** runtime. It is not the Windows app.

**Consumer advice:** treat this as "builds, signs, and its binary executes." Do not
treat it as "an app someone has used."

## 3. Linux `.deb`

Two different packages exist in intent; only one exists on disk.

| Package | Contents | State |
|---|---|---|
| `dist/khostty-vt_0.1.0_amd64.deb` | **the `libghostty-vt` library**, headers, pkg-config | **Exists.** 2,320,612 B, `sha256 3c080d13…d834cf` |
| `khostty_0.1.0_amd64.deb` | the GTK **application** | **Does not exist.** Not buildable from macOS |

**Get it:** the library `.deb` from this host, or
`bash packaging/linux/deb-libvt.sh` (any host with `zig` and `dpkg-deb`).

**Verified (recorded 2026-09-18, in `dist-release/evidence/deb-full-build.log`):**
installed and run in an x86-64 Debian 12 container. `dpkg -i` exit 0
(`Status: install ok installed`), `dpkg -V` found no modified or missing files,
`ldconfig -p` resolved the SONAME, the shipped `example/c-vt-formatter` compiled against
the **installed** headers and **installed** `.so` and passed 4/4 VT assertions, and
`dpkg -r` removed it cleanly.

**Unverified:**
- The container is emulated x86-64 userspace, not bare metal.
- No desktop session was involved, so this says nothing about GUI behaviour.
- No `apt`-repository install path was exercised; this is a local `dpkg -i`.
- **No GTK application package exists.** `bash packaging/linux/deb.sh` exits 1 on
  `'adwaita.h' not found` / `'gtk/gtk.h' not found` — GTK4/libadwaita development
  headers for `x86_64-linux-gnu` are absent, and Homebrew's `gtk4` is a macOS-native
  build that cannot supply a Linux sysroot.

**Consumer advice:** usable as a C library by way of a local `.deb`. Not usable as a
Linux terminal application from this release.

## 4. WASM / npm-style package

**Get it:** `dist-release/wasm/khostty-libghostty-vt-wasm-0.1.0.tar.gz` (680,598 B,
`sha256 55cfc675…8604dc`), or `bash packaging/wasm-dist.sh`.

**Verified (recorded 2026-09-18):**
- Sidecar `.sha256` verified with `shasum -a 256 -c` → `OK`, exit 0.
- Freshly extracted to a scratch directory; `node smoke.mjs --json` → 13/13 checks, exit 0.
- A real ESM import of the extracted `js/api.js` opened a terminal and echoed text back.
- `npm install <tarball>` into a clean consumer directory, then an import of the **bare
  specifier** `khostty-libghostty-vt-wasm/api` resolved through the package `exports`
  map → exit 0; VT write with SGR produced `"Green via npm"`; snapshot round-trip matched.
- 54/54 repository WASM tests; 187 exported `ghostty_*` functions; `tsc --strict` with
  `skipLibCheck: false` over the type tests.
- `khostty-vt.wasm` (813,670 B) reproducible byte-identically from a cold cache.

**Unverified:**
- **Node-only.** No browser was ever run. The module is freestanding and
  dependency-free, so Node exercises the same code path a browser would, but
  WebView-specific behaviour is unverified.
- **Kitty graphics is absent by design** (upstream disables it on freestanding targets),
  so 16 of the 203 declared functions are not exported. The conformance suite's
  kitty-gfx case does not apply to this artifact.
- **The tarball provenance gap is closed** (`source_dirty: no`, built 2026-09-18 from
  clean commit `7cd94370e`). An earlier revision was built from a dirty tree; that
  artifact has been superseded by the clean rebuild recorded below.

**Consumer advice:** this is the most consumable artifact in the release. Node ≥ 20.

## 5. Windows PE payload (not an installer)

**Get it:** `dist-release/stage/windows/Khostty-0.1.0-win64/payload/ghostty.exe`
(43,470,336 B, `sha256 df0b4c87…8d03e`) and `ghostty-vt.dll` (7,545,344 B,
`sha256 b4cff87e…5e6654f`).

**Verified:** both are real PE32+ files; hashes match between `zig-out/bin/` and the
staged copies; 198 distinct `ghostty_*` exports in the DLL versus 209 declared in the
headers, with **0 exports undeclared**; the 11-name gap is exactly the 3 `static inline`
helpers in `vt/modes.h` and the 8 `__wasm__`-gated `ghostty_wasm_*` allocators.

**Unverified — and this is the important part:**
- **Never executed on Windows.** No Windows host, `wine` absent, wine casks
  Gatekeeper-disabled, no Rosetta.
- **No installer.** `packaging/windows/installer.sh --probe` reports
  `ISCC.exe: MISSING`; the Inno Setup script was generated but never compiled, so there
  is no `setup.exe`.
- The named-pipe IPC transport is a scaffold returning `error.Unimplemented`, and its
  pipe-path constant is known to be malformed.

**Consumer advice:** you may consume `ghostty-vt.dll` as a *build product* for ABI
planning. You may not consume anything here as a working Windows terminal. The ABI check
proves the *shape* of the API, not runtime behaviour.

## 6. Rust — `khostty-vt`

In-repo crate, not published to crates.io.

```bash
cd khostty-vt && cargo build && cargo test
```

**Verified:** re-executed for this document on 2026-09-18 — **199/199 tests pass**
(195 across 10 unit/integration targets + 4 doc-tests), 0 failed. Independent
verification of the Rust gate's recorded figure.

**Unverified / caveats:**
- Not on crates.io. A consumer must vendor the directory or use a path/git dependency.
- The crate depends on a built `libghostty-vt`; `build.rs` discovers it. See
  `packaging/` for producing the library.
- Not part of a tagged release, so there is no versioned artifact to pin beyond the
  in-tree `Cargo.toml` version `0.1.0`.

## 7. Go — `khostty-go`

In-repo module (`github.com/KooshaPari/Khostty/khostty-go`), not published.

```bash
cd khostty-go && go build ./... && go vet ./... && go test ./...
```

**⚠ Discrepancy found 2026-09-18.** The WBS G6 evidence row records `go test ./...` →
45 pass. Re-running it on this host today **fails at link**:

```
/usr/local/go/pkg/tool/darwin_arm64/link: running clang failed: exit status 1
ld: multiple errors: tapi error: malformed file
  .../MacOSX27.0.sdk/usr/lib/libresolv.9.tbd:4:20: error: unknown architecture
  arm64e.x1-macos ...
FAIL  github.com/KooshaPari/Khostty/khostty-go [build failed]
```

The cause is a toolchain/SDK mismatch, not Khostty source: Apple clang 17.0.0
(clang-1700.3.19.1, Command Line Tools for Xcode 26.0) cannot parse the `arm64e.x1-macos`
architecture token in the MacOSX27.0 SDK `.tbd` stubs. **This does not retroactively
invalidate the recorded 45-pass run**, but the claim is **not reproducible on this host
today** and must not be restated as current until it is re-run on a working toolchain.

**Verified:** the failure is at link, after successful compilation of the cgo bindings —
so the Go *source* compiles today.
**Unverified:** the 45-test pass itself, on this host, as of 2026-09-18.

## 8. Python — `khostty-python`

In-repo package, not published to PyPI.

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -e khostty-python && pytest khostty-python
```

**Verified:** the WBS G6 evidence records `ruff` clean, 162 pytest cases pass, both
examples run, and install verified as editable, wheel, and sdist in fresh venvs, with
`validate_abi()` returning empty diff maps against the linked library.

**Re-verified 2026-09-18 for this document**, using `uv` with Python 3.12 against an
isolated environment:

```console
$ uv pip install -e . pytest && uv run python -m pytest -q
162 passed in 1.26s
```

An earlier attempt with the system interpreter (Python 3.9.6, pip 21.2.4) was
inconclusive: that pip predates PEP 660 editable installs and refused
`pip install -e .`, and `pytest` was never installed, so the run reported
`ImportError` for every test. That failure was environmental, not a package defect —
proved by the same suite passing 162/162 under Python 3.12.

**Caveats:** not on PyPI; a consumer vendors the directory. `requires-python` is
declared as `>=3.8` but only 3.12 was exercised here.

---

## 9. What a consumer should and should not trust

Trust today:

- **The WASM package** — extracted, smoke-tested, and imported through a real `npm
  install` + bare-specifier path.
- **The `libghostty-vt` library `.deb`** — installed and exercised on x86-64 Debian 12.
- **The Rust crate** — 199/199 tests re-verified 2026-09-18.
- **The checksums** — recomputed 2026-09-18, all match, none discrepancy.

Do not trust today:

- **Anything Windows as a running program.**
- **The macOS `.app` as a usable application** — signed and executable, never launched
  in a GUI, not notarized.
- **The GTK Linux application** — it does not exist for this release.
- **Any performance claim** — no baseline, one run under load 425, dirty tree.
- **The IPC surface as a live service** — 458 module tests pass, including over real
  sockets, but the server is not started from the application and the app-thread hop is
  not wired. Nothing listens in a running Khostty.

## 10. Next bounded task

**Completed 2026-09-18: the WASM distribution was rebuilt from a clean tree.**

```bash
git status --porcelain          # empty (tracked tree clean)
bash packaging/wasm-dist.sh     # exit 0
# khostty-version.json -> source_dirty: "no", source_commit 7cd94370ebdf8dc151a9253974271d281af150b3
# tarball 680,598 B, sha256 55cfc67572696db9eaf48cb69ae231ca99119aa1caf064e0c08c8c8c178604dc
```

Executed evidence: WASM suite 54 passed / 0 failed against the rebuilt module; the
repack was **byte-identical** (`55cfc675…` both times); extracted-tarball consumer smoke
test 13/13, exit 0; sidecar `shasum -a 256 -c` → OK. The artifact is now attributable
to a clean commit. Hash updated in [RELEASE.md §6](RELEASE.md), `docs/INSTALL.md`, the
changelog, and `dist-release/CHECKSUMS.txt`.

**New next bounded task: close the Windows runtime gap on a Windows host (or a host with
a working x86_64 Windows emulation layer).** It is the only remaining artifact whose
*runtime* behaviour is unverified. Acceptance: `ghostty.exe` launches on Windows and
`ghostty-vt.dll` loads, with the 198 exported symbols callable. This host cannot do it:
no Windows host, no `wine` (all Homebrew casks Gatekeeper-disabled since 2026-09-01),
and no Rosetta for x86_64 emulation. The ABI *shape* is already verified statically
(see [RELEASE.md §6](RELEASE.md)), so only runtime behaviour is outstanding.

**Blocked on authorization (not on capability):** WBS 10.5 (publish FFI packages),
10.6 (create the GitHub release), 10.8 (announce), and creating the `v0.1.0` tag.
See [RELEASE.md §7](RELEASE.md).

---

## See also

- [RELEASE.md](RELEASE.md) — version scheme, cut-a-release commands, checksum manifest
- [INSTALL.md](INSTALL.md) — per-artifact install and verification, with status vocabulary
- [changelog/0.1.0.md](changelog/0.1.0.md) — release notes and known issues
- [PLATFORMS.md](PLATFORMS.md) — support matrix per platform
- [FORK.md](FORK.md) — what the fork claims and what the evidence does not support
- [dossiers/KHOSTTY.md](dossiers/KHOSTTY.md) — product dossier
- Deep WBS: [`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](sessions/20260916-fork-assessment/02_DEEP_WBS.md)
