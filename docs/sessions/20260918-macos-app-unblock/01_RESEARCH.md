# 2026-09-18 — Research log: Metal toolchain on this host

Every command below was executed on this host on 2026-09-18 (times local, UTC−07:00).
Exit codes are the observed ones. Nothing here is inferred.

## 1. Baseline — the recorded blocker reproduces

| # | Command | Exit | Observed |
|---|---|---|---|
| 1 | `xcode-select -p` | 0 | `/Applications/Xcode.app/Contents/Developer` |
| 2 | `xcodebuild -version` | 0 | `Xcode 26.0` / `Build version 17B5050g` |
| 3 | `xcrun -sdk macosx metal --version` | **1** | `error: cannot execute tool 'metal' due to missing Metal Toolchain; use: xcodebuild -downloadComponent MetalToolchain` |
| 4 | `xcodebuild -downloadComponent MetalToolchain` | **70** | `Failed fetching catalog for assetType (com.apple.MobileAsset.MetalToolchain), serverParameters ({ RequestedBuild = 17B5050g; })` |
| 5 | `bash packaging/macos-app.sh --probe` | 0 | prints `blocked`, writes `dist-release/macos/toolchain-probe.txt` |

So the recorded failure was accurate for the exact command recorded — and `#4` is the
command the script tells the operator to run.

## 2. Network and daemon are healthy — the failure is not connectivity

| # | Command | Exit | Observed |
|---|---|---|---|
| 6 | proxy vars via `printenv` | 0 | all empty — no proxy configured |
| 7 | `curl -s -o /dev/null -w '%{http_code}' https://gdmf.apple.com/` | 0 | `404` (host reachable, 1.1 s) |
| 8 | `curl … https://mesu.apple.com/`, `swcdn.apple.com` | 0 | `404`, reachable |
| 9 | `curl … https://developer.apple.com/` | 0 | `200` |
| 10 | `ps aux \| grep mobileasset` | 0 | `mobileassetd` running (PID 7478) |
| 11 | `launchctl print system/com.apple.mobileassetd` | 0 | `state = running` |

`gdmf.apple.com/v2/assets` is the asset server, and it answers. The "Failed fetching
catalog" message was therefore **not** a network fault.

## 3. Where the toolchain lives — nothing usable pre-installed

| # | Command | Exit | Observed |
|---|---|---|---|
| 12 | `ls /Applications \| grep -i xcode` | 0 | only `Xcode.app` |
| 13 | `mdfind 'kMDItemCFBundleIdentifier == "com.apple.dt.Xcode"'` | 0 | only `/Applications/Xcode.app` — **no second Xcode** |
| 14 | `ls /Applications/Xcode.app/Contents/Developer/Toolchains/` | 0 | only `XcodeDefault.xctoolchain` |
| 15 | `ls /Library/Developer/Toolchains/*` | 1 | no such directory |
| 16 | `ls /Library/Developer/CommandLineTools/usr/bin/metal` | 127 (direct run) | **absent** — CLT ships no `metal` at all |
| 17 | `find /Applications/Xcode.app /Library/Developer -name 'metal' -type f` | 0 | exactly one hit: `XcodeDefault.xctoolchain/usr/bin/metal` |
| 18 | `xcrun -f metal` | 0 | resolves to that same path |
| 19 | `ls /Library/Developer/CommandLineTools/SDKs/` | 0 | `MacOSX.sdk -> MacOSX27.0.sdk`, `MacOSX26.5.sdk`, `MacOSX27.0.sdk` |

Two corrections to the prior note:

- `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` **is locatable** — it exists and is
  a symlink to `MacOSX27.0.sdk`. The earlier "NOT LOCATABLE" observation no longer holds.
- CLT is nonetheless useless for Metal: `xcrun --sdk <CLT SDK> -f metal` still resolves to
  Xcode's shim, and CLT itself contains no `metal` binary to fall back on.

## 4. Root cause 1 — no mapping entry for the installed Xcode build

`~/Library/Developer/Xcode/XcodeToMetalToolchainIndexMapping.plist` maps `xcodeBuildUpdate`
→ `assetBuildUpdate`. Read in full (`plutil -p`):

- 43 entries.
- `17B5*` entries: `17B5025f`, `17B5035f`, **`17B5045g`** — then the series jumps to `17C48`.
- **No entry has `xcodeBuildUpdate = 17B5050g`**, which is the installed Xcode.

That is the whole explanation for `#4`: the requested build has no catalog target.

### Proof that pinning the build fixes the fetch

| # | Command | Exit | Observed |
|---|---|---|---|
| 20 | `xcodebuild -downloadComponent MetalToolchain -buildVersion 17B5045g` | **70** | `Download is not allowed as mobileassetd was starting up. (Asset download for com.apple.MobileAsset.MetalToolchain c3195e2bd42c415e8f5e500cbad3acfcc0205e7b)` |
| 21 | same, retry | 0 → killed by a 90 s harness timeout mid-transfer | progressed to `Downloading… (373.7 MB of 704.6 MB)` |
| 22 | same, retry | **0** | `Downloaded asset to: /System/Library/AssetsV2/com_apple_MobileAsset_MetalToolchain/c3195e2b….asset/AssetData/Restore/022-20562-020.dmg` / `Done downloading: Metal Toolchain 17B5045g.` |
| 23 | same, retry | **0** | idempotent: asset already present, same message |

Two distinct errors, two distinct causes: `#20` is transient (daemon startup), `#4` is
structural (no mapping). Only `#4` was previously recorded, and it was recorded as
unfixable.

`-downloadAllPlatforms` and `-downloadPlatform` were also executed:

| # | Command | Exit | Observed |
|---|---|---|---|
| 24 | `xcodebuild -downloadPlatform macos` | **70** | `Could not find platform: macos` — `-downloadPlatform` accepts only `iOS\|watchOS\|tvOS\|visionOS` |
| 25 | `xcodebuild -downloadAllPlatforms` (bounded to 25 s) | 124 (harness timeout) | printed only `Finding content…`; **no MetalToolchain mention**. Per `xcodebuild -help` it "downloads a matching simulator runtime for every platform in this Xcode" — it targets simulator runtimes, not the Metal component |
| 26 | `xcodebuild -help \| grep download` | 0 | `-downloadComponent <componenttype>` — *"Supported component: MetalToolchain."* |

After `#25` no partial download was left behind (`~/Library/Developer/DVTDownloads/*`
unchanged at 0 B / 12 K, no orphaned `xcodebuild` process, free space unchanged).

## 5. Root cause 2 — the asset is on disk but never linked into the toolchain

After the successful download the cryptex **was** mounted:

```
/dev/disk7s1 on /private/var/run/com.apple.security.cryptexd/mnt/\
com.apple.MobileAsset.MetalToolchain-v17.2.5045.7.1eItvk (apfs, sealed, local, read-only, …)
```

and it contains a **working** toolchain:

| # | Command | Exit | Observed |
|---|---|---|---|
| 27 | `<cryptex>/Metal.xctoolchain/usr/bin/metal --version` | 0 | `Apple metal version 32023.830 (metalfe-32023.830.2)`, `InstalledDir: …/usr/metal/current/bin` |
| 28 | `xcrun -sdk macosx metal --version` | **1** | *still* `missing Metal Toolchain` |

So a working compiler existed on disk and `xcrun` could not find it. That is root cause 2.

### Why: the shim's resolution rule

`XcodeDefault.xctoolchain/usr/bin/metal` is a 107 KB arm64 shim linked only against
`libc++.1.dylib` and `libSystem.B.dylib` — no Foundation, so it **cannot read a plist**.
Its entire `__cstring` section is:

```
unknown path to tool · XcodeDefault.xctoolchain · OSX[0-9]+\.[0-9]+\.xctoolchain
metal · current · macos · ios · bin · / · .. · SDKROOT · .sdk
```

i.e. it derives a developer root from `SDKROOT`, then probes
`<toolchain>/usr/metal/current/bin/<basename argv[0]>`. `SDKROOT` as passed by xcrun was
observed with:

```bash
xcrun -sdk macosx sh -c 'printf "%s\n" "$SDKROOT"'
# /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.0.sdk
```

That path leads to `/Applications/Xcode.app/Contents/Developer`, and
`Toolchains/XcodeDefault.xctoolchain/usr/metal` did not exist.

### Establishing the graft point by experiment, not by guess

The failure was reproduced in a throwaway tree and three candidates tested in order
(`$HOME/.jcode/scratch/metalfix1/`, nothing under `/Applications` touched):

| Variant | Graft created | `metal --version` |
|---|---|---|
| V0 | none | fails — `missing Metal Toolchain` |
| V1 | `Toolchains/Metal.xctoolchain` → cryptex | fails (unchanged) |
| V2 | `Toolchains/OSX26.0.xctoolchain` → cryptex | fails (unchanged) |
| **V3** | **`XcodeDefault.xctoolchain/usr/metal` → cryptex `usr/metal`** | **PASS — `Apple metal version 32023.830`** |

Only V3 resolves. V1/V2 are recorded because they are the layouts one would otherwise
assume from the `Metal.xctoolchain` directory name in the cryptex, and both are wrong for
this shim.

### The `metallib` shim

The cryptex's own `usr/bin/` holds ~54 shims (`metal`, `metallib`, `metal-opt`, `air-*`, …)
that delegate to `usr/metal/current/bin/`; the real 196 MB `metal` lives only under
`usr/metal/current/bin/`. Xcode ships just two names: `metal` and `metal-package-builder`.
`xcrun -sdk macosx metallib` therefore failed with
`unable to find utility "metallib"`.

The shim dispatches on `argv[0]`. Proven directly by copying it under another name:

| # | Command | Exit | Observed |
|---|---|---|---|
| 29 | `cp …/usr/bin/metal $SCRATCH/metallib_probe && $SCRATCH/metallib_probe --version` | 0 | `error: cannot execute tool 'metallib_probe' due to missing Metal Toolchain…` — the name in the message is `argv[0]`, confirming name dispatch |
| 30 | `<cryptex>/Metal.xctoolchain/usr/bin/metallib --version` | 0 | `AIR-LLD 32023.830 (metalfe-32023.830.2) (compatible with legacy metallib linker)` |

Hence `ln -sfn metal usr/bin/metallib` is a supported use of the mechanism Xcode already
relies on, rather than a copy of a foreign binary.

## 6. Result

| # | Command | Exit | Observed |
|---|---|---|---|
| 31 | `xcrun -sdk macosx metal --version` | **0** | `Apple metal version 32023.830 (metalfe-32023.830.2)`, `InstalledDir: /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/metal/current/bin` |
| 32 | `xcrun -sdk macosx metallib --version` | **0** | `AIR-LLD 32023.830` |
| 33 | `bash packaging/macos-app.sh --probe` | 0 | `metal compiler: usable` → **`ok`** |
| 34 | `bash packaging/macos-app.sh` | **0** | `ok built zig-out/Ghostty.app (CFBundleShortVersionString=0.1, id=com.mitchellh.ghostty)`; `codesign --verify` passed; zip written |
| 35 | `shasum -a 256 -c dist-release/macos/Khostty-0.1.0-macos.zip.sha256` | 0 | `Khostty-0.1.0-macos.zip: OK` |
| 36 | `codesign --verify --deep --strict --verbose=2 zig-out/Ghostty.app` | 0 | `valid on disk` / `satisfies its Designated Requirement` |
| 37 | `file zig-out/Ghostty.app/Contents/MacOS/ghostty` | 0 | `Mach-O universal binary with 2 architectures: [x86_64] [arm64]` |
| 38 | `./zig-out/Ghostty.app/Contents/MacOS/ghostty --version` | **0** | `Ghostty 1.3.2-main-+41b24baad`, `channel: tip`, `build mode: .ReleaseSafe` |

The metallib step that the blocker turned on left its own artifact:

| # | Command | Exit | Observed |
|---|---|---|---|
| 39 | `find ~/.jcode/scratch/zc -name '*.metallib' -newermt '-3 hours'` | 0 | `…/b235b466e413153b78f870c40baee097/Ghostty.metallib` |
| 40 | `file Ghostty.metallib` | 0 | `MetalLib executable (MacOS), version 1.2.7`, 52,381 bytes |
| 41 | `shasum -a 256 Ghostty.metallib` | 0 | `b005b34ad3ae1ebfad69756fd2f35f31d4074661c1ddd492745040c0850e1aa9` |

Full build wall time: 1002.7 s (started 04:56:55, finished 05:13:37), single run, no reruns.

## 7. Rejected alternatives

| Alternative | Why rejected |
|---|---|
| `xcodebuild -importComponent MetalToolchain -importPath <dmg>` | Would import the same asset that is already grafted; does not create the `usr/metal` path, and the DMG is a `cryptex1` restore image rather than an importable bundle. |
| Adding a `17B5050g` entry to `XcodeToMetalToolchainIndexMapping.plist` | Cannot work: the consumer that fails is the `xcrun` shim, which links no plist-reading framework. The plist only steers the Xcode **IDE**'s own grafting step, which is not in `zig build`'s path. Untested and therefore not claimed. |
| Adding `Toolchains/Metal.xctoolchain` or `Toolchains/OSX26.0.xctoolchain` | Both tested in the throwaway tree and both failed (V1, V2 above). |
| `xcodebuild -downloadAllPlatforms` | Executed (#25) and shown to fetch simulator runtimes, not the Metal component; `-downloadComponent` documents `MetalToolchain` as its only supported component (#26). |
| `-downloadPlatform macos` | Executed (#24); `macos` is not an accepted platform name. |
| Building without Metal (`-Drenderer=metal` avoided) | Not available: `src/build/MetallibStep.zig` returns `null` only for non-macOS targets, so the metallib step is unconditional for the macOS `.app`. |
| Mounting the DMG manually | Unnecessary — `cryptexd` already mounted it (and the mount is read-only/sealed by design). Would also have needed privileged operations, which this task forbade. |

## 8. Residual uncertainty

- **Durability is unproven.** The symlinks point at a per-boot cryptex mount name. Whether
  the mount name is stable across reboots was **not** tested — a reboot was out of scope.
  Treat the fix as session-scoped and re-link after reboot (see `00_SESSION_OVERVIEW.md`).
- **`17B5045g` vs `17B5050g` is a deliberate mismatch.** The toolchain is one asset-build
  older than the Xcode that consumes it. It compiles this project's shaders cleanly, but it
  is not the pairing Apple verifies, and no other pairing is reachable from this host.
- **No GUI launch, so "installs and runs" is only half-evidenced.** `--version` proves the
  binary loads, dyld resolves and the embedded metallib is intact; it does not prove the
  AppKit shell renders. The WBS 9.15 acceptance bullet asks for an install-and-run outside
  the source tree, which remains unexecuted.

## See also

- [`00_SESSION_OVERVIEW.md`](00_SESSION_OVERVIEW.md) — outcome, host changes, durability caveat
- [`../../INSTALL.md`](../../INSTALL.md) — per-artifact status
- [`../../dossiers/KHOSTTY.md`](../../dossiers/KHOSTTY.md) — product dossier
- [`../20260916-fork-assessment/02_DEEP_WBS.md`](../20260916-fork-assessment/02_DEEP_WBS.md) — WBS source of truth
