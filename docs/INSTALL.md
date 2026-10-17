# Installing Khostty

**Observed:** 2026-10-17 · **Version:** `0.1.0` · **Source revision:** `main` HEAD (post-Phase-0 merge at `ebc033eba`)

This is the install counterpart to [`BUILD.md`](BUILD.md). BUILD.md answers
*"how do I compile this?"*. This document answers *"how do I install the
result, and how do I prove the install actually worked?"*.

The three rules below govern every claim in this document:

1. **Every status carries its observation date.** A pass observed yesterday is
   not a pass observed today, and this repository is under concurrent edit.
2. **Nothing is marked VERIFIED unless the check was executed on this host.**
   Where a step needs a host this machine is not, the row says so and names the
   missing tool, rather than implying the step is merely untested.
3. **The packaging scripts are the source of truth**, not this document. This
   document tells you which script to run, on which host, and how to check the
   result. It does not restate their internals.

---

## Quick install (library-first 0.1.0)

Khostty ships the upstream Ghostty VT engine across six binding surfaces. Three
commands get a developer a working VT parser; the downloads further down install
the desktop applications.

### Library + FFI

```bash
# Rust — published on crates.io (199/199 integration tests)
cargo add khostty-vt

# Browser / Node — published on npm (54/54 tests, 0.1.0)
npm install @khostty/libghostty-vt-wasm

# Python — PyPI publish pending trusted-publisher registration (operator action)
pip install khostty-vt          # works once O1/O2 land; today: install from source
#   git clone https://github.com/KooshaPari/Khostty.git && cd Khostty/khostty-python
#   pip install .

# Go — local clone only (no tagged module path yet)
go install github.com/KooshaPari/Khostty/khostty-go@latest
# OR today (no tagged release):
#   git clone https://github.com/KooshaPari/Khostty.git && cd Khostty/khostty-go
#   go build ./...

# C ABI — build from source (see BUILD.md §2 for full options)
zig build -Demit-lib-vt -Doptimize=ReleaseSafe
# → zig-out/lib/libghostty-vt.{a,0.1.0.dylib,0.1.0.so} + zig-out/include/ghostty/
```

### Desktop applications (download)

Download from the GitHub release page:
**<https://github.com/KooshaPari/Khostty/releases/tag/v0.1.0>**

| Asset | Bytes | Status (as of 2026-10-17) |
|---|---:|---|
| `Khostty-0.1.0-macos.zip` | 35,953,098 | **shippable** — signed; interactive keystroke round-trip verified 2026-09-20; not notarized |
| `Khostty-0.1.0-windows-x86_64-setup.exe` | 19,766,307 | **build + install + uninstall verified** — GUI window not yet launched (G3 scaffold; runtime calls return `error.Unimplemented` until G3 is lifted) |
| `khostty_0.1.0_amd64.deb` (GTK application) | 18,143,964 | **shippable** — install-verified on WSL Fedora 44; GUI-launch half-verified via Xvfb 2026-09-19 |
| `khostty-vt_0.1.0_amd64.deb` (library) | 2,320,612 | **shippable** — install-and-run-verified in x86-64 Debian 12 container |
| `khostty-libghostty-vt-wasm-0.1.0.tar.gz` | 680,598 | **shippable** — npm 0.1.0 published; `wasm/package.json` shows 0.0.0 (drift — Phase A6 fix) |
| `CHECKSUMS.txt` | 4,273 | release manifest |

Verify a download against the recorded checksum:

```bash
shasum -a 256 Khostty-0.1.0-macos.zip
# compare against the line in CHECKSUMS.txt whose path ends in the same basename
```

### Build from source

For everything that isn't a prebuilt download, see [`BUILD.md`](BUILD.md).
The short version for the VT library (no GUI dependencies):

```bash
git clone https://github.com/KooshaPari/Khostty
cd Khostty
zig build -Demit-lib-vt -Doptimize=ReleaseSafe
```

For the macOS `.app`, Linux `.deb`, Windows `.exe`, and WASM tarball the
per-target packaging scripts under `packaging/` are the source of truth; this
document's historical detail lives in §3.

---

## Status (the polish reality, 2026-10-17)

The 0.1.0 release shipped on 2026-09-27. The repository is in **post-SUNSET
polish**: Phase 0 (agent IPC build-wiring) merged via PR #15 at `ebc033eba`,
and the open work is concentrated on three remaining items: the post-merge
polish batch (Phase A, ~3h), the GTK runtime wire-up (Phase B, ~1d, blocked on
a Linux host), and Phase 1 mux shell design (Phase C, ~2d, blocked on operator
windowed-runtime decision).

What is shippable today:

- `cargo add khostty-vt` → instant parser in Rust
- `npm install @khostty/libghostty-vt-wasm` → instant parser in browser/Node
- The built `Khostty.app` that runs on macOS, behaves like upstream Ghostty,
  exposes the 3 upstream `+new-window` / `+new-tab` / `+toggle-quick-term`
  actions over the existing narrow IPC
- The Linux GTK `.deb` (install-verified on WSL Fedora 44)
- The Windows installer (build + install + uninstall verified; GUI not yet
  launched)

What is **not** yet shippable:

- The agent IPC **story** — modules written (6,839 LOC, 458 tests, 12 wire
  commands) and build-wired at `test-agent-ipc`, but **no runtime calls
  `Server.bind`**. The GTK runtime is the intended call site; the macOS
  operator host cannot build GTK.
- Even after GTK wiring, **`pane.focus` and `pane.search` return
  `error.Unsupported`** against the GTK runtime — they need upstream-core
  APIs (focus-by-id, synchronous scan) that do not exist upstream and are out
  of fork-only scope. **Do not build against `pane.focus` or `pane.search`
  and do not report them as shipped.**
- The Python binding — sdist built (`khostty_vt 0.1.0`); **PyPI publish
  pending operator action** (trusted publisher registration + dispatch hook
  approval, per `docs/RELEASE.md` §7).
- The Windows GUI runtime — scaffold exists (`src/apprt/windows/`, ~3,300
  lines, 11 files); every windowing + IPC call returns `error.Unimplemented`
  until G3 is lifted (3-4w scope, program decision).

Authoritative handoff:

- [`docs/audits-archive/2026-10-17-final/FINAL-AUDIT.md`](audits-archive/2026-10-17-final/FINAL-AUDIT.md)
  — synthesis, current state, what's done, what's unfinished, MVP scoring
- [`docs/audits-archive/2026-10-17-final/FWD-PATH.md`](audits-archive/2026-10-17-final/FWD-PATH.md)
  — Phases A/B/C task lists, operator decisions, effort budget
- [`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](sessions/20260916-fork-assessment/02_DEEP_WBS.md)
  — the 115-task Deep WBS that drove the 0.1.0 ship

---

## 1. Host requirements

| Target | Build host | Install/verify host | Tools the build host must have |
|---|---|---|---|
| Rust `khostty-vt` | any (build script invokes Zig) | any | `cargo`, `zig` 0.16.0; pre-built `libghostty-vt` (or rely on crate's link feature) |
| WASM tarball | macOS or Linux | any (Node ≥ 20) | `zig` 0.16.0, `node`, `tar`, `gzip` |
| Go `khostty-go` | any with cgo + Zig | any | `go` 1.23+, `zig` 0.16.0, pre-built `libghostty-vt` |
| Python `khostty-vt` | macOS or Linux | any | `python` 3.8+, `zig` 0.16.0, `cffi` |
| macOS library | macOS | macOS | `zig` 0.16.0, `cc`; Metal toolchain **not** required for `-Demit-lib-vt` |
| macOS `.app` | macOS | macOS with a GUI session | `zig` 0.16.0, Xcode, **Metal Toolchain component** |
| Linux `.deb` (GTK application) | Linux (native x86_64; cross-build from macOS is not viable: the payload needs GTK4 for the target) | Debian/Ubuntu x86-64 | `zig` 0.16.0, `dpkg-deb`, GTK4 + libadwaita development headers for the host (`gtk4-devel`, `libadwaita-devel`), `ImageMagick` for icons |
| Linux `.deb` (libghostty-vt library) | macOS or Linux — cross-compiles cleanly | Debian/Ubuntu x86-64 | `zig` 0.16.0, `dpkg-deb` (`brew install dpkg`); `docker` only for `--verify` |
| Windows installer | any host with `zig` | Windows x86-64 | `zig` 0.16.0, Inno Setup 6.3+ (`ISCC.exe`); on a non-Windows host also `wine` + `winepath` |

All packaging scripts accept a probe mode that only *reports* readiness and
changes nothing. Run it first on any new host:

```bash
bash packaging/version.sh                # resolved version + upstream base
bash packaging/macos-app.sh --probe      # writes dist-release/macos/toolchain-probe.txt
bash packaging/linux/deb.sh --probe           # prints, writes nothing
bash packaging/linux/deb-libvt.sh --probe     # library `.deb`; prints, writes nothing
bash packaging/windows/installer.sh --probe   # writes dist-release/windows/toolchain-probe.txt
```

---

## 2. Per-platform installation

### 2.1 Rust `khostty-vt` (crates.io)

```bash
cargo add khostty-vt
cargo build
cargo test             # requires the built shared library
```

The crate finds the library in this order:

1. `GHOSTTY_VT_LIB` — explicit file path
2. `GHOSTTY_VT_LIB_DIR` — explicit directory
3. `../zig-out/lib`, `../build/lib`, `../dist/lib`

Typecheck without a native library:

```bash
cargo check --no-default-features     # disables the `link` feature
```

The `bindgen` feature regenerates bindings and compares against the checked-in
`src/ffi.rs`; it requires libclang:

```bash
cargo test --features bindgen
```

Expected: 199/199 integration tests pass.

### 2.2 WASM / npm-style package

The published package is `@khostty/libghostty-vt-wasm 0.1.0` on
[npm](https://www.npmjs.com/package/@khostty/libghostty-vt-wasm). The
`wasm/package.json` source still shows `0.0.0` (drift; fixed by Phase A6).

```bash
npm install @khostty/libghostty-vt-wasm
```

Quick start:

```js
import { Terminal } from "@khostty/libghostty-vt-wasm/api";

using term = await Terminal.open({ cols: 80, rows: 24 });
term.write("Hello, World!\r\n\x1b[1;32mgreen bold\x1b[0m");
term.text();
// "Hello, World!\ngreen bold"
```

If you build the WASM module from source (no published tarball needed for
end-users; only for maintainers verifying the build):

```bash
bash packaging/wasm-dist.sh
```

The script builds the module, runs the repository WASM suite against the
rebuilt binary (54/54), assembles the dist, tars it deterministically, and
runs `packaging/wasm-smoke.mjs` against the extracted copy.

### 2.3 Python `khostty-vt` (PyPI pending)

The Python package is `khostty-vt` (importable as `khostty_vt`); version
`0.1.0` is built as a sdist and wheel locally. **PyPI publication is pending
operator action** (trusted publisher registration + dispatch hook approval
per `docs/RELEASE.md` §7).

Today (until O1/O2 land):

```bash
git clone https://github.com/KooshaPari/Khostty
cd Khostty/khostty-python
pip install .
```

Once PyPI publishes:

```bash
pip install khostty-vt
```

Verify:

```bash
python -c "import khostty_vt; print(khostty_vt.__version__)"
# expected: 0.1.0
```

### 2.4 Go `khostty-go` (local clone)

The Go module is `github.com/KooshaPari/Khostty/khostty-go`. There is no
tagged module path yet; today you build from a local clone.

```bash
git clone https://github.com/KooshaPari/Khostty
cd Khostty/khostty-go
go build ./...
go test ./...    # 45/45 cgo tests
```

Once a tagged module path is published:

```bash
go install github.com/KooshaPari/Khostty/khostty-go@latest
```

The Go binding links against the same `libghostty-vt` shared library; macOS
builds use the Xcode SDK explicitly (Command Line Tools + Xcode coexistence
causes `tapi error: malformed file`; pin via `SDKROOT`, see `BUILD.md §6`).

### 2.5 C ABI — macOS — library and headers — VERIFIED

**Artifacts:** `zig-out/lib/libghostty-vt.0.1.0.dylib` (+ `.0.dylib` and
`.dylib` symlinks, `libghostty-vt.a`), `zig-out/include/ghostty/…`
**Produced by:** `zig build -Demit-lib-vt`
**Evidence:** conformance run 2026-09-18 (84/84); see `docs/TESTING.md`

This is the artifact most C consumers want, and it is the one macOS target
that does **not** need the Metal toolchain or a GUI session.

Build and install in one step — `--prefix` is the install root, and its default
is `zig-out`:

```bash
# Install into a staging prefix and inspect before touching the system
zig build -Demit-lib-vt -Doptimize=ReleaseSafe --prefix "$PWD/stage-prefix"

# Install system-wide (the default prefix is `zig-out`; pass an absolute path
# to place it elsewhere)
sudo zig build -Demit-lib-vt -Doptimize=ReleaseSafe --prefix /usr/local
```

If the build dies with `unable to open '.../zig-pkg/<pkg>': FileNotFound`, the
repository-local `.zig-cache` holds a stale build runner. Use an explicit cache
directory; `packaging/lib.sh` does this for every script in `packaging/`:

```bash
zig build -Demit-lib-vt -Doptimize=ReleaseSafe --prefix /usr/local \
  --cache-dir "${JCODE_SCRATCH_DIR:-$PWD/../scratch}/zc/o" \
  --global-cache-dir "${JCODE_SCRATCH_DIR:-$PWD/../scratch}/zc/g"
```

Verify. Compiling a consumer against the installed prefix is the check that
actually proves the install: headers must resolve, the dylib must be findable,
its install name (`@rpath/libghostty-vt.dylib`) must be resolvable, and the
ABI must answer.

```bash
PREFIX=/usr/local   # the prefix you installed into
# Use the Xcode SDK explicitly; see the note below on why the default `cc` fails.
SDK=$(ls -d /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX2*.sdk | sort | tail -1)

cat > /tmp/khostty-consumer.c <<'EOF'
#include <stdio.h>
#include <ghostty/vt.h>
#include <ghostty/vt/build_info.h>
int main(void) {
    GhosttyString version = {0};
    GhosttyOptimizeMode optimize = GHOSTTY_OPTIMIZE_DEBUG;
    size_t major = 0, minor = 0, patch = 0;
    GhosttyResult r1 = ghostty_build_info(GHOSTTY_BUILD_INFO_VERSION_STRING, &version);
    GhosttyResult r2 = ghostty_build_info(GHOSTTY_BUILD_INFO_OPTIMIZE, &optimize);
    GhosttyResult r3 = ghostty_build_info(GHOSTTY_BUILD_INFO_VERSION_MAJOR, &major);
    GhosttyResult r4 = ghostty_build_info(GHOSTTY_BUILD_INFO_VERSION_MINOR, &minor);
    GhosttyResult r5 = ghostty_build_info(GHOSTTY_BUILD_INFO_VERSION_PATCH, &patch);
    if (r1 == GHOSTTY_SUCCESS)
        printf("build_info version_string = %.*s\n", (int)version.len, (const char *)version.ptr);
    printf("build_info optimize       = %d\n", (int)optimize);
    printf("build_info version triple = %zu.%zu.%zu (rc %d/%d/%d)\n",
           major, minor, patch, (int)r3, (int)r4, (int)r5);
    const int ok = (r1 == GHOSTTY_SUCCESS) && (r2 == GHOSTTY_SUCCESS) &&
                   (r3 == GHOSTTY_SUCCESS) && (r4 == GHOSTTY_SUCCESS) &&
                   (r5 == GHOSTTY_SUCCESS);
    printf("RESULT: %s\n", ok ? "PASS" : "FAIL");
    return ok ? 0 : 1;
}
EOF

cc -isysroot "$SDK" -I "$PREFIX/include" /tmp/khostty-consumer.c \
   -L "$PREFIX/lib" -lghostty-vt \
   -Wl,-rpath,"$PREFIX/lib" -o /tmp/khostty-consumer
/tmp/khostty-consumer       # expected: RESULT: PASS

# Confirm no unresolved dependencies in the installed dylib itself
otool -L "$PREFIX/lib/libghostty-vt.0.1.0.dylib"
```

Behavioural verification, which is a stronger claim than "it linked":

```bash
bash conformance/build.sh run
# expected tail: Passed: 84 / Failed: 0 / Total: 84 / Success Rate: 100%
```

**Troubleshooting the verify step: `ld: tapi error: malformed file`.** If `cc`
resolves to the Command Line Tools toolchain, linking can fail before it ever
looks at the library:

```
ld: tapi error: malformed file
/Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk/usr/lib/libSystem.B.tbd:4:20:
error: unknown architecture  [arm64e.x1-macos, arm64e.x1-maccatalyst ]
clang: error: linker command failed with exit code 1
```

That is a CLT SDK problem, not a library problem. Pass the Xcode SDK explicitly
(`-isysroot "$SDK"` as above, or `xcrun -sdk macosx cc`). Against the Xcode 26.0
SDK the same command links and runs cleanly.

### 2.6 macOS — the `.app` bundle — VERIFIED (build); launch verified 2026-09-20

**Artifacts:** `zig-out/Ghostty.app`,
`dist-release/macos/Khostty-0.1.0-macos.zip` (35,953,098 B,
`sha256 94abd2a7e7d63e790bfffd3a6e6f4e08ae80a67fbf3dbe8227e754c6104317cb`)
**Produced by:** `packaging/macos-app.sh`

Build:

```bash
bash packaging/macos-app.sh              # build, sign, verify signature, zip
bash packaging/macos-app.sh --no-sign    # build and zip without signing
```

Install:

```bash
ditto -x -k dist-release/macos/Khostty-0.1.0-macos.zip /Applications
open /Applications/Ghostty.app
```

Verify:

```bash
codesign --verify --deep --strict --verbose=2 /Applications/Ghostty.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  /Applications/Ghostty.app/Contents/Info.plist
/Applications/Ghostty.app/Contents/MacOS/ghostty +version
spctl --assess --type execute --verbose /Applications/Ghostty.app
```

GUI launch verified 2026-09-20: `open` (PID 30796), two windows enumerated,
keystroke round-trip (`echo SHELL_ECHO_TEST` → typed line + shell's echoed
response observed in the AXTextArea) proves interactive keyboard input
executes in a live shell.

**One caveat:** notarization is not configured on this host, so first launch on
a pristine machine may require a Gatekeeper override (untested).

### 2.7 Linux — `.deb`

Two different `.deb`s belong to this section and they have different status.

#### 2.7.1 `khostty_0.1.0_amd64.deb` — GTK application — BUILT + INSTALL-VERIFIED (2026-09-19)

The build enables both Wayland and X11 display backends (the default
`gtk_targets` on Linux) plus `gtk4-layer-shell`, which only has an effect on
the Wayland backend (window positioning/anchoring). Neither backend can be
exercised without a desktop session, so both remain unverified at runtime on
this host.

**Artifact:** `dist/khostty_0.1.0_amd64.deb` — 18,143,964 bytes,
`sha256 63d4e6159d65e97db685b9eedbe19c37765f5f838279e9d5b0326ab5a7b80de0`
**Produced by:** `packaging/linux/deb.sh`
**Built on:** WSL Fedora 44 on `kooshapari-desk` (native x86_64 Linux; has
`gtk4-devel`, `libadwaita-devel`, `gtk4-layer-shell-devel`, `ImageMagick`, zig
0.16.0 at `/opt/zig`).

Build, on a Linux host:

```bash
bash packaging/linux/deb.sh
# or, for toolchain readiness only:
bash packaging/linux/deb.sh --probe
```

Install:

```bash
# Requires glibc >= 2.43 (Debian trixie is 2.41, Ubuntu 25.10 is 2.42, Fedora 42+ ok).
# dpkg -i leaves the package unpacked-but-unconfigured on older distros instead of
# shipping a binary that cannot load; apt resolves the libc6 floor and refuses cleanly.
sudo dpkg -i dist/khostty_0.1.0_amd64.deb
# or, letting the package manager resolve libc6:
sudo apt install ./dist/khostty_0.1.0_amd64.deb
```

Verify:

```bash
dpkg -s khostty | grep -E '^(Status|Version|Architecture):'
#    expected: Status: install ok installed

dpkg -L khostty | grep -E '/usr/bin/khostty|applications/.*desktop|metainfo/|icons/hicolor.*png'
#    expected: /usr/bin/khostty, the .desktop, the metainfo.xml, and 6 hicolor PNGs

ldd "$(command -v khostty)" | grep 'not found'    # expected: no output
desktop-file-validate /usr/share/applications/com.khostty.Khostty.desktop
khostty +version                                   # expected: prints the Ghostty/Khostty version block

# Desktop integration actually registered
update-desktop-database ~/.local/share/applications 2>/dev/null || true
gio info /usr/share/applications/com.khostty.Khostty.desktop >/dev/null && echo "desktop entry readable"
```

#### 2.7.2 `khostty-vt_0.1.0_amd64.deb` — libghostty-vt library — VERIFIED

**Artifact:** `dist/khostty-vt_0.1.0_amd64.deb` — 2,320,612 bytes,
`sha256 3c080d13a74d6bf6dca9d28dc2c685f6b4350ec3130f3f3fafa5cb4d77d834cf`,
computed twice with independent tools (`shasum -a 256` and `openssl dgst
-sha256`).
**Produced by:** `packaging/linux/deb-libvt.sh` (new).

This is a different payload, not a relabelled substitute. libghostty-vt is the
only Khostty artifact that cross-compiles from macOS to `x86_64-linux-gnu`. It
is a real x86-64 Linux ELF — `file` reports `ELF 64-bit LSB shared object, x86-64`,
`objdump -p` reports `SONAME libghostty-vt.so.0` and `NEEDED libm.so.6 libc.so.6
librt.so.1` — packaged with its SONAME and development symlinks, the public C
headers, and a `pkg-config` file. It is **not** the GTK terminal application.

Build and structural verification:

```bash
bash packaging/linux/deb-libvt.sh          # exit 0
#   payload ELF verified: soname=libghostty-vt.so.0 needs=[libc.so.6 libm.so.6 librt.so.1]
#   ar members: debian-binary control.tar.xz data.tar.xz
#   debian-binary = 2.0
#   dpkg-deb --info succeeded; dpkg-deb --contents succeeded (54 entries)
```

Install-and-run verification — executed, not inferred:

```bash
bash packaging/linux/deb-libvt.sh --verify   # exit 0
```

Observed in an `x86_64` `debian:bookworm` container (Debian 12.15, glibc 2.36)
on this host, launched with `docker run --platform linux/amd64` with the
repository mounted read-only:

| Check | Observed |
|---|---|
| `dpkg -i dist/khostty-vt_0.1.0_amd64.deb` | exit 0; `Setting up khostty-vt (0.1.0) ...`; `dpkg -s` → `Status: install ok installed` |
| `dpkg -L khostty-vt` | 54 entries, including `/usr/lib/x86_64-linux-gnu/libghostty-vt.so.0.1.0`, `.../libghostty-vt.so.0`, `.../libghostty-vt.so`, `/usr/include/ghostty/vt.h`, the `vt/**` headers, and `.../pkgconfig/libghostty-vt.pc` |
| `dpkg -V khostty-vt` | no modified or missing files — the package's `md5sums` integrity holds |
| `ldconfig -p \| grep ghostty` | `libghostty-vt.so.0 (libc6,x86-64) => /lib/x86_64-linux-gnu/libghostty-vt.so.0` |
| `gcc example/c-vt-formatter/src/main.c -lghostty-vt` | compiled against the **installed** headers and the **installed** `.so`; ran and printed the formatted 80×24 screen |
| functional assertions | 4/4 PASS — literal text, `CSI 2K` erase-and-rewrite, CUP placement at (5,10), right-edge clamp |
| `dpkg -r khostty-vt` | exit 0; clean removal |

### 2.8 Windows — `.exe` installer — BUILT + install-verified 2026-09-19

> **Windows GUI window is NOT yet launchable.** The `ghostty.exe` runtime is a
> SCAFFOLD (`src/apprt/windows/`, ~3,300 lines, 11 files). All windowing +
> IPC calls return `error.Unimplemented` until G3 is lifted (3-4w scope,
> program decision; see `FINAL-AUDIT.md §5`). What is verified today: the
> installer builds, installs, runs the CLI `+version`, and uninstalls cleanly;
> the bundled `ghostty-vt.dll` loads and answers its ABI live.

**Artifact:**
`dist-release/stage/windows/Khostty-0.1.0-win64/output/Khostty-0.1.0-windows-x86_64-setup.exe`
(19,766,307 B, `sha256 4070e89e8f693c44abda13da1b718dca4e53d73279f3d945854431d76f095546`,
`VersionInfo.FileVersion 0.1.0.0`)
**Produced by:** `packaging/windows/installer.sh` (payload) + `ISCC.exe khostty.iss` (compiler)

Build:

```bash
bash packaging/windows/installer.sh --probe      # readiness, changes nothing
bash packaging/windows/installer.sh --stage-only # build + stage payload + generate .iss, stop before ISCC
bash packaging/windows/installer.sh              # full build: stage, generate .iss, run ISCC
bash packaging/windows/installer.sh --no-build   # reuse existing zig-out/bin artifacts
```

On a host with no Inno Setup in a default location, point the script at the
compiler explicitly:

```bash
KHOSTTY_ISCC="/path/to/ISCC.exe" bash packaging/windows/installer.sh
```

Install, on Windows:

```powershell
# Interactive
.\Khostty-0.1.0-windows-x86_64-setup.exe

# Unattended, no elevation (the .iss sets PrivilegesRequired=lowest)
.\Khostty-0.1.0-windows-x86_64-setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG=install.log
```

Verify:

```powershell
# 1. Files landed
Get-ChildItem "$env:LOCALAPPDATA\Programs\Khostty"     # or $env:ProgramFiles\Khostty if installed elevated
#    expected: ghostty.exe, ghostty-vt.dll, ghostty.ico, LICENSE

# 2. The installed binary answers
& "$env:LOCALAPPDATA\Programs\Khostty\ghostty.exe" +version

# 3. The installer registered an uninstaller (Inno writes this key)
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' |
  Where-Object DisplayName -like 'Khostty*' |
  Select-Object DisplayName, DisplayVersion, InstallLocation, UninstallString

# 4. Silent uninstall leaves nothing behind, then re-check step 3 is empty
& "$env:LOCALAPPDATA\Programs\Khostty\unins000.exe" /VERYSILENT

# 5. Payload integrity against the recorded hashes
Get-FileHash "$env:LOCALAPPDATA\Programs\Khostty\ghostty.exe" -Algorithm SHA256
Get-FileHash "$env:LOCALAPPDATA\Programs\Khostty\ghostty-vt.dll" -Algorithm SHA256
#    compare against dist-release/windows/EVIDENCE.txt (written only by a full build)
```

**Status, observed 2026-09-19. The installer is BUILT and was installed, run
and uninstalled.** Inno Setup 6.7.1 was installed on the Windows runner
`kooshapari-desk` (via Chocolatey), and the staged `khostty.iss` was compiled:

```
ISCC.exe khostty.iss
   Successful compile (11.891 sec). Resulting Setup program filename is:
   ...\output\Khostty-0.1.0-windows-x86_64-setup.exe
```

Then, on the same host (`docs/sessions/20260916-fork-assessment/evidence/windows_installer_e2e_2026-09-19.txt`):

```
SETUP ARTIFACT   bytes 19766307   sha256 4070E89E…095546   ver 0.1.0.0
SILENT INSTALL   installer exited: True
INSTALLED PAYLOAD
  MATCH  DF0B4C87…  ghostty.exe
  MATCH  B4CFF87E…  ghostty-vt.dll
  uninstaller present: True
RUN INSTALLED ghostty.exe +version  ->  app runtime: .windows
SILENT UNINSTALL  residual installed files: 0
DONE failures=0
```

### 2.9 Windows — payload binaries only — VERIFIED as artifacts

If you want the terminal binaries without the installer, build them directly
with `zig` and copy them wherever you like:

```bash
zig build -Dtarget=x86_64-windows-gnu -Dapp-runtime=windows \
  -Demit-macos-app=false -Doptimize=ReleaseFast      # -> zig-out/bin/ghostty.exe
zig build -Dtarget=x86_64-windows-gnu -Demit-lib-vt -Doptimize=ReleaseFast  # -> zig-out/bin/ghostty-vt.dll
```

These are the two invocations `packaging/windows/installer.sh` performs. They
were **not** re-run during this documentation pass; what was checked on
2026-09-18 is that the resulting artifacts exist in `zig-out/bin/` and that
`file` reports:

```
zig-out/bin/ghostty.exe:    PE32+ executable (GUI) x86-64, for MS Windows
zig-out/bin/ghostty-vt.dll: PE32+ executable (DLL) (GUI) x86-64, for MS Windows
```

Windows consumers must ship `ghostty.exe` and `ghostty-vt.dll` **together**;
the `.dll` is the ABI the executable and any C/Rust/Go/Python consumer link
against. A `.pdb` is emitted alongside each — useful for debugging, not
required at runtime.

---

## 3. Evidence log (anchor dates, archived)

The historical evidence log is preserved here for traceability. Every command
in the original section was executed on this host on the observed date;
nothing was inferred. The hash table at the end of the original section is
also preserved verbatim — those hashes describe the bytes on this host at the
stated time and are not a release manifest.

For the release manifest itself see `packaging/version.sh --json` and the
per-target `EVIDENCE.txt` files written by each packaging script. Note also
that `dist-release/` (`.gitignore` line 41) and `zig-out/` are gitignored.
Every path in this document that starts with those two prefixes is **local
build output that is not in git**.

The archived evidence lives in
[`docs/sessions/20260916-fork-assessment/evidence/`](sessions/20260916-fork-assessment/evidence/).
A small selection of high-value evidence files:

- `wasm-tarball-smoke.json` — 13/13 consumer checks, exit 0
- `gtk_deb_install_2026-09-19.txt` — Linux GTK `.deb` install-verify on WSL Fedora 44
- `khostty_gui_launch_xvfb_2026-09-19.log` — GTK app launched headless via Xvfb
- `windows_installer_e2e_2026-09-19.txt` — Windows installer install + uninstall
- `windows_runtime_verify_2026-09-19.txt` — `ghostty.exe +version` + `ghostty-vt.dll` ABI on real Windows

---

## 4. What would change these statuses

1. **macOS `.app`** — **build closed 2026-09-18.** GUI launch verified 2026-09-20.
   The Metal toolchain was obtained on this host by pinning the asset build
   and adding the graft Xcode failed to create. Two things still change this
   status: (a) a **reboot or Xcode upgrade** silently undoes the fix, because
   the symlinks resolve through a per-boot cryptex mount name — re-run the two
   `ln -sfn` commands from §3.3 of the archived INSTALL.md, or use an Xcode
   whose build appears in `XcodeToMetalToolchainIndexMapping.plist`; (b)
   notarization remains impossible without `notarytool` credentials.
2. **Linux `.deb` (GTK application)** — **build + install closed 2026-09-19;**
   GUI launch half-verified headless via Xvfb the same day. Re-run on any
   native x86_64 Linux host with the GTK4 + libadwaita development packages.
3. **Linux `.deb` (libghostty-vt library)** — **closed 2026-09-18.** Re-run
   `bash packaging/linux/deb-libvt.sh --verify` after any change to the VT
   core; the pass describes the library built on 2026-09-18, not the current
   tree.
4. **Windows `.exe`** — install Inno Setup 6.3+ on a Windows host and run
   `bash packaging/windows/installer.sh`, or set `KHOSTTY_ISCC` and add wine
   on a POSIX host. The `.iss` is generated with
   `ArchitecturesAllowed=x64compatible`, which requires Inno 6.3 or newer; on
   6.0–6.2 substitute `x64`. GUI launch is still blocked on the G3 scaffold
   being lifted (3-4w scope).
5. **macOS library** — already verified; re-run `bash conformance/build.sh run`
   after any change to the VT core, because the 84/84 pass describes the
   library built on 2026-09-18, not the current source tree.
6. **PyPI publish** — blocked on operator action (trusted publisher
   registration + dispatch hook approval, per `docs/RELEASE.md` §7).
7. **Go tagged module path** — no upstream commit to publish a tagged Go
   module path yet; today you build from a local clone.
8. **Agent IPC `Server.bind`** — blocked on a GTK/Linux host (Phase B in
   `FWD-PATH.md`). The macOS operator host cannot build GTK.
9. **`pane.focus` / `pane.search` `error.Unsupported`** — requires
   upstream-core API additions (focus-by-id, synchronous scan) that are out of
   fork-only scope.

---

## See also

- [`BUILD.md`](BUILD.md) — compiling from source, flag reference, build troubleshooting
- [`README.md`](../README.md) — overview, install quickref, architecture, status
- [`TESTING.md`](TESTING.md) — the conformance suite and every other test surface
- [`PLATFORMS.md`](PLATFORMS.md) — the support matrix these artifacts map onto
- [`AGENT.md`](AGENT.md) — driving the installed binary from an agent
- [`SECURITY.md`](SECURITY.md) — agent IPC auth model, threat model
- [`RELEASE.md`](RELEASE.md) — release process, registry publishes
- [`audits-archive/2026-10-17-final/FINAL-AUDIT.md`](audits-archive/2026-10-17-final/FINAL-AUDIT.md)
  — current-state audit (canonical)
- [`audits-archive/2026-10-17-final/FWD-PATH.md`](audits-archive/2026-10-17-final/FWD-PATH.md)
  — Phase A/B/C task lists
- `packaging/lib.sh` — the shared rules every packaging script follows, including "never fabricate a result"
- `packaging/linux/deb-libvt.sh` — the libghostty-vt `.deb`; `--probe`, plain, and `--verify` (installs and runs the package in an x86-64 Debian container)
- `packaging/version.sh` — the single source of truth for the version number