# Windows native runtime receipt

Status: S2/S1/S3 local gates passed; S5/S6 pending. This is an experimental
Windows runtime, not a completed interactive terminal. S5/S6 remain unimplemented.

## Scope and isolation

Worktree: `C:\Users\koosh\Khostty\.worktrees\lane-c`.
Branch: `stubs/khostty-lane-c-20261016`, based on `origin/main` at `52a69ca86`.
All work ran locally on the Windows desk, with `-j2` and worktree-local
`.zig-cache` / `.zig-global-cache`. No screenshots or recordings were taken.
No other checkout was edited. No issue was created or closed, and nothing merged.

- S2: checked SDK-backed class registration, HWND creation, GetMessage's three
  outcomes, DPI, positioning, posting, and read-only Unicode clipboard copying.
- S1: class registration, owned HWND, ShowWindow, GetMessage/DispatchMessage loop,
  WM_CLOSE/WM_DESTROY cleanup, UI-thread DPI awareness restoration, and wakeup.
- S3: software Direct2D target and DirectWrite system fallback, persistent Ghostty
  VT parser, UTF-16 screen snapshots, paint/invalidation/resize, and HWND hooks.
  The software backend avoids the host's unproven OpenGL path.
- Reuse the two relevant build fixes from `lanes/d-ci-installer-20261016`: exclude
  Unix headers from Windows C translation; represent DMA-BUF descriptors as ints.
- Add user32/d2d1/dwrite/uuid linkage and a small C COM adapter. Native tests import
  the SDK only for Windows; portable message-decoder tests remain available.

S3 deliberately renders plain text. SGR attributes, precise per-font cell metrics,
selection/cursor rendering, and the core Surface bridge are still missing. Its
own terminal grid is not a complete replacement for the core Surface lifecycle.
Input dispatch, bracketed paste, ConPTY, interactive shell round-trip, and herdr
verification are not implemented or claimed. No default GUI launch was attempted.
The operator's earlier `error.Unimplemented` GUI report is historical evidence,
not a newly verified error or an attribution to a current call site.

The prescribed `C:\Users\koosh\Downloads\docs-3\products\khostty\DOSSIER.md`
was absent; its QA gates could not be read or claimed.

## Timeout method

All commands below run from the worktree, with
`C:\Users\koosh\zig\zig-x86_64-windows-0.16.0` on PATH.
`tools/lane-c/bounded.ps1 -Seconds <cap> -Name <receipt> -Command '<command>'`
runs a hidden child process and records stdout/stderr/child exit under
`.zig-cache/lane-c-receipts/`. A timeout returns 124 and targets only that process
tree. Build/compile caps are 900 seconds unless noted; standalone native test and
CLI probes have 60-second caps. No timeout or cancellation is treated as a pass.

This Zig rejects `--test-timeout 60s` (exit 1), so an outer timeout is used.
An initial unquoted `-femit-bin` invocation failed before compilation; its first
wrapper incorrectly returned 0 with a blank child exit. That attempt is not a
pass. The wrapper now explicitly records the child's exit code.

## Pre-S3 verification (before renderer integration)

```powershell
zig test src/apprt/windows/win32api.zig -lc -luser32 -lkernel32 -j2 --cache-dir .zig-cache --global-cache-dir .zig-global-cache --test-no-exec "-femit-bin=.zig-cache/lane-c-native.exe"
# Exit 0; 900-second cap.
& ./.zig-cache/lane-c-native.exe
# Exit 0; 2/2 tests passed, no skips; 60-second cap.

zig test src/apprt/windows/win32api.zig -target x86_64-windows-gnu -lc -luser32 -lkernel32 -j2 --cache-dir .zig-cache --global-cache-dir .zig-global-cache --test-no-exec -fno-emit-bin
# Exit 0; semantic compilation only; 120-second cap.

zig test src/apprt/windows/win32api.zig -target x86_64-windows-gnu -luser32 -lkernel32 -isystem C:/Users/koosh/zig/zig-x86_64-windows-0.16.0/lib/libc/include/any-windows-any -isystem C:/Users/koosh/zig/zig-x86_64-windows-0.16.0/lib/include -j2 --cache-dir .zig-cache --global-cache-dir .zig-global-cache --test-no-exec "-femit-bin=.zig-cache/lane-c-native-no-crt.exe"
# Exit 0; explicit SDK headers, no CRT linkage; 120-second cap.
& ./.zig-cache/lane-c-native-no-crt.exe
# Exit 0; 2/2 tests passed, no skips; 60-second cap.

zig build test-windows-apprt -Dtarget=x86_64-windows-gnu -Dapp-runtime=windows -Dtest-filter=native -Demit-docs=false -j2 --cache-dir .zig-cache --global-cache-dir .zig-global-cache
# Exit 0 before the 900-second cap; default output contains no test count.

zig build -Dtarget=x86_64-windows-gnu -Dapp-runtime=windows -Demit-docs=false -Demit-macos-app=false -j2 --cache-dir .zig-cache --global-cache-dir .zig-global-cache
# First attempt exit 1 (dependency fetch); retry exit 0 within 900 seconds.
```

The two standalone tests exercised real invisible HWND creation, duplicate class
registration, DPI, positioning, close/message-loop cleanup, invalid-HWND controls,
and read-only clipboard acquisition/copy/release. These passes predate S3's hook
and renderer integration and must not be substituted for the final gates below.

The pre-S3 exe's `+version` probe passed, exit 0, with an explicit
`System.Diagnostics.Process` wait, redirected stdout/stderr, and a 60-second cap:
`.windows`, `.freetype_windows`, OpenGL build config, IOCP. This is CLI evidence,
not GUI rendering evidence. An earlier direct PowerShell invocation left
LASTEXITCODE unset and was recorded as 1 by the wrapper; it was not reliable
application-status evidence.

## Failed/canceled attempts

First build error (exit 1):

```text
vaxis/build.zig.zon:8:20: error: unable to discover remote git server capabilities: HttpConnectionClosing
.url = "git+https://github.com/zigimg/zigimg#d695acd97c02e57bb151e8f659d1280f5cd6ca70",
```

Recovery downloaded that exact revision's codeload archive into `.zig-cache`.
`zig fetch --global-cache-dir .zig-global-cache .zig-cache/zigimg.tar.gz` exited 0
and returned the expected hash
`zigimg-0.1.0-8_eo2oyaFwBZwJpmqPkCfVXWBrHcqbYwmrp1I6bTD3lI`.
No pinned dependency or manifest changed.

A redundant standalone CRT compile was canceled, not passed:

```powershell
zig test src/apprt/windows/win32api.zig -target x86_64-windows-gnu -lc -luser32 -lkernel32 -j2 --cache-dir .zig-cache --global-cache-dir .zig-global-cache --test-no-exec "-femit-bin=.zig-cache/lane-c-native-final.exe"
# CANCELED; child/wrapper exit 1.
```

`taskkill /PID 312312 /T /F` returned 255: the parent terminated, one compiler
child initially reported termination unsupported, and a subsequent process check
confirmed that child had exited. No other process tree was targeted.

Initial S3 compile (900-second cap), exit 1, three pointer-alignment errors:

```powershell
zig build test-windows-apprt -Dtarget=x86_64-windows-gnu -Dapp-runtime=windows -Dtest-filter=native -Demit-docs=false -j2 --cache-dir .zig-cache --global-cache-dir .zig-global-cache --summary all
```

Exact diagnostic: `error: @ptrCast increases pointer alignment` at the hook,
BeginPaint, and InvalidateRect calls. HWND values are opaque handle IDs, not
pointers into the SDK's aligned placeholder struct; conversion now preserves the
handle value instead of asserting an invalid memory-alignment requirement.

## Final S3 gates

The final results are recorded below. The native renderer test feeds split ANSI/UTF-8
through Ghostty's parser, submits software Direct2D frames, resizes, reads output
from `cmd.exe /d /c "echo S3-shell-output"`, and probes DirectWrite glyph IDs for
`A界😀`, with an absent-character negative control. It captures no pixels.

```powershell
zig build test-windows-apprt -Dtarget=x86_64-windows-gnu -Dapp-runtime=windows -Dtest-filter=native -Demit-docs=false -j2 --cache-dir .zig-cache --global-cache-dir .zig-global-cache --summary failures
# First retry exit 1: undefined IID_IDWriteFactory, IID_IDWritePixelSnapping,
# IID_IDWriteTextRenderer. Fixed with SDK initguid.h. Final retry exit 0.

zig build -Dtarget=x86_64-windows-gnu -Dapp-runtime=windows -Demit-docs=false -Demit-macos-app=false -j2 --cache-dir .zig-cache --global-cache-dir .zig-global-cache --summary failures
# Exit 0, 900-second cap. Includes the software renderer integration.

zig build-exe .zig-cache/renderer-probe.c -target x86_64-windows-gnu -lc -luser32 -ld2d1 -ldwrite -luuid -j2 --cache-dir .zig-cache --global-cache-dir .zig-global-cache "-femit-bin=.zig-cache/renderer-probe.exe"
# Exit 0, 120-second cap; independent C adapter probe.
& ./.zig-cache/renderer-probe.exe
# Exit 0, 60-second cap.
```

The independent probe used a private invisible STATIC HWND and the same tracked C
adapter. Its process-scoped output was:

```text
positive HRESULT=0x00000000 missing=0 runs=3
negative HRESULT=0x00000000 missing=1 runs=1
draw HRESULT=0x00000000
```

The integrated native test also includes this glyph-ID check and negative control,
as well as the real `cmd.exe` pipe-output/VT-parser/draw test. Neither command
captures pixels or proves an interactive ConPTY session. No full test suite, GUI
launch, hosted CI, deployment, or merge is claimed.
