# Test strategy: the Windows apprt builds and paints; the grid is not drawn yet

Session: 2026-11-20. Owner lane: khostty. Measured, not planned.

## What is proven, and by what command

| Claim | Command | Observed |
|---|---|---|
| The Windows runtime compiles and links | `zig build -Dtarget=x86_64-windows-gnu -Dapp-runtime=windows` on the desk node in `/root/builds/khostty` | `rc=0` |
| A Windows binary is produced | `ls -l zig-out/bin` | `ghostty.exe` 43431936 bytes, `sha256 e5481f70a7ca41563708186df6c1deaf3c4a84e7022d7ccc44c0feec838b334c` |
| The gdi32 symbols the paint path CALLS are linkable | the same build | it produced an exe, so `CreateSolidBrush`, `DeleteObject`, `GetClientRect`/`FillRect`, `BeginPaint`/`EndPaint` resolved. The text set (`CreateFontW`, `TextOutW`, `GetTextMetricsW`, `SelectObject`, `SetTextColor`, `SetBkMode`, `CreateCompatibleDC`, `DeleteDC`) is DECLARED but never called, so it is not yet in the import table and is unproven |
| The source the build used was the source on disk at build time | `sha256sum src/apprt/windows/{App,win32}.zig` local versus the build tree | equal on both: `dd29684f…` (App.zig), `6e0e8f9d…` (win32.zig) - i.e. HEAD's `win32.zig` |

The build was run on the desk (Windows 11 host, WSL2 Fedora, `zig 0.16.0` at
`/usr/sbin/zig`), not on the Mac. Transfer was `git archive HEAD | gzip | ssh`,
i.e. tracked files only, 97.7 MB, then the two hashes above were compared.

After that build, the working tree's `win32.zig` was found modified
(`d1ea7dd4…`, +104 lines, stable, nothing calls it). That uncommitted state was
NOT part of the proven build, and it is dead code until a call site exists.

## What is NOT proven

- **No pixel has been observed.** A successful link is not a painted window. The
  paint path (`WM_ERASEBKGND` + `WM_PAINT` in `src/apprt/windows/App.zig`) has
  never run on a Windows desktop from this lane.
- **No text or grid is drawn.** `WM_PAINT` fills the client rect and stops.
  `win32.zig` carries the GDI text declarations (`CreateFontW`, `SelectObject`,
  `GetTextMetricsW`, `SetTextColor`, `SetBkMode`, `TextOutW`,
  `CreateCompatibleDC`, `DeleteDC`, `MultiByteToWideChar`) but nothing calls them.
- **DPI awareness is unset.** Without `SetProcessDpiAwarenessContext` the client
  area is virtualised on a scaled display, so a 16px requested cell height is not
  16 physical pixels. Unmeasured at any scale other than 100%.
- **The terminal is not reachable from the window procedure yet.**
  `GWLP_USERDATA` holds `*Surface`; the paint path therefore cannot see cells,
  cursor or styles until that bridge exists.

## Next test to write, in order

1. A `textFont()` probe that creates the face, selects it into a compatible DC,
   and records `tmHeight` into `cell_height` - asserted by a unit test that skips
   when `CreateCompatibleDC` returns null (non-Windows hosts).
2. A headless check that the built exe's import table names `gdi32.dll`, which
   turns "the declarations link" from an inference into a measurement.
3. Only then, a real desktop launch, verified by process and window
   enumeration - never by a screenshot.

## Reproduce

```
git archive --format=tar HEAD | gzip -1 | ssh desk \
  'wsl -e bash -lc "tar xzf - -C /root/builds/khostty"'
ssh desk 'wsl -e bash -c "cd /root/builds/khostty; \
  zig build -Dtarget=x86_64-windows-gnu -Dapp-runtime=windows; echo rc=$?"'
```
