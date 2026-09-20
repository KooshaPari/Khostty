# Installing Khostty

**Observed:** 2026-09-18 · **Version:** `0.1.0` (`-dev` prerelease) · **Source revision:** `c2bac90`, working tree dirty

Version and revision come from `packaging/version.sh`, which reads `lib_version`
out of `build.zig` and derives the upstream base from git. That script is the only
authority for the version number; this document never restates a version by hand.

This is the installation counterpart to [BUILD.md](BUILD.md). BUILD.md answers
*"how do I compile this?"*. This document answers *"how do I install the result,
and how do I prove the install actually worked?"*.

Three rules govern every claim below:

1. **Every status carries its observation date.** A pass observed yesterday is
   not a pass observed today, and this repository is under concurrent edit.
2. **Nothing is marked VERIFIED unless the check was executed on this host.**
   Where a step needs a host this machine is not, the row says so and names the
   missing tool, rather than implying the step is merely untested.
3. **The packaging scripts are the source of truth**, not this document. This
   document tells you which script to run, on which host, and how to check the
   result. It does not restate their internals.

---

## 1. Status at a glance (2026-09-18)

Status vocabulary used throughout:

| Status | Meaning |
|---|---|
| **VERIFIED** | The artifact exists, its hash was computed on 2026-09-18, and the stated check was executed and passed on this host. |
| **NOT BUILT** | The packaging script exists and its `--probe` mode runs green, but the artifact has never been produced. The specific missing tool is named. |
| **BLOCKED** | A required toolchain component is absent or unusable and cannot be obtained on this host. The exact failure is recorded. |

| # | Artifact | Platform | Status | Evidence, as observed 2026-09-18 |
|---|---|---|---|---|
| 1 | `khostty-libghostty-vt-wasm-0.1.0.tar.gz` | any — Node ≥ 20 / browser | VERIFIED | Tarball `sha256 55cfc675…` matches the sidecar `.sha256` written beside it, verified with `shasum -a 256 -c` (exit 0). Freshly extracted to a scratch directory and `node smoke.mjs --json` returned 13/13 checks, 0 failed, exit 0. A direct `import` of the extracted `js/api.js` opened a terminal and echoed text back. Repository WASM suite re-run the same day: 54 tests, 54 pass, 0 fail. |
| 2 | `libghostty-vt.0.1.0.dylib` + `include/ghostty/` headers | macOS arm64 | VERIFIED | `zig build -Demit-lib-vt -Doptimize=ReleaseSafe --prefix <scratch>` installed a prefix (exit 0); a C program including the **installed** headers and linking the **installed** dylib compiled, ran, and printed `RESULT: PASS` with the library reporting `0.1.0-dev` (see §3.2). Conformance harness against the built library: 84/84 passed, 0 failed. |
| 3 | `Khostty-0.1.0-macos.zip` — the `Ghostty.app` bundle | macOS | VERIFIED (build) / LAUNCH NOT EXECUTED | Built, signed, verified and hashed on this host 2026-09-18: `bash packaging/macos-app.sh` exited **0**, producing `dist-release/macos/Khostty-0.1.0-macos.zip` (35,953,098 B, `sha256 94abd2a7e7d63e790bfffd3a6e6f4e08ae80a67fbf3dbe8227e754c6104317cb`, `shasum -c` OK). `codesign --verify --deep --strict` → *valid on disk* / *satisfies its Designated Requirement*. The bundled binary was executed non-interactively: `Contents/MacOS/ghostty --version` → `Ghostty 1.3.2-main-+41b24baad`, exit 0. **This row was `BLOCKED` until 2026-09-18; the previous reason was wrong** — see §3.3. Not notarized (no `notarytool` credentials), and no GUI launch was attempted, so the WBS "installs and runs" clause is only half-met. |
| 4 | `khostty_0.1.0_amd64.deb` — the GTK **application** | Debian / Ubuntu x86-64 | BUILT + INSTALL-VERIFIED (2026-09-19) / GUI launch OPEN | **Built 2026-09-19 in WSL Fedora 44 on `kooshapari-desk`** (native x86_64 Linux with `gtk4-devel`, `libadwaita-devel`, `gtk4-layer-shell-devel`): `dist/khostty_0.1.0_amd64.deb`, **18,143,964 B**, `sha256 63d4e6159d65e97db685b9eedbe19c37765f5f838279e9d5b0326ab5a7b80de0` (supersedes `209ba5ed…713a`). Three blockers fixed (§3.4.1): the unconditional `-Dtarget=x86_64-linux-gnu` that made Zig refuse system shared libraries on a native host (now conditional, `9daf736e8`), the icon set / desktop `Icon=` ref (now size-matched hicolor PNGs 16–512 + `Icon=com.khostty.Khostty`, `45e6d086b`), and the stale `libc6 (>= 2.17)` floor that let `dpkg -i` install onto glibc 2.36 with the binary failing at load (now derived from the binary with readelf: `libc6 (>= 2.43)`, `65de471df`). **Install-verified on the WSL host (glibc 2.43, dpkg db via `--force-depends`):** `dpkg -s` → `install ok installed`, `dpkg -V` clean, `dpkg -L` lists the binary + `.desktop` + metainfo + 6 hicolor PNGs, `ldd` all resolved, `desktop-file-validate` OK, metainfo well-formed, installed `khostty +version` → exit 0, `gio info` readable, `dpkg --purge` clean. **Negative control (bookworm glibc 2.36):** unpack ok, configure REFUSED on `libc6 (>= 2.43)`. Evidence `sessions/20260916-fork-assessment/evidence/gtk_deb_install_2026-09-19.txt`. No GUI launch attempted (no desktop session on the WSL host); that half is open. Cross-building **from macOS is still not viable** (Homebrew's `gtk4` cannot supply a Linux sysroot). |
| 5 | `khostty-vt_0.1.0_amd64.deb` — the libghostty-vt **library** | Debian / Ubuntu x86-64 | VERIFIED | `packaging/linux/deb-libvt.sh` cross-compiles libghostty-vt for `x86_64-linux-gnu` and packages it. `sha256 3c080d13a74d6bf6dca9d28dc2c685f6b4350ec3130f3f3fafa5cb4d77d834cf`, 2,320,612 bytes; `ar t` → `debian-binary`, `control.tar.xz`, `data.tar.xz`; `dpkg-deb --info` and `--contents` (54 entries) both succeed. **Installed and run, not inferred:** in an x86-64 Debian 12 (bookworm, glibc 2.36) container, `dpkg -i` exited 0 with `Status: install ok installed`; `dpkg -V` found no modified or missing files; `ldconfig -p` resolved the SONAME; the shipped `example/c-vt-formatter` compiled against the **installed** headers and **installed** `.so` and passed 4/4 VT assertions; `dpkg -r` removed it cleanly. This is the library payload, not the GTK application. See §3.4.2. |
| 6 | `Khostty-0.1.0-windows-x86_64-setup.exe` | Windows x86-64 | BUILT + VERIFIED | **Built 2026-09-19.** Inno Setup 6.7.1 was installed on the Windows runner `kooshapari-desk`; `ISCC.exe khostty.iss` → *Successful compile (11.891 s)*, producing **19,766,307 B**, `sha256 4070e89e8f693c44abda13da1b718dca4e53d73279f3d945854431d76f095546`, `VersionInfo.FileVersion 0.1.0.0`. **Installed, run and uninstalled, not inferred:** silent install to a scratch dir (exit 0) produced `ghostty.exe` + `ghostty-vt.dll` + `ghostty.ico` + `LICENSE` + `unins000.exe`; the two payload files **hash-match the staged originals**; the installed `ghostty.exe +version` ran (`app runtime: .windows`); silent uninstall left **0 residual files**. Evidence `sessions/20260916-fork-assessment/evidence/windows_installer_e2e_2026-09-19.txt`. |
| 7 | `ghostty.exe` + `ghostty-vt.dll` (row 6's payload) | Windows x86-64 | BUILT + EXECUTED | Both are real PE32+ files built 2026-09-18 (43.5 MB and 7.5 MB), staged and hashed 2026-09-18T03:33 local. `file` confirms `PE32+ executable (GUI) x86-64` and `PE32+ executable (DLL)`. **Executed 2026-09-19 on `kooshapari-desk` (Windows NT 10.0.28120, AMD64)**, copied there byte-identically (sha256 re-verified): `ghostty.exe +version` → exit 0, reporting `app runtime: .windows`, `font engine: .freetype_windows`, `libxev: iocp`, `Zig 0.16.0`, build mode `.Debug`; `ghostty-vt.dll` loads via `LoadLibraryW` and its ABI runs live — `terminal_new(80,24)` rc 0, `get COLS/ROWS` 80/24, `resize(100,40)` → 100/40, `vt_write` + OSC-0 → `CURSOR_Y` 1 / `TITLE` `Khostty-Win`, `terminal_free` clean — **0 failures**. Evidence `sessions/20260916-fork-assessment/evidence/windows_runtime_verify_2026-09-19.txt`. Caveat: CLI `+version` only; no GUI window was launched. |

**No row in this table claims a runtime test that was not run.** Rows 1, 2 and 5
are the rows whose checks were executed end to end on 2026-09-18. Row 5 is the
only one whose install-and-run check ran on Linux, and it exercised the
libghostty-vt *library* payload — not the GTK application. Row 7 was a *build
product* only until **2026-09-19**, when both files were executed on the Windows
runner `kooshapari-desk`: `ghostty.exe +version` exits 0 and `ghostty-vt.dll` runs
its terminal ABI live (0 failures). The GUI window was not launched, so "runs" is
demonstrated for the CLI/library surface but not for interactive windowing.

### What is still missing for the WBS 9.15 acceptance criteria

[`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](sessions/20260916-fork-assessment/02_DEEP_WBS.md)
requires that the macOS `.app`, the Linux `.deb`, and the Windows `.exe` each
"install and run". One of the three remains undemonstrable from this host: the
Windows `.exe` needs Inno Setup plus a Windows host. The macOS `.app` **builds**,
signs and verifies, and its binary executes (`--version`, exit 0), but it has not
been installed outside the source tree or launched in a GUI session, so its clause
is half-met rather than met (§3.3). The Linux `.deb` criterion **is** satisfied for
both payloads **as builds**: the GTK *application* `.deb` was built 2026-09-19 in
WSL Fedora 44 (§3.4.1), and the libghostty-vt library `.deb` is built AND
install-and-run-verified on x86-64 Debian 12 (§3.4.2). The GTK payload's
install-verify (install, `desktop-file-validate`) is now met on the WSL glibc 2.43
host (§3.4.1); the GUI-launch half is now verified headless (Xvfb, APP_ALIVE,
zero-error GTK init; §3.4.1).
§5 lists, per artifact, the exact requirement that is missing and
where it can be met. The
fourth criterion — the WASM dist being consumable via npm/ESM — **is** satisfied,
observed 2026-09-18 (§3.1).

---

## 2. Host requirements

| Target | Build host | Install/verify host | Tools the build host must have |
|---|---|---|---|
| WASM tarball | macOS or Linux | any (Node ≥ 20) | `zig` 0.16.0, `node`, `tar`, `gzip` |
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

## 3. Per-platform installation

### 3.1 WASM / npm-style package — VERIFIED

**Artifact:** `dist-release/wasm/khostty-libghostty-vt-wasm-0.1.0.tar.gz`
**Produced by:** `packaging/wasm-dist.sh`
**Verification evidence:** `dist-release/logs/wasm-source-tests.log`, `dist-release/logs/wasm-tarball-smoke.json`

Build:

```bash
bash packaging/wasm-dist.sh
```

The script builds the module, runs the repository WASM suite against the rebuilt
binary, assembles the dist, tars it deterministically, repacks it to prove the
bytes are reproducible, extracts the tarball to a scratch directory, and runs
`packaging/wasm-smoke.mjs` against the **extracted** copy. Those last two are
separate claims on purpose: a tarball can omit a file the source-tree suite never
needed, and only the extracted-artifact run catches that.

Install, three supported ways:

```bash
# From the tarball, as a dependency of another project
npm install /absolute/path/to/khostty-libghostty-vt-wasm-0.1.0.tar.gz

# From an unpacked directory: extract once, then install or import directly
tar -xzf dist-release/wasm/khostty-libghostty-vt-wasm-0.1.0.tar.gz
npm install ./khostty-libghostty-vt-wasm-0.1.0

# Directly by path, no packaging step at all
node --input-type=module -e '
  import { openTerminal } from "./khostty-libghostty-vt-wasm-0.1.0/js/api.js";
  using term = await openTerminal({ cols: 20, rows: 4 });
  term.write("hello\r\n");
  console.log("text() =", JSON.stringify(term.text()));
'
#    observed 2026-09-18: text() = "hello"
```

`js/api.js` is the object-model entry point (`Terminal`, `Snapshot`, `Search`,
`openTerminal`, plus re-exports of `loadGhosttyVt` and the error types);
`js/index.js` is the lower-level C-ABI surface. Both are declared in the
tarball's `package.json` `exports` map, so `import { openTerminal } from
"khostty-libghostty-vt-wasm/api"` works after an `npm install`.

Verify:

```bash
# 1. Integrity against the recorded hash (run from dist-release/wasm/)
shasum -a 256 -c khostty-libghostty-vt-wasm-0.1.0.tar.gz.sha256
#    expected: khostty-libghostty-vt-wasm-0.1.0.tar.gz: OK

# 2. Consumer smoke test on a fresh extraction
mkdir -p /tmp/khostty-wasm-verify && tar -xzf khostty-libghostty-vt-wasm-0.1.0.tar.gz -C /tmp/khostty-wasm-verify
cd /tmp/khostty-wasm-verify/khostty-libghostty-vt-wasm-0.1.0
node smoke.mjs          # expected final line: 13/13 checks passed
node smoke.mjs --json   # machine-readable; compare length vs failures

# 3. Repository suite (from the source tree)
cd wasm && node --test --test-reporter=tap test/ | grep -E '^# (pass|fail)'
#    expected: # pass 54  /  # fail 0
```

The smoke test exercises the public entry point (`js/api.js`), instantiates the
bundled module, opens a terminal at a requested size, renders cells to HTML,
reads cursor/screen state, resizes with reflow, and round-trips a snapshot. A
partial pass is not success: `packaging/wasm-dist.sh` fails the build if any
check fails, precisely so a "13/14 checks passed" line can never be mistaken for
a green run.

One thing the script does **not** claim: it never claims the package is
*published*. `npm publish` is a separate, deliberate act and no row here depends
on it.

### 3.2 macOS — library and headers — VERIFIED

**Artifacts:** `zig-out/lib/libghostty-vt.0.1.0.dylib` (+ `.0.dylib` and
`.dylib` symlinks, `libghostty-vt.a`), `zig-out/include/ghostty/…`
**Produced by:** `zig build -Demit-lib-vt`
**Evidence:** conformance run 2026-09-18 (84/84); see `docs/TESTING.md`

This is the artifact most consumers want, and it is the one macOS target that
does **not** need the Metal toolchain or a GUI session.

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
its install name (`@rpath/libghostty-vt.dylib`) must be resolvable, and the ABI
must answer.

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

`conformance/build.sh` resolves the library at `zig-out/lib/libghostty-vt.dylib`,
so run it against the default prefix (or copy the installed dylib there). For a
non-default prefix, point `DYLD_LIBRARY_PATH` at it:
`DYLD_LIBRARY_PATH=/usr/local/lib ./zig-out/bin/conformance_test`.

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

**Observed 2026-09-18, executed end to end.** Install into a throwaway prefix
(`zig build -Demit-lib-vt -Doptimize=ReleaseSafe --prefix <scratch>`, exit 0,
emitting `include/ghostty/…`, `lib/libghostty-vt.0.1.0.dylib` plus `.0.dylib` and
`.dylib` symlinks, `lib/libghostty-vt.a`, `share/man`, `share/pkgconfig`,
`lib/ghostty-vt.xcframework`). Compiling the consumer above against that prefix
and running it:

```
build_info version_string = 0.1.0-dev
build_info optimize       = 1        (GHOSTTY_OPTIMIZE_RELEASE_SAFE)
build_info version triple = 0.1.0 (rc 0/0/0)
RESULT: PASS
```

The build emits one warning that does not block this target:
`Metal toolchain not found; using the OpenGL renderer instead`. It is relevant
only to §3.3.

### 3.3 macOS — the `.app` bundle — VERIFIED (build); launch not executed

**Artifacts (both exist, observed 2026-09-18):** `zig-out/Ghostty.app`,
`dist-release/macos/Khostty-0.1.0-macos.zip` (35,953,098 B,
`sha256 94abd2a7e7d63e790bfffd3a6e6f4e08ae80a67fbf3dbe8227e754c6104317cb`)
**Produced by:** `packaging/macos-app.sh`

Build (no longer blocked — see the correction below):

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

**Correction, observed 2026-09-18: this section previously reported `BLOCKED`, and that
report was wrong.** The blocker was not external. It was two local defects, and both were
fixed on this host without `sudo` and without touching source.

1. **The asset build was not pinned.** `xcodebuild -downloadComponent MetalToolchain` asks
   the `gdmf.apple.com` catalog for `RequestedBuild = 17B5050g` (the installed Xcode 26.0
   build). `~/Library/Developer/Xcode/XcodeToMetalToolchainIndexMapping.plist` has no entry
   for that build — its `17B5*` entries stop at `17B5045g` — so the request has no target
   and the command exits **70** with
   `Failed fetching catalog for assetType (com.apple.MobileAsset.MetalToolchain)`.
   Pinning a build that *is* mapped succeeds:

   ```bash
   $ xcodebuild -downloadComponent MetalToolchain -buildVersion 17B5045g
   Downloaded asset to: /System/Library/AssetsV2/com_apple_MobileAsset_MetalToolchain/c3195e2b….asset/AssetData/Restore/022-20562-020.dmg
   Done downloading: Metal Toolchain 17B5045g.
   $ echo $?
   0
   ```

   A first attempt can exit 70 with `Download is not allowed as mobileassetd was starting
   up.` — that is transient; the retry succeeds. `cryptexd` then mounts the asset read-only
   as `MetalToolchainCryptex`, containing a working compiler:
   `Apple metal version 32023.830 (metalfe-32023.830.2)` (exit 0).

2. **Xcode never linked the graft into its toolchain.** `xcrun metal` is a thin shim that
   resolves `XcodeDefault.xctoolchain/usr/metal/current/bin/<argv[0]>`; it links only
   libc++/libSystem, so it reads no plist, and nothing had created `usr/metal`. Two symlinks
   inside the (user-owned) `Xcode.app` closed it: `usr/metal` → the cryptex's `usr/metal`,
   and `usr/bin/metallib` → `metal`, because that shim dispatches on the executable name.

The probe then reports:

```
status: ok
detail: xcodebuild: Xcode 26.0 Build version 17B5050g
detail: developer dir: /Applications/Xcode.app/Contents/Developer
detail: metal compiler: usable
detail: codesigning identity: 1+ Developer ID Application present (of 3 valid)
detail: notarytool credentials: NOT configured (notarization impossible on this host)
```

Full command log with exit codes, the throwaway-tree experiments that located the graft
point, and the alternatives that were tested and rejected:
[`sessions/20260918-macos-app-unblock/01_RESEARCH.md`](sessions/20260918-macos-app-unblock/01_RESEARCH.md).

**Two caveats keep the WBS clause open.** First, the fix is **not durable**: both symlinks
resolve through a cryptex mount whose path carries a per-mount suffix, and neither is
restored after a reboot or an Xcode upgrade. Second, the bundle has **not been launched** in
a GUI session and is **not notarized**, so "install and run" is not demonstrated. What *is*
demonstrated: the bundle builds (exit 0), signs, verifies
(`codesign --verify --deep --strict` → *valid on disk*, *satisfies its Designated
Requirement*), hashes to `94abd2a7…`, and its binary executes non-interactively
(`Contents/MacOS/ghostty --version` → `Ghostty 1.3.2-main-+41b24baad`, exit 0).

Two further facts from the probe, unchanged: a Developer ID Application identity *is*
present (1 of 3 valid identities), so the script signs with it rather than ad-hoc; and
notarytool credentials are not configured, so notarization is impossible here regardless.
An app launch is also meaningless outside a logged-in GUI session, which this host does not
have.

### 3.4 Linux — `.deb`

Two different `.deb`s belong to this section and they have different status.
§3.4.1 is the GTK application package; §3.4.2 is the libghostty-vt library
package, which is the one that has actually been installed and run.

#### 3.4.1 `khostty_0.1.0_amd64.deb` — GTK application — BUILT + INSTALL-VERIFIED (2026-09-19)

The build enables both Wayland and X11 display backends (the default
`gtk_targets` on Linux) plus `gtk4-layer-shell`, which only has an effect on the
Wayland backend (window positioning/anchoring). Neither backend can be exercised
without a desktop session, so both remain unverified at runtime on this host.

**Artifact:** `dist/khostty_0.1.0_amd64.deb` — 18,143,964 bytes,
`sha256 63d4e6159d65e97db685b9eedbe19c37765f5f838279e9d5b0326ab5a7b80de0`
(supersedes `209ba5ed10abfe4e1a0caf4fb5da9bd16e7fc375b49254c46149d523652d713a`,
which had the stale glibc floor, see blocker 3).
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

**Status (2026-09-19).** The build **exits 0 in WSL Fedora 44** and produces the
artifact above. Two earlier blockers are fixed:

1. **Cross-compile mis-target (fixed `9daf736e8`).** `deb.sh` passed
   `-Dtarget=x86_64-linux-gnu` unconditionally. On a native x86_64 Linux host
   that makes Zig treat the build as a cross-compile, so it refuses to link the
   system shared libraries:

   ```
   error: unable to find dynamic system library 'gobject-2.0'
          using strategy 'paths_first'. searched paths: none
   ```

   The target is now conditional on the host: on native x86_64 Linux no
   `-Dtarget` is passed and the system GTK4/libadwaita link normally.

2. **Icon set and desktop Icon ref (fixed `45e6d086b`).** The icon block
   converted the upstream `.ico` into a single 512x512 PNG; without a 512px
   source frame ImageMagick instead wrote numbered files (`-0`..`-4`, up to
   256px) into one directory. It now extracts the largest embedded frame and
   resizes it into size-matched hicolor paths (16/24/32/48/256/512, verified in
   the built package). `dist/linux/app.desktop.in` hard-coded
   `Icon=com.mitchellh.ghostty`; it now uses `Icon=@APPID@`
   (`com.khostty.Khostty`), matching the installed icon names and the
   `.metainfo` id — confirmed by extracting the built package.

**Install-verify (executed 2026-09-19).** The package **was installed and driven
on the WSL Fedora 44 host** (glibc 2.43) after the glibc-floor fix
(`65de471df`): `dpkg -i` (with `--force-depends`, needed only because the host's
dpkg database has no `libc6` entry even though it runs glibc 2.43 binaries) →
`Status: install ok installed`; `dpkg -V` clean; `dpkg -L` lists
`/usr/bin/khostty`, the `.desktop`, the metainfo, and the 6 hicolor PNGs;
`ldd` on the installed binary resolves everything; `desktop-file-validate` OK;
metainfo XML well-formed; the installed `/usr/bin/khostty +version` → exit 0
(`Ghostty 1.3.2-main-+65de471df`); `gio info` reads the desktop entry;
`dpkg --purge` leaves no residual files.

**Negative control (Debian 12 bookworm, glibc 2.36, container on the WSL
host).** `dpkg -i` unpacks the package (`install ok unpacked`) but
`dpkg --configure -a` **refuses**: `khostty depends on libc6 (>= 2.43);
however: Version of libc6:amd64 on system is 2.36-9+deb12u14`. With the
superseded build (`209ba5ed…713a`, floor `libc6 (>= 2.17)`) the same container
installed and *configured* cleanly and the binary then failed at load
(`version 'GLIBC_2.43' not found`) — the exact defect the floor fix removes.

**GUI launch (headless Xvfb, 2026-09-19).** With no desktop session on the WSL
host, the installed app (`dpkg -i --force-depends`, 0.1.0, artifact sha256
`63d4e615…de0`) was launched headless: `Xvfb :99 -screen 0 1280x800x24 -nolisten
tcp`, then `dbus-run-session -- bash -c 'DISPLAY=:99 GSK_RENDERER=cairo
/usr/bin/khostty …'`. The process stayed alive (`APP_ALIVE`) and the stderr log
shows the full GTK init chain with zero errors: ghostty 1.3.2-main-+65de471df,
`runtime=.gtk`, GTK 4.22.5 runtime, libadwaita 1.9.4 runtime,
fontconfig/freetype, io_uring, and the template config file created at
`/root/.config/ghostty/config.ghostty`. **Scope limits:** xwininfo/xwd are not
installable on Fedora 44 (xorg-x11-utils and xorg-x11-apps do not provide them),
so window-tree enumeration and a screenshot capture were not possible; window
presence is evidenced by process aliveness plus a successful GTK/GDK init under
a real X server connection, not by a captured window image. The app was purged
afterward (`PURGED_OK`, 0 residuals). Raw log:
`sessions/20260916-fork-assessment/evidence/khostty_gui_launch_xvfb_2026-09-19.log`.

#### 3.4.2 `khostty-vt_0.1.0_amd64.deb` — libghostty-vt library — VERIFIED

**Artifact:** `dist/khostty-vt_0.1.0_amd64.deb` — 2,320,612 bytes,
`sha256 3c080d13a74d6bf6dca9d28dc2c685f6b4350ec3130f3f3fafa5cb4d77d834cf`,
computed twice with independent tools (`shasum -a 256` and `openssl dgst
-sha256`).
**Produced by:** `packaging/linux/deb-libvt.sh` (new).

This is a different payload, not a relabelled substitute. libghostty-vt is the
only Khostty artifact that cross-compiles from macOS to `x86_64-linux-gnu`. It is
a real x86-64 Linux ELF — `file` reports `ELF 64-bit LSB shared object, x86-64`,
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

The archive holds 54 entries: 39 regular files, 2 symlinks
(`libghostty-vt.so` → `.so.0` → `.so.0.1.0`), and 13 directories, including 34
headers under `/usr/include/ghostty/vt/`. The first `ar` member is
`debian-binary`, and `debian-binary` reads exactly `2.0`.

Install-and-run verification — executed, not inferred:

```bash
bash packaging/linux/deb-libvt.sh --verify   # exit 0
```

observed in an `x86_64` `debian:bookworm` container (Debian 12.15, glibc 2.36) on
this host, launched with `docker run --platform linux/amd64` with the repository
mounted read-only:

| Check | Observed |
|---|---|
| `dpkg -i dist/khostty-vt_0.1.0_amd64.deb` | exit 0; `Setting up khostty-vt (0.1.0) ...`; `dpkg -s` → `Status: install ok installed` |
| `dpkg -L khostty-vt` | 54 entries, including `/usr/lib/x86_64-linux-gnu/libghostty-vt.so.0.1.0`, `.../libghostty-vt.so.0`, `.../libghostty-vt.so`, `/usr/include/ghostty/vt.h`, the `vt/**` headers, and `.../pkgconfig/libghostty-vt.pc` |
| `dpkg -V khostty-vt` | no modified or missing files — the package's `md5sums` integrity holds |
| `ldconfig -p \| grep ghostty` | `libghostty-vt.so.0 (libc6,x86-64) => /lib/x86_64-linux-gnu/libghostty-vt.so.0` |
| `gcc example/c-vt-formatter/src/main.c -lghostty-vt` | compiled against the **installed** headers and the **installed** `.so`; ran and printed the formatted 80×24 screen |
| functional assertions | 4/4 PASS — literal text, `CSI 2K` erase-and-rewrite, CUP placement at (5,10), right-edge clamp |
| `dpkg -r khostty-vt` | exit 0; clean removal |

**What this does not prove.** The GTK application `.deb` is still not built, so
"the Khostty terminal *application* installs and runs from a `.deb`" remains
**unverified** — §3.4.1 records exactly what is missing. The container is an
emulated x86-64 userspace on Apple Silicon rather than bare-metal Debian, and it
is not a desktop session, so this validates package metadata, file layout, loader
resolution and the library's C ABI, not a GUI launch. No `apt`-repository install
path was exercised. The WBS 9.15 acceptance bullet for the Linux `.deb` is
therefore satisfied for the library payload only, and is stated that way in the
status table above.

### 3.5 Windows — `.exe` installer — BUILT + install-verified 2026-09-19

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

**Status, observed 2026-09-19. The installer is BUILT and was installed, run and
uninstalled.** Inno Setup 6.7.1 was installed on the Windows runner `kooshapari-desk`
(via Chocolatey), and the staged `khostty.iss` was compiled:

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

The earlier 2026-09-18 probe output, kept for contrast (this host, no Windows host
tried yet):

```
$ bash packaging/windows/installer.sh --probe
    zig: 0.16.0 (/opt/homebrew/bin/zig)
    ISCC.exe: MISSING (install Inno Setup 6.3+, or set KHOSTTY_ISCC)
    wine: not needed yet (ISCC.exe itself is missing)
status: blocked
```

Verified present and hashed on this host:

| Staged payload file | Size | SHA-256 |
|---|---|---|
| `ghostty.exe` | 43,470,336 B (41.4 MiB) | `df0b4c87…` |
| `ghostty-vt.dll` | 7,545,344 B (7.1 MiB) | `b4cff87e…` |
| `ghostty.ico` | 86,258 B | — |
| `LICENSE` | 1,097 B | — |

`dist-release/stage/windows/Khostty-0.1.0-win64/khostty.iss` is the generated
Inno definition (stable `AppId {14bf69b1-ddd1-54e3-81bc-898bdbacb251}`, a UUIDv5
of `khostty.com`, so upgrades replace rather than accumulate). Compile it on
Windows with:

```
ISCC.exe khostty.iss
```

or anywhere else with `wine ISCC.exe khostty.iss`. `makensis` (NSIS) and `wix`
(WiX) are alternatives the script detects and reports but does not drive.

**What is not verified:** that the payload runs, that the installer completes,
and that an uninstall is clean. macOS cannot execute PE32+ binaries, there is no
wine on this host, and no Windows host was available. The script's own
`EVIDENCE.txt` records `install_verified: NO` and is written only by a full build,
so its absence is itself consistent with the installer never having been compiled.

### 3.6 Windows — payload binaries only — VERIFIED as artifacts

If you want the terminal binaries without the installer, build them directly with
`zig` and copy them wherever you like:

```bash
zig build -Dtarget=x86_64-windows-gnu -Dapp-runtime=windows \
  -Demit-macos-app=false -Doptimize=ReleaseFast      # -> zig-out/bin/ghostty.exe
zig build -Dtarget=x86_64-windows-gnu -Demit-lib-vt -Doptimize=ReleaseFast  # -> zig-out/bin/ghostty-vt.dll
```

These are the two invocations `packaging/windows/installer.sh` performs. They were
**not** re-run during this documentation pass; what was checked on 2026-09-18 is
that the resulting artifacts exist in `zig-out/bin/` and that `file` reports:

```
zig-out/bin/ghostty.exe:    PE32+ executable (GUI) x86-64, for MS Windows
zig-out/bin/ghostty-vt.dll: PE32+ executable (DLL) (GUI) x86-64, for MS Windows
```

The cross-compile itself was recorded as exit 0 when the payload was built
(probe timestamp 2026-09-18T08:23:00Z for `ghostty.exe`). Treat that as a
second-hand record, not a fresh observation.

Windows consumers must ship `ghostty.exe` and `ghostty-vt.dll` **together**; the
`.dll` is the ABI the executable and any C/Rust/Go/Python consumer link against.
A `.pdb` is emitted alongside each — useful for debugging, not required at
runtime.

---

## 4. Evidence log for 2026-09-18

Every command in this section was executed on this host on 2026-09-18. Nothing
here is inferred.

| Check | Command | Result |
|---|---|---|
| Version resolution | `bash packaging/version.sh` | `0.1.0 (dev)`, upstream base `ghostty 1.3.2-dev @ d4c88d8`, source `c2bac90` (dirty) |
| macOS toolchain | `bash packaging/macos-app.sh --probe` | `status: ok` — `metal compiler: usable` (was `blocked`; corrected 2026-09-18, §3.3) |
| Metal compiler | `xcrun metal --version` | exit 0, `Apple metal version 32023.830 (metalfe-32023.830.2)` (was exit 1 / missing toolchain) |
| Metal linker | `xcrun metallib --version` | exit 0, `AIR-LLD 32023.830 (metalfe-32023.830.2)` — required for the `metallib` step; needed its own shim |
| Metal asset fetch | `xcodebuild -downloadComponent MetalToolchain` | **exit 70**, `Failed fetching catalog … RequestedBuild = 17B5050g` (no mapping entry) |
| Metal asset fetch (pinned) | `xcodebuild -downloadComponent MetalToolchain -buildVersion 17B5045g` | **exit 0**, `Done downloading: Metal Toolchain 17B5045g.` (704.6 MB; first attempt exited 70 with a transient `mobileassetd was starting up`) |
| macOS `.app` build | `bash packaging/macos-app.sh` | **exit 0**; built, signed, `codesign --verify` passed, zip written |
| macOS `.app` artifact | `shasum -a 256 -c Khostty-0.1.0-macos.zip.sha256` | `Khostty-0.1.0-macos.zip: OK`; 35,953,098 B |
| macOS `.app` liveness | `zig-out/Ghostty.app/Contents/MacOS/ghostty --version` | exit 0, `Ghostty 1.3.2-main-+41b24baad` — non-interactive; **not** a GUI launch |
| Linux toolchain | `bash packaging/linux/deb.sh --probe` | exit 0; `zig 0.16.0`, `dpkg-deb: /opt/homebrew/bin/dpkg-deb` (was `MISSING` before `brew install dpkg`) |
| dpkg assembler install | `brew install dpkg` | exit 0; poured `dpkg 1.23.11` + deps `gnu-tar`, `gpatch`, `libmd`, `perl`; caveat printed: `dpkg -i`/`--configure` are not configured to install software, but `dpkg-deb` builds and reads archives |
| Linux GTK-app `.deb` build | `bash packaging/linux/deb.sh` | **exit 1.** Reaches the build step and dies on missing target headers: `adw_c.h:1:10: fatal error: 'adwaita.h' not found`, `gtk_c.h:1:10: fatal error: 'gtk/gtk.h' not found`, `error: the following build command failed with exit code 1`. Assembler is no longer the blocker. |
| Linux library `.deb` build | `bash packaging/linux/deb-libvt.sh --probe` then `bash packaging/linux/deb-libvt.sh` | probe exit 0; build exit 0; produced `dist/khostty-vt_0.1.0_amd64.deb` |
| Linux library `.deb` structure | `dpkg-deb --info` / `--contents` / `ar t` on the artifact | all exit 0; `ar t` → `debian-binary`, `control.tar.xz`, `data.tar.xz` (first member `debian-binary`, contents `2.0`); 54 entries (39 files, 2 symlinks, 13 dirs) |
| Linux library `.deb` install + run | `bash packaging/linux/deb-libvt.sh --verify` (exit 0) | **PASS.** x86-64 `debian:bookworm` (12.15, glibc 2.36) under `docker run --platform linux/amd64`: `dpkg -i` exit 0 → `Status: install ok installed`; `dpkg -V` no modified/missing files; `ldconfig -p` resolves `libghostty-vt.so.0`; `example/c-vt-formatter` compiles against the installed headers and `.so` and passes 4/4 VT assertions; `dpkg -r` exit 0 |
| Windows installer | `bash packaging/windows/installer.sh --probe`; `ISCC.exe khostty.iss` on Windows | **PASS 2026-09-19.** Compiled the staged `khostty.iss` with Inno Setup 6.7.1 → `Khostty-0.1.0-windows-x86_64-setup.exe` (`4070e89e…095546`); silent install → payload hashes MATCH; installed exe runs; silent uninstall → 0 residual files |
| WASM tarball integrity | `cd dist-release/wasm && shasum -a 256 -c khostty-libghostty-vt-wasm-0.1.0.tar.gz.sha256` | `khostty-libghostty-vt-wasm-0.1.0.tar.gz: OK`, exit 0 |
| WASM tarball consumer test | extract to scratch, `node smoke.mjs --json` | 13/13 checks, 0 failed, exit 0 |
| WASM direct import | `import { openTerminal } from "./js/api.js"`, then `write` + `text()` | `text() = "hello"`, exit 0 |
| WASM repository suite | `node --test --test-reporter=tap test/` | `# tests 54`, `# pass 54`, `# fail 0` |
| macOS library behaviour | `bash conformance/build.sh run` | Passed 84, Failed 0, Success Rate 100% across 8 categories |
| macOS library install | `zig build -Demit-lib-vt -Doptimize=ReleaseSafe --prefix <scratch>` (fresh cache, 8m16s) | exit 0; prefix contained `include/ghostty/`, `lib/libghostty-vt.0.1.0.dylib` + 2 symlinks, `lib/libghostty-vt.a`, `lib/ghostty-vt.xcframework`, `share/man`, `share/pkgconfig` |
| macOS library consume | `cc -isysroot <Xcode SDK> -I <prefix>/include … -L <prefix>/lib -lghostty-vt -Wl,-rpath,<prefix>/lib` then run | compile OK; `RESULT: PASS`, `version_string = 0.1.0-dev`, `optimize = 1` |
| CLT SDK linking (negative result, recorded) | `cc` without `-isysroot` | `ld: tapi error: malformed file` against `MacOSX27.0.sdk/…/libSystem.B.tbd` — Command Line Tools SDK problem, worked around with `-isysroot <Xcode SDK>` |
| Windows payload type | `file zig-out/bin/ghostty.exe zig-out/bin/ghostty-vt.dll` | both PE32+ x86-64 |

### Artifact hashes observed 2026-09-18

| Artifact | Bytes | SHA-256 |
|---|---|---|
| `khostty-vt_0.1.0_amd64.deb` | 2,320,612 | `3c080d13a74d6bf6dca9d28dc2c685f6b4350ec3130f3f3fafa5cb4d77d834cf` |
| `libghostty-vt.0.1.0.dylib` | 7,685,808 | `bc74fa7171e3abceb7e32904266cb23876c50a1313f6f65cd7b92c34a962642a` |
| `wasm/khostty-vt.wasm` | 813,670 | `08ac8ed881ffdae68b9f96f9afa6c834e57ba7ea49280d220e882938508e5bf6` |
| `khostty-libghostty-vt-wasm-0.1.0.tar.gz` | 680,598 | `55cfc67572696db9eaf48cb69ae231ca99119aa1caf064e0c08c8c8c178604dc` |
| `zig-out/bin/ghostty.exe` | 43,470,336 | `df0b4c8772ad5de8c65078cf0ade6645ad16601b1b4ca37097e314abf028d03e` |
| `zig-out/bin/ghostty-vt.dll` | 7,545,344 | `b4cff87e6ee95dd97e0872fdaf752122aceb4f7536662f6ceadf3905eae6654f` |

These hashes describe the bytes on this host at the stated time. They are not a
release manifest: this repository rebuilds under concurrent edit, and a rebuilt
artifact will not match. For the release manifest itself see
`packaging/version.sh --json` and the per-target `EVIDENCE.txt` files written by
each packaging script.

Note also that `dist-release/` (`.gitignore` line 41) and `zig-out/` are
gitignored. Every path in this document that starts with those two prefixes is
**local build output that is not in git**. That is why this document quotes
hashes and probe output rather than linking to a committed manifest: the only
durable record of what was built is the one reproduced here and in each script's
`EVIDENCE.txt`.

---

## 5. What would change these statuses

1. **macOS `.app`** — **build closed 2026-09-18.** The Metal toolchain was obtained on this
   host by pinning the asset build and adding the graft Xcode failed to create (§3.3), after
   which `bash packaging/macos-app.sh` exited 0. Two things still change this status:
   (a) a **reboot or Xcode upgrade** silently undoes the fix, because the symlinks resolve
   through a per-boot cryptex mount name — re-run the two `ln -sfn` commands from §3.3,
   or use an Xcode whose build appears in `XcodeToMetalToolchainIndexMapping.plist`;
   (b) the WBS "installs and runs" clause needs the `.app` copied **outside** the source
   tree and launched in a real GUI session, which has not been done. Notarization remains
   impossible without `notarytool` credentials.
2. **Linux `.deb` (GTK application)** — run `bash packaging/linux/deb.sh` on a
   Debian/Ubuntu host with the GTK4 and libadwaita development packages for
   `x86_64-linux-gnu`. The probe already reports `dpkg-deb`; the build step is
   what fails on the missing target headers.
3. **Linux `.deb` (libghostty-vt library)** — **closed 2026-09-18.** §3.4.2
   records the artifact, its hash, and an executed `dpkg -i` + run. Re-run
   `bash packaging/linux/deb-libvt.sh --verify` after any change to the VT core;
   the pass describes the library built on 2026-09-18, not the current tree.
4. **Windows `.exe`** — install Inno Setup 6.3+ on a Windows host and run
   `bash packaging/windows/installer.sh`, or set `KHOSTTY_ISCC` and add wine on a
   POSIX host. The `.iss` is generated with `ArchitecturesAllowed=x64compatible`,
   which requires Inno 6.3 or newer; on 6.0–6.2 substitute `x64`.
5. **macOS library** — already verified; re-run `bash conformance/build.sh run`
   after any change to the VT core, because the 84/84 pass describes the library
   built on 2026-09-18, not the current source tree.
6. **Documentation consistency** — [BUILD.md](BUILD.md) and
   [README.md](README.md) still state, as of 2026-09-17, that the committed
   revision does not build. A `zig build -Demit-lib-vt` from the working tree
   succeeded on 2026-09-18 (§3.2), so those dated claims are stale. They were not
   edited here because this change is scoped to installation documentation.

---

## See also

- [BUILD.md](BUILD.md) — compiling from source, flag reference, build troubleshooting
- [TESTING.md](TESTING.md) — the conformance suite and every other test surface
- [PLATFORMS.md](PLATFORMS.md) — the support matrix these artifacts map onto
- [AGENT.md](AGENT.md) — driving the installed binary from an agent
- `packaging/lib.sh` — the shared rules every packaging script follows, including
  "never fabricate a result"
- `packaging/linux/deb-libvt.sh` — the libghostty-vt `.deb`; `--probe`, plain,
  and `--verify` (installs and runs the package in an x86-64 Debian container)
- `packaging/version.sh` — the single source of truth for the version number
