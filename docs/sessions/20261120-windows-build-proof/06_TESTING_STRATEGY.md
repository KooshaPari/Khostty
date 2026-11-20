# Test strategy: the Windows apprt builds and paints; the grid is not drawn yet

Session: 2026-11-20. Owner lane: khostty. Measured, not planned.

## What is proven, and by what command

| Claim | Command | Observed |
|---|---|---|
| The Windows runtime compiles and links | `zig build -Dtarget=x86_64-windows-gnu -Dapp-runtime=windows` on the desk node in `/root/builds/khostty` | `rc=0` (build 1: HEAD) |
| A Windows binary is produced | `ls -l zig-out/bin; sha256sum zig-out/bin/ghostty.exe` | build 1: `ghostty.exe` 43431936 bytes, `sha256 e5481f70a7ca41563708186df6c1deaf3c4a84e7022d7ccc44c0feec838b334c` |
| The GDI text path compiles and links | the same command, after mirroring the working-tree `App.zig` (`5f206c3f…`) and `win32.zig` (`d1ea7dd4…`), hashes compared first | build 2: `ghostty.exe` 43726336 bytes (+294400), `sha256 34d91a1e384ab50660aeac00c26f0ad590b2ade507b2a3fa43bbbd7a4c64c11f`, mtime inside the 06:27:03Z-06:29:35Z build window. `zig-out/bin` is written by the install step after compile+link, so a newer and larger exe means the text path resolved |
| The gdi32 symbols are linkable | the two builds above, then `llvm-objdump -p` on the exe from build 3 | build 1 resolved the symbols the paint path calls; builds 2 and 3 additionally had call sites for the text set. Measured, not inferred: the import table names `GDI32.dll` with `CreateSolidBrush`, `CreateCompatibleDC`, `CreateFontW`, `DeleteDC`, `DeleteObject`, `GetTextMetricsW`, `SelectObject`, `SetBkMode`, `SetTextColor`, `TextOutW` (10 symbols), and `USER32.dll` with `BeginPaint`, `EndPaint`, `FillRect`, `GetClientRect` |
| The committed tree builds with a recorded exit code | `zig build -Dtarget=x86_64-windows-gnu -Dapp-runtime=windows -p <prefix>` at HEAD `559f33d3b`, on the Mac | build 3: `rc=0`, `ghostty.exe` 43792384 bytes. This target cross-compiles from macOS, so the desk was never required for the compile - only for the earlier runs |
| The source the build used was the source on disk | `sha256sum src/apprt/windows/{App,win32}.zig` local versus the build tree | build 1: equal, `dd29684f…` and `6e0e8f9d…` (HEAD's `win32.zig`). Build 2: equal, `5f206c3f…` and `d1ea7dd4…` |

The build was run on the desk (Windows 11 host, WSL2 Fedora, `zig 0.16.0` at
`/usr/sbin/zig`), not on the Mac. Transfer was `git archive HEAD | gzip | ssh`,
i.e. tracked files only, 97.7 MB, then the two hashes above were compared.

Build 1 ran from a tracked-only `git archive HEAD`; its `win32.zig` was HEAD's. The
working tree then grew a text path, and build 2 was the same command against those
two files, mirrored and hash-verified rather than archived - so the uncommitted
edit was the build's input, not a bystander.

## What is NOT proven

- **The numeric build-2 exit code is UNKNOWN, and its log cannot be read.** The
  command that ran it wrote a literal `BUILD_RC=$?` into the log (the `$?`
  escaping was consumed by `cmd.exe` before `wsl` saw it), and three follow-up
  reads of `build-20261120T062703Z.log` failed: twice `Wsl/Service/WSAETIMEDOUT`,
  then a 600 s timeout with no output. The new-and-larger artifact is the
  evidence; the exit code is not.
- **No pixel has been observed.** A successful link is not a painted window. The
  paint path (`WM_ERASEBKGND` + `WM_PAINT` in `src/apprt/windows/App.zig`) has
  never run on a Windows desktop from this lane.
- **No text or grid is drawn.** `paint()` fills the client rect, then calls
  `viewportText()`, which dumps the focused surface's viewport under
  `renderer_state.mutex`; with no focused surface it returns null and the window
  draws `status_text` ("khostty: no terminal attached (Windows AppRT)") instead.
  So the GDI text path is exercised and observable, but terminal content is not.
- **DPI awareness is unset.** There is no `SetProcessDpiAwarenessContext` call and
  none in the import table, so the client area is virtualised on a scaled display
  and a 16px requested cell height is not 16 physical pixels. Unmeasured at any
  scale other than 100%.
- **The terminal is not reachable from the window procedure yet.** That is a
  structural limit, verified independently rather than inferred: `interface.zig:52`
  asserts `Surface.init()` returns `error.Unimplemented`, and
  `src/App.zig:435` is the only place `focused_surface` is set, so it is always
  null on Windows. `GWLP_USERDATA` now holds `*App` (`App.zig:166`) and reaches
  `paint`/`viewportText`; it cannot reach a terminal, because none is created.
- **`zig build test-windows-apprt` cannot run off Windows, and this predates the
  text path.** With 22 `callconv(.winapi)` sites in HEAD's `win32.zig`, the step
  fails on `aarch64-macos` with `calling convention 'aarch64_aapcs_win' not
  supported by compiler backend 'stage2_llvm'` (first at the `WakeupProc`
  declaration, then `DeleteObject`). Retargeting the test artifact to
  `x86_64-windows-gnu` clears that but loses the `macos` module that
  `src/font/discovery.zig` and the two `coretext.zig` files import, so a fix means
  a target-aware module graph, not a one-line target swap. The change was
  attempted and reverted rather than landed half-migrated.

## Next test to write, in order

1. A `textFont()` probe that creates the face, selects it into a compatible DC,
   and records `tmHeight` into `cell_height` - asserted by a unit test that skips
   when `CreateCompatibleDC` returns null (non-Windows hosts). `textFont()` now
   exists and does that measurement at runtime; the assertion is still missing and
   cannot run on this host for the calling-convention reason above.
2. A headless check that the built exe's import table names `gdi32.dll`. **DONE** -
   `llvm-objdump -p ghostty.exe` names `GDI32.dll` and, inside it, `TextOutW`
   alongside the other nine text symbols, plus the four `USER32.dll` paint symbols.
3. Only then, a real desktop launch, verified by process and window
   enumeration - never by a screenshot.

## Reproduce

```
git archive --format=tar HEAD | gzip -1 | ssh desk \
  'wsl -e bash -lc "tar xzf - -C /root/builds/khostty"'
ssh desk 'wsl -e bash -c "cd /root/builds/khostty; \
  zig build -Dtarget=x86_64-windows-gnu -Dapp-runtime=windows; echo rc=$?"'
```

No desk needed for the build or the import proof, and this path records its own
exit code:

```
zig build -Dtarget=x86_64-windows-gnu -Dapp-runtime=windows -p "$PREFIX"; echo rc=$?
llvm-objdump -p "$PREFIX/bin/ghostty.exe" | sed -n '/GDI32.dll/,/KERNEL32.dll/p'
```
