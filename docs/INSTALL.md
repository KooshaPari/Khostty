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
| 1 | `khostty-libghostty-vt-wasm-0.1.0.tar.gz` | any — Node ≥ 20 / browser | VERIFIED | Tarball `sha256 ce5d1f1d…` matches the sidecar `.sha256` written beside it, verified with `shasum -a 256 -c` (exit 0). Freshly extracted to a scratch directory and `node smoke.mjs --json` returned 13/13 checks, 0 failed, exit 0. A direct `import` of the extracted `js/api.js` opened a terminal and echoed text back. Repository WASM suite re-run the same day: 54 tests, 54 pass, 0 fail. |
| 2 | `libghostty-vt.0.1.0.dylib` + `include/ghostty/` headers | macOS arm64 | VERIFIED | `zig build -Demit-lib-vt -Doptimize=ReleaseSafe --prefix <scratch>` installed a prefix (exit 0); a C program including the **installed** headers and linking the **installed** dylib compiled, ran, and printed `RESULT: PASS` with the library reporting `0.1.0-dev` (see §3.2). Conformance harness against the built library: 84/84 passed, 0 failed. |
| 3 | `Khostty-0.1.0-macos.zip` — the `Ghostty.app` bundle | macOS | BLOCKED | `packaging/macos-app.sh --probe` reports `status: blocked`. `xcrun metal --version` exits 1: `cannot execute tool 'metal' due to missing Metal Toolchain`. The metallib step is unconditional for macOS targets, so no `.app` can be produced here. No bundle exists in the tree. |
| 4 | `khostty_0.1.0_amd64.deb` | Debian / Ubuntu x86-64 | NOT BUILT | `bash packaging/linux/deb.sh --probe` runs (exit 0) and reports `zig: 0.16.0`, `dpkg-deb: MISSING`. Assembling a `.deb` requires `dpkg-deb`; the payload inside it additionally requires a Linux/GTK build, which this macOS host cannot produce. No `.deb` exists in the tree. |
| 5 | `Khostty-0.1.0-windows-x86_64-setup.exe` | Windows x86-64 | NOT BUILT | `bash packaging/windows/installer.sh --probe` runs (exit 0) and reports `status: blocked`, `ISCC.exe: MISSING`. The installer payload and the generated `khostty.iss` are staged and hashed, but Inno Setup has never compiled them. |
| 6 | `ghostty.exe` + `ghostty-vt.dll` (row 5's payload) | Windows x86-64 | VERIFIED | Both are real PE32+ files built 2026-09-18 (43.5 MB and 7.5 MB), staged and hashed 2026-09-18T03:33 local. `file` confirms `PE32+ executable (GUI) x86-64` and `PE32+ executable (DLL)`. **They have not been executed**: macOS cannot run PE binaries and no wine or Windows host is present. |

**No row in this table claims a runtime test that was not run.** Rows 1 and 2 are
the only rows whose checks were executed end to end on 2026-09-18. Row 6 is
verified as a *build product*, not as a running program.

### What is still missing for the WBS 9.15 acceptance criteria

[`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](sessions/20260916-fork-assessment/02_DEEP_WBS.md)
requires that the macOS `.app`, the Linux `.deb`, and the Windows `.exe` each
"install and run". None of those three can be demonstrated from this host: each
needs a toolchain or an operating system that is not available here. §5 lists,
per artifact, the exact requirement that is missing and where it can be met. The
fourth criterion — the WASM dist being consumable via npm/ESM — **is** satisfied,
observed 2026-09-18 (§3.1).

---

## 2. Host requirements

| Target | Build host | Install/verify host | Tools the build host must have |
|---|---|---|---|
| WASM tarball | macOS or Linux | any (Node ≥ 20) | `zig` 0.16.0, `node`, `tar`, `gzip` |
| macOS library | macOS | macOS | `zig` 0.16.0, `cc`; Metal toolchain **not** required for `-Demit-lib-vt` |
| macOS `.app` | macOS | macOS with a GUI session | `zig` 0.16.0, Xcode, **Metal Toolchain component** |
| Linux `.deb` | Linux (cross-build from macOS is not viable: the payload needs GTK4 for the target) | Debian/Ubuntu x86-64 | `zig` 0.16.0, `dpkg-deb` |
| Windows installer | any host with `zig` | Windows x86-64 | `zig` 0.16.0, Inno Setup 6.3+ (`ISCC.exe`); on a non-Windows host also `wine` + `winepath` |

All packaging scripts accept a probe mode that only *reports* readiness and
changes nothing. Run it first on any new host:

```bash
bash packaging/version.sh                # resolved version + upstream base
bash packaging/macos-app.sh --probe      # writes dist-release/macos/toolchain-probe.txt
bash packaging/linux/deb.sh --probe      # prints, writes nothing
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

### 3.3 macOS — the `.app` bundle — BLOCKED

**Artifacts (neither exists):** `zig-out/Ghostty.app`,
`dist-release/macos/Khostty-0.1.0-macos.zip`
**Produced by:** `packaging/macos-app.sh`

Build (once the blocker below is cleared):

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

**Blocker, observed 2026-09-18.** `packaging/macos-app.sh --probe` reports
`status: blocked` and writes the detail to
`dist-release/macos/toolchain-probe.txt`:

```
detail: xcodebuild: Xcode 26.0 Build version 17B5050g
detail: metal compiler: NOT USABLE (exit 1)
detail: error: cannot execute tool 'metal' due to missing Metal Toolchain; use: xcodebuild -downloadComponent MetalToolchain
detail: notarytool credentials: NOT configured (notarization impossible on this host)
```

`xcrun metal --version` exits 1 on this host, confirmed independently:

```bash
$ xcrun metal --version
error: error: cannot execute tool 'metal' due to missing Metal Toolchain; use: xcodebuild -downloadComponent MetalToolchain
$ echo $?
1
```

The remediation (`xcodebuild -downloadComponent MetalToolchain`) also fails here,
because the asset catalog cannot be fetched for this Xcode build. The `.metallib`
step in the app chain is unconditional for macOS targets
(`src/build/MetallibStep.zig` returns null only for non-macOS), so the fallback
to the OpenGL renderer that lets `zig build` succeed does **not** unblock the
`.app`.

Two further facts from the same probe, relevant on a host where Metal does work:
a Developer ID Application identity *is* present (1 of 3 valid identities), so the
script would sign with it rather than ad-hoc; and notarytool credentials are not
configured, so notarization is impossible here regardless. A launch test is also
meaningless outside a logged-in GUI session, which this host does not have.

### 3.4 Linux — `.deb` — NOT BUILT

**Artifact (does not exist):** `dist/khostty_0.1.0_amd64.deb`
**Produced by:** `packaging/linux/deb.sh`

Build, on a Linux host:

```bash
bash packaging/linux/deb.sh
# or, for toolchain readiness only:
bash packaging/linux/deb.sh --probe
```

Install:

```bash
sudo dpkg -i dist/khostty_0.1.0_amd64.deb
# or, letting the package manager resolve libc6 / libgcc-s1:
sudo apt install ./dist/khostty_0.1.0_amd64.deb
```

Verify:

```bash
dpkg -s khostty | grep -E '^(Status|Version|Architecture):'
#    expected: Status: install ok installed

dpkg -L khostty | grep -E '/usr/bin/khostty|applications/.*desktop|metainfo/'
#    expected: /usr/bin/khostty, the .desktop, and the metainfo.xml

ldd "$(command -v khostty)" | grep 'not found'    # expected: no output
desktop-file-validate /usr/share/applications/com.khostty.Khostty.desktop
khostty +version                                   # expected: prints the Ghostty/Khostty version block

# Desktop integration actually registered
update-desktop-database ~/.local/share/applications 2>/dev/null || true
gio info /usr/share/applications/com.khostty.Khostty.desktop >/dev/null && echo "desktop entry readable"
```

**Status, observed 2026-09-18.** The script is present and its probe runs green,
but the `.deb` has never been produced:

```
$ bash packaging/linux/deb.sh --probe
packaging/linux/deb.sh --probe
  VERSION:        0.1.0
  zig:            0.16.0
  dpkg-deb:       MISSING (install dpkg)
  Output:         /Users/kooshapari/CodeProjects/Phenotype/repos/khostty/dist/khostty_0.1.0_amd64.deb
```

Two distinct gaps: the assembler (`dpkg-deb`) is absent, and the payload is a
Linux GTK build (`zig build -Dtarget=x86_64-linux-gnu -Dapp-runtime=gtk`) that
needs GTK4 development headers for the target, which this macOS host does not
have. `dist/` in the tree contains upstream packaging *templates* only. The verify
commands above are therefore **documented but unexecuted**; treat them as the
checklist to run on the Linux host, not as evidence.

### 3.5 Windows — `.exe` installer — NOT BUILT

**Artifact (does not exist):**
`dist-release/windows/stage/Khostty-0.1.0-win64/output/Khostty-0.1.0-windows-x86_64-setup.exe`
**Produced by:** `packaging/windows/installer.sh`

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

**Status, observed 2026-09-18.** The payload and the Inno script are staged, but
the installer has never been compiled:

```
$ bash packaging/windows/installer.sh --probe
    zig: 0.16.0 (/opt/homebrew/bin/zig)
    ISCC.exe: MISSING (install Inno Setup 6.3+, or set KHOSTTY_ISCC)
    wine: not needed yet (ISCC.exe itself is missing)
    input ghostty.exe:    41.4 MiB (built 2026-09-18T08:23:00Z)
    input ghostty-vt.dll: 7.1 MiB (built 2026-09-18T08:22:36Z)
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
| macOS toolchain | `bash packaging/macos-app.sh --probe` | `status: blocked` — Metal toolchain missing |
| Metal compiler | `xcrun metal --version` | exit 1, `cannot execute tool 'metal' due to missing Metal Toolchain` |
| Linux toolchain | `bash packaging/linux/deb.sh --probe` | exit 0; `zig 0.16.0`, `dpkg-deb: MISSING` |
| Windows toolchain | `bash packaging/windows/installer.sh --probe` | exit 0; `status: blocked`, `ISCC.exe: MISSING` |
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
| `libghostty-vt.0.1.0.dylib` | 7,685,808 | `bc74fa7171e3abceb7e32904266cb23876c50a1313f6f65cd7b92c34a962642a` |
| `wasm/khostty-vt.wasm` | 813,670 | `08ac8ed881ffdae68b9f96f9afa6c834e57ba7ea49280d220e882938508e5bf6` |
| `khostty-libghostty-vt-wasm-0.1.0.tar.gz` | 680,607 | `ce5d1f1dfcf03cade7add0c6564b72b2690b496859e5c91fd432234db655c709` |
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

1. **macOS `.app`** — obtain the Metal Toolchain component on a host whose asset
   catalog serves it, then `bash packaging/macos-app.sh`. Expect an ad-hoc
   signature unless a Developer ID Application identity is present, and no
   notarization without notarytool credentials.
2. **Linux `.deb`** — run `bash packaging/linux/deb.sh` on a Debian/Ubuntu host
   with GTK4 dev packages. The probe must stop reporting `dpkg-deb: MISSING`.
3. **Windows `.exe`** — install Inno Setup 6.3+ on a Windows host and run
   `bash packaging/windows/installer.sh`, or set `KHOSTTY_ISCC` and add wine on a
   POSIX host. The `.iss` is generated with `ArchitecturesAllowed=x64compatible`,
   which requires Inno 6.3 or newer; on 6.0–6.2 substitute `x64`.
4. **macOS library** — already verified; re-run `bash conformance/build.sh run`
   after any change to the VT core, because the 84/84 pass describes the library
   built on 2026-09-18, not the current source tree.
5. **Documentation consistency** — [BUILD.md](BUILD.md) and
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
- `packaging/version.sh` — the single source of truth for the version number
