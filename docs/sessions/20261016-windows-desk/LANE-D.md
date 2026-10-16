# Windows desk build receipt — 2026-10-16

Status: **BLOCKED — `error.TestsTimedOut`**. No PR was opened because the
operator requires passing desk builds and tests before PR creation.

All Git/GitHub operations target `KooshaPari/Khostty`. Branch:
`lanes/d-ci-installer-20261016`, based on main `79538308694f032d5c068de68c5679b8931ff908`.
Compute placement: local `KOOSHAPARI-DESK`, Zig `-j2`.

## Verified build and packaging

Zig **0.16.0** was downloaded from the official Windows x86_64 archive into
`C:\Users\koosh\zig` and installed without admin privileges. SHA-256:
`68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e`.

```powershell
zig build -j2 --cache-dir dist-release/cache/zc/o --global-cache-dir dist-release/cache/zc/g -Dtarget=x86_64-windows-gnu -Demit-lib-vt -Doptimize=ReleaseFast --summary all
zig build -j2 --cache-dir dist-release/cache/zc/o --global-cache-dir dist-release/cache/zc/g -Dtarget=x86_64-windows-gnu -Dapp-runtime=windows -Demit-macos-app=false -Doptimize=ReleaseFast --summary all
bash packaging/windows/installer.sh --no-build
```

The library build passed **48/48** steps. The final-source executable build
passed **125/125** steps, exit 0. The installer compiled successfully after
excluding ISCC's `/Q` flag from Git Bash path conversion. The executable was
rebuilt and the installer repackaged after the final Zig source change.

| Artifact | SHA-256 |
|---|---|
| `zig-out/bin/ghostty.exe` | `f14ce1ce65d31361ed3118642fa4fe2c425d50941d37fb5807b8a8d64c7e65fa` |
| `zig-out/bin/ghostty-vt.dll` | `612bbbe8ec3855ab383f93963adfbd62bebd20f8fb4ee05a285b275ab3be5bb4` |
| `dist-release/stage/windows/Khostty-0.1.0-win64/output/Khostty-0.1.0-windows-x86_64-setup.exe` | `7e15e0e1df1c40e6ee7768d076aa2bdca523ecfbe50c96e539b1b14723b8b3a9` |

Final installer size: **16,674,281 bytes**. Exact output tail:

```text
==> done
artifact /c/Users/koosh/Khostty/dist-release/stage/windows/Khostty-0.1.0-win64/output/Khostty-0.1.0-windows-x86_64-setup.exe
size 15.9 MiB
sha256 7e15e0e1df1c40e6ee7768d076aa2bdca523ecfbe50c96e539b1b14723b8b3a9
install test not run
```

`+version` exited **0**, reporting Windows runtime, Zig 0.16.0,
ReleaseFast, freetype_windows, OpenGL and IOCP. Its smoke-tested executable
hash is identical to the final-source executable hash above. The embedded
version names base `795383086`; builds used the branch's working-tree changes.
Installer installation/uninstallation remains **UNEXECUTED**.

## Test gate: blocked

```powershell
zig build -j2 --cache-dir dist-release/cache/zc/o --global-cache-dir dist-release/cache/zc/g test-windows-apprt -Dtarget=x86_64-windows-gnu --test-timeout 60s --summary all
```

The initial compile exposed the DMA-BUF Unix descriptor field selecting
Windows HANDLE via `std.posix.fd_t`; it now uses the Unix integer `c_int`
required by EGL export. The initial executable build also required omitting
Unix-only `pwd.h`/`unistd.h` from the Windows C translation header set.

Compilation then completed and the actual test program executed, but never
returned a protocol result. The native 60-second timeout did not terminate it.
The bounded attempt started **12:45:41 Pacific**, was canceled at **12:49:35**,
and consumed **221.7 CPU seconds**. Exact active test name and completed-test
count are **UNKNOWN**. Both owned test trees were stopped; no tests were
skipped or reported passed. This is a timeout/cancellation, not an assertion
failure diagnosis.

`packaging/windows/build.ps1` independently limits the complete test-build
process tree to 15 minutes and throws `error.TestsTimedOut`. Its actual
helper was verified with a 1-second negative-control limit: it killed its
owned process tree, drained output and returned the typed timeout in 1.27s.
This guard check is **not** a test-suite pass.

## GUI and screenshot: blocked

The real default launch exited **1**, no window handle, with:

```text
info: runtime=.windows
info: font_backend=.freetype_windows
info: renderer=renderer.generic.Renderer(renderer.OpenGL)
info: libxev default backend=iocp
error: Unimplemented
```

`error.ScreenshotUnavailable`: no safe authentic process-window capture.
A coordinate capture contained unrelated desktop pixels and was quarantined
locally, never uploaded or committed. A bounded process-exclusive capture
found no capturable window. The requested screenshot path is absent; no
image attachment or renderer proof is claimed.

## CI and receipts

Workflow: `.github/workflows/windows-desk.yml`. Required labels:
`[self-hosted, Windows, X64]`, with explicit `KOOSHAPARI-DESK` host guard,
same-fork PR restriction and no hosted fallback. The fork API returned
**zero registered runners**; no desk-specific label was discovered and
Actions execution is **UNEXECUTED**. No hosted dispatch/rerun was performed.

Issue receipt: https://github.com/KooshaPari/Khostty/issues/13#issuecomment-6223322548

Full local result: `C:\Users\koosh\workers\khostty-d-RESULT.md`.
Build logs: `khostty-d-build-attempt2.log`, `khostty-d-exe-final.log`,
`khostty-d-installer-final.log`; timeout receipt:
`khostty-d-tests-timeout.json`, under the same workers directory.

Next: diagnose the Windows test-runner timeout, register an eligible desk
runner for this fork, and complete the native lifecycle/renderer lane before
claiming GUI acceptance. Open the requested non-draft PR only after the
desk test gate passes. Concurrent lane A worktree/processes were preserved.
