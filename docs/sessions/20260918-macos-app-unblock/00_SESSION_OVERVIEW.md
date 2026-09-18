# 2026-09-18 — Unblocking WBS 9.11 (macOS `.app` bundle)

## Outcome

**WBS 9.11 is no longer blocked.** The macOS `.app` bundle was built, signed, verified,
zipped and hash-checked on this host. The recorded blocker ("Metal Toolchain cannot be
obtained on this host") was **wrong**, and is corrected here with executed evidence.

| Item | Result |
|---|---|
| `packaging/macos-app.sh --probe` | `ok` — `metal compiler: usable` |
| `bash packaging/macos-app.sh` | **exit 0** |
| Bundle | `zig-out/Ghostty.app`, `CFBundleShortVersionString=0.1`, id `com.mitchellh.ghostty` |
| Binary | Mach-O universal (x86_64 + arm64) |
| Signature | Developer ID located by prefix; `codesign --verify --deep --strict` → *valid on disk*, *satisfies its Designated Requirement* |
| Artifact | `dist-release/macos/Khostty-0.1.0-macos.zip`, 35,953,098 bytes |
| `sha256` | `94abd2a7e7d63e790bfffd3a6e6f4e08ae80a67fbf3dbe8227e754c6104317cb` (`shasum -a 256 -c` → OK) |
| Liveness (no GUI) | `./zig-out/Ghostty.app/Contents/MacOS/ghostty --version` → `Ghostty 1.3.2-main-+41b24baad`, exit 0 |
| Source commit | `41b24baad24227e22fefc35ae74ee5999f3591d1` |

`dist-release/` is gitignored, so the probe and evidence files are not committed. This
session document is the committed record.

## Root cause (two independent defects, not one)

The previously recorded single blocker was:

> `xcodebuild -downloadComponent MetalToolchain` fails with
> `Failed fetching catalog for assetType (com.apple.MobileAsset.MetalToolchain)`.

That reproduces exactly — but only because the command omits the asset build. The real
picture:

1. **Xcode 26.0 build `17B5050g` has no Metal-toolchain mapping.** The local
   `~/Library/Developer/Xcode/XcodeToMetalToolchainIndexMapping.plist` has 43 entries; its
   `17B5*` entries stop at **`17B5045g`** and the next is `17C48`. There is no entry whose
   `xcodeBuildUpdate` is `17B5050g`. Requesting that build therefore has no catalog target,
   which is what produces the "Failed fetching catalog" message.
2. **Even once the asset is on disk, Xcode never links it into its toolchain.** `xcrun
   metal` is a thin shim (libc++/libSystem only — it cannot read plists) that resolves
   `SDKROOT` → developer root → `XcodeDefault.xctoolchain/usr/metal/current/bin/metal`.
   `Metal.xctoolchain` was mounted as a cryptex but nothing created that path, so the shim
   still reported the toolchain missing.

Defect 2 is why the failure survived a successful download, and it is the defect that
actually gated the build.

## What was changed on this host

All changes are additive, inside a **user-owned** `Xcode.app` (`kooshapari:staff`, mode
`drwxr-xr-x`). **No `sudo` was used. Nothing was deleted. No source file was modified.**

1. Downloaded the Metal toolchain asset by pinning its build:

   ```bash
   xcodebuild -downloadComponent MetalToolchain -buildVersion 17B5045g
   ```

   exit 0, `Done downloading: Metal Toolchain 17B5045g.` This placed a 716 MB asset
   (build `17B5045g`, digest `c3195e2bd42c415e8f5e500cbad3acfcc0205e7b`) under
   `/System/Library/AssetsV2/com_apple_MobileAsset_MetalToolchain/`, which `cryptexd`
   then mounted as the read-only volume `MetalToolchainCryptex`.

2. Created two symlinks inside `Xcode.app`:

   ```bash
   XB=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain
   CRYPT=/private/var/run/com.apple.security.cryptexd/mnt/\
   com.apple.MobileAsset.MetalToolchain-v17.2.5045.7.1eItvk/Metal.xctoolchain

   ln -sfn "$CRYPT/usr/metal"      "$XB/usr/metal"
   ln -sfn metal                   "$XB/usr/bin/metallib"
   ```

   - `usr/metal` is the path the `metal` shim probes. `usr/bin/metal` (Xcode's own shim)
     was **not** touched.
   - `usr/bin/metallib` → `metal` works because that shim dispatches on `argv[0]`; it is
     the same mechanism Xcode already uses for `metal`. Confirmed by invoking the shim
     under a different name, which reported `cannot execute tool 'metallib_probe'`.

The graft location was **not** guessed. It was established by reproducing the failure in a
throwaway tree under `$HOME/.jcode/scratch/metalfix1/` and then testing three candidates:
`Toolchains/Metal.xctoolchain`, `Toolchains/OSX26.0.xctoolchain`, and
`XcodeDefault.xctoolchain/usr/metal`. Only the third resolved; the first two left the error
unchanged. See `01_RESEARCH.md` for the full command log.

## Durability — read this before trusting the fix

The unblock is **host-local and not durable across reboots or Xcode updates**:

- The cryptex mount point contains a per-mount suffix (`...7.1eItvk`). Both symlinks point
  at it. After a reboot the volume is re-mounted under a **different** name, and the
  symlinks dangle. Re-run the two `ln -sfn` commands with the current mount path
  (`mount | grep MetalToolchain`).
- An Xcode update replaces `Xcode.app` and removes both symlinks.
- `17B5045g` is not the build Apple's mapping would have chosen for `17B5050g` — no such
  entry exists. It is simply the newest `17B5*` build with a catalog entry. It works, but
  it is a deliberate mismatch, not a supported pairing.

A durable fix is to install an Xcode whose build appears in
`XcodeToMetalToolchainIndexMapping.plist`, on which
`xcodebuild -downloadComponent MetalToolchain` succeeds without `-buildVersion` and Xcode
performs the graft itself.

## What was deliberately *not* done

- **No GUI launch.** The bundle was not started as an application: doing so would take
  focus on the operator's live desktop, and `packaging/macos-app.sh` itself declines to
  launch. Liveness is evidenced instead by running the bundled binary's `--version`, which
  exercises dyld, the embedded metallib and the build config without a window.
- **No source change.** `packaging/macos-app.sh` and `src/build/MetallibStep.zig` are
  untouched, so `--probe` remains the single source of truth for readiness.
- **No notarization.** `notarytool` credentials are absent; the `.app` is not notarized, so
  Gatekeeper will quarantine it on another machine.
- **No push, no publish, no tag.** The zip stays in the gitignored `dist-release/`.

## Known inaccuracies left in place

Two pre-existing reporting flaws were observed and **not** fixed, because both are inside
the packaging script and this task forbade source edits:

1. `dist-release/macos/EVIDENCE.txt` always writes
   `notarization_blocker: no Developer ID Application identity …`, which is untrue on this
   host (a Developer ID identity *is* present). The line is unconditional in the script.
2. On success the script still prints `ok ad-hoc signature verifies` while
   `EVIDENCE.txt` correctly records `signed: developer-id`. The success message is
   hardcoded.

## Follow-ups

- Propagate the corrected status to `docs/INSTALL.md` (row 3, §3.3, check table),
  `docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md` (G9, 9.11, check table) and
  `docs/dossiers/KHOSTTY.md` (§3.3, §7, §8, §10). The dossier and the headline rows are
  updated by this session; the remaining narrative in `docs/INSTALL.md` §3.3 was left to
  that file's concurrent author to avoid clobbering in-flight work.
- The G9 acceptance criterion *"macOS `.app` installs and runs (verified outside source
  tree)"* is **partly** met: the bundle builds, verifies and executes, but it has **not**
  been copied outside the source tree and launched in a GUI session, and it is not
  notarized. Treat it as **NOT YET CLOSED** on the install/launch half.

## See also

- [`01_RESEARCH.md`](01_RESEARCH.md) — full command log with exit codes
- [`../../INSTALL.md`](../../INSTALL.md) — per-artifact status
- [`../../dossiers/KHOSTTY.md`](../../dossiers/KHOSTTY.md) — product dossier
- [`../20260916-fork-assessment/02_DEEP_WBS.md`](../20260916-fork-assessment/02_DEEP_WBS.md) — WBS source of truth
