# Platform Support

**Observed:** 2026-09-17 · Honest matrix. A row is only marked **VERIFIED** when
this repository has an observed, dated result for it. Upstream support and
Khostty-verified support are different columns, because they are different claims.

---

## 1. Summary matrix

| Platform | VT library | Terminal app | Agent IPC | FFI | Renderer | Verified in this fork? |
|---|---|---|---|---|---|---|
| **macOS** (arm64/x86_64) | **VERIFIED** | Upstream AppKit; Metal toolchain caveat | 3 actions | C, Rust, WASM | Metal / OpenGL | **YES** — 2026-09-16/17 |
| **Linux** (x86_64/arm64) | Upstream supported | Upstream GTK4 | 3 actions | C, Rust, WASM | OpenGL | **NO** — not built here |
| **Windows** (x86_64) | Upstream builds; **no app runtime** | **SCAFFOLD only** | Named-pipe stub | C, Rust, Go | OpenGL (unproven) | **NO** — G3 IN PROGRESS |
| **WASM** (`wasm32-freestanding`) | **VERIFIED** | n/a (headless) | n/a | JS/TS | WebGL (n/a for VT-only) | **YES** — artifact verified |
| **iOS** | Library only (xcframework slice) | Not supported | n/a | C | Metal | Artifact present, app not attempted |
| **FreeBSD** | Upstream supported | Upstream GTK4 | 3 actions | C, Rust | OpenGL | **NO** |

Read this table as: *only the macOS and WASM rows have fresh evidence in this
fork.* Everything else is upstream capability that Khostty has not independently
exercised.

---

## 2. Platform selection at build time

Three comptime choices decide what a target gets. Each falls back to a
platform-appropriate default when the corresponding `-D` flag is omitted.

### Application runtime — `src/apprt/runtime.zig`

```zig
pub fn default(target: std.Target) Runtime {
    return switch (target.os.tag) {
        .linux, .freebsd => .gtk,
        else             => .none,   // lib-only; no executable
    };
}
```

| Target | Default runtime | Consequence |
|---|---|---|
| Linux, FreeBSD | `gtk` | Full app; requires GTK4 + wayland/x11 |
| macOS | `none` | Library only; Xcode builds the `.app` |
| **Windows** | **`none`** | **Library only — this is the gap G3 fills** |
| wasm32 | `browser` (via `.wasm_module`) | Headless module |

### Renderer — `src/renderer/backend.zig`

```zig
if (target.cpu.arch == .wasm32) return switch (wasm_target) { .browser => .webgl };
if (target.os.tag.isDarwin())  return .metal;
return .opengl;
```

Override with `-Drenderer=opengl|metal|webgl`.

### Fonts — `src/font/backend.zig`

| Target | Default backend |
|---|---|
| macOS | `coretext` |
| Linux, BSD | `fontconfig_freetype` |
| Windows | `freetype_windows` (Windows font-directory scanner) |
| wasm32 | `web_canvas` (not used by the VT-only library) |

Override with `-Dfont-backend=…`. Note the Windows comment in-tree: fontconfig is
avoided on Windows because its libxml2 dependency may not unpack correctly;
a future DirectWrite backend may replace `freetype_windows`.

> Windows having a default *font* backend does not mean Windows has an
> application runtime. Font discovery and windowing are separate layers.

---

## 3. macOS

**Status: VERIFIED for the library; app blocked by toolchain.**

> **Current build blocker (observed 2026-09-17).** `zig build -Demit-lib-vt` fails
> for every platform: commit `e1277bea2` renamed `src/apprt/ipc.zig` to
> `src/apprt/ipc/mod.zig` without updating its relative imports. The artifacts
> below are real, but they cannot currently be regenerated from source. Diagnosis
> and the two-line fix: [BUILD.md](BUILD.md#unable-to-load-mainzig-filenotfound--unable-to-load-quirkszig).

### Verified artifacts (2026-09-16, still present)

| Artifact | Size | Timestamp |
|---|---|---|
| `zig-out/lib/libghostty-vt.a` | 1,323,002 B | 2026-09-16 16:46 |
| `zig-out/lib/libghostty-vt.0.1.0.dylib` | 2,215,792 B | 2026-09-16 16:46 |
| `zig-out/lib/libghostty-vt.dylib` | symlink → `.0.dylib` → `.0.1.0.dylib` | 2026-09-16 04:31 |
| `zig-out/lib/ghostty-vt.xcframework/` | 3 slices | 2026-09-16 04:31 |
| `zig-out/bin/ghostty-vt.wasm` | 813,670 B | 2026-09-16 04:35 |

xcframework slices present: `macos-arm64_x86_64`, `ios-arm64`,
`ios-arm64-simulator`.

### Conformance (2026-09-17)

84/84 cases pass against the built `libghostty-vt.dylib`. Re-run with
`conformance/build.sh`. See [TESTING.md](TESTING.md).

### Known blocker: Metal toolchain

The full application build reports 285/302 steps succeeding. Metal shader
compilation fails on the installed Xcode because the **MetalToolchain component
is missing** (Xcode 26 beta). `-Demit-macos-app=false` does not avoid it, because
Metal is used by the core library's macOS renderer rather than only by the app
bundle.

Workarounds in use:

| Workaround | Effect |
|---|---|
| `-Drenderer=opengl` | Build with the OpenGL renderer instead of Metal |
| `-Demit-lib-vt` | Build only the VT library; no renderer at all |
| `-Demit-macos-app=false` | Skip the Xcode-driven `.app` (does not by itself fix Metal) |

CI reflects this: `.github/workflows/ci.yml` (the fork's own workflow) runs
`zig fmt --check src/ build.zig` on Ubuntu and
`zig build -Doptimize=ReleaseSafe -Demit-macos-app=false` on a macOS runner.

Why Linux is still unverified here: the Ubuntu job is **formatting only**, and
upstream's heavier suites are not effective in this fork. `test.yml` gates every
job on `github.repository == 'ghostty-org/ghostty'`, so it is inert here;
`nix.yml`, `flatpak.yml`, and `update-colorschemes.yml` carry the same guard.
`nix.yml` additionally targets `namespace-profile-ghostty-*` runners that do not
exist for this repository. 12 of the 16 workflow files have no repository guard
at all and would attempt to run. Neither a Linux build nor a Linux test is
executed by any workflow that can actually succeed in this fork. See
[CONTRIBUTING.md](CONTRIBUTING.md#9-continuous-integration).

**Honest statement:** Khostty's macOS *library* path is verified. Khostty's macOS
*application* is not verified in this fork; the blocker is external (a missing
Xcode component), not a code defect.

---

## 4. Linux

**Status: upstream-supported, NOT verified in this fork.**

Upstream provides a full GTK4 application runtime (`src/apprt/gtk.zig` plus
`src/apprt/gtk/`, ~8000+ lines) that is the default for Linux and FreeBSD.

| Item | Value |
|---|---|
| Runtime | `gtk` (default) |
| Renderer | `opengl` |
| Fonts | `fontconfig_freetype` |
| Display backends | x11 and/or wayland (`-Dgtk-wayland`, `-Dgtk-x11`) |
| Packaging | `flatpak/`, `snap/`, `dist/linux/` |

Why it is unverified here: G1 validated the macOS host build only. No Linux build
or run has been recorded in `docs/sessions/`. Treat Linux as "should work,
untested by us".

CI runs only `zig fmt --check` on Ubuntu (lint); it does not build or test on
Linux. That is a gap worth closing before claiming Linux support.

---

## 5. Windows

**Status: NOT STARTED (G3), scaffold only.**

This is the fork's headline delta: upstream has no Windows application runtime.
`Runtime.default` returns `.none` for Windows, so upstream produces no executable.

### What exists

`src/apprt/windows/` — an isolated scaffold:

| File | State |
|---|---|
| `mod.zig` | Module root; `resourcesDir` returns `null` |
| `App.zig` | `init`, `registerWindowClass`, `run` all return `error.Unimplemented` |
| `Window.zig` | HWND wrapper type |
| `surface.zig` | Routes `WM_SIZE`, `WM_PAINT`, `WM_ERASEBKGND`, `WM_CLOSE`, `WM_DESTROY`; delegates rendering to the stub |
| `renderer.zig` | `init`, `resize`, `renderFrame`, `invalidate` all return `error.Unimplemented` |
| `win32api.zig` | Win32 type aliases and `user32`/`kernel32`/`dwmapi` declarations |
| `ipc.zig` | Named-pipe transport; all operations return `error.Unimplemented` |

### What does not exist

- **No wiring.** `src/apprt.zig` selects `none`, `gtk`, `embedded`, or `browser`
  only. `src/apprt/windows/` is not reachable from the runtime switch, so no
  build currently compiles it as a runtime.
- **No cross-compilation evidence.** `zig build -Dtarget=x86_64-windows` has not
  been run and recorded here.
- **No run evidence.** No Windows binary has been launched, natively or under
  Wine.
- **No real Win32 calls.** `win32api.zig` declares function pointers; no code
  invokes them.

### Known defect (observed 2026-09-17)

`src/apprt/windows/mod.zig` imports `"Surface.zig"`, but the tracked file is
`surface.zig`. The import resolves only on a case-insensitive filesystem. Any
case-sensitive build that pulls `mod.zig` into the graph will fail.

### Windows IPC sketch

| Item | Value |
|---|---|
| Pipe name | `\\.\pipe\khostty-{server_pid}` intended; **the constant currently has one leading backslash, which is not the pipe namespace** (observed 2026-09-17) |
| Frame | `extern struct { action: u16, length: u32 }` + packed payload |
| Security attributes | **None declared.** The earlier null-DACL / inheritable-handle declaration was removed without a replacement, so no ACL design exists. |
| Status | SCAFFOLD, `error.Unimplemented` |

Details and the security implication: [SECURITY.md](SECURITY.md#4-windows-transport-weakness-scaffold).

### G3 exit criteria (from the WBS)

Cross-compile succeeds; the binary runs (native or Wine); keyboard and mouse
input encode correctly via `ghostty_key_encoder_*` / `ghostty_mouse_encoder_*`;
DirectWrite renders glyphs with font fallback; clipboard works with bracketed
paste; the named pipe accepts agent commands. None are met.

---

## 6. WebAssembly

**Status: IN PROGRESS (G7); artifact verified.**

| Item | Value |
|---|---|
| Target | `wasm32-freestanding` |
| Build | `wasm/build.sh` (pins target, isolates cache, validates magic + version) |
| Artifact | `813,670 bytes`, sha256 `08ac8ed881ffdae68b9f96f9afa6c834e57ba7ea49280d220e882938508e5bf6` |
| Module shape | 0 imports, 189 exports (187 `ghostty_*` functions + memory) |
| Runtime | Node ≥ 20; any browser with ESM + WebAssembly |
| Package | `@khostty/libghostty-vt-wasm` (private, `version 0.0.0`) |

### What works

The VT core: parser, screen, scrollback, cursor, styles, selection, search, render
state, snapshots, SGR, OSC, and key/mouse/focus encoding. The module is
freestanding with `rdynamic` exports, a growable indirect function table, no
entrypoint, and a 128 KB stack.

### What is excluded by design

| Excluded | Reason |
|---|---|
| Kitty graphics (16 functions) | Needs OS timestamps, unavailable when freestanding. Sequences are parsed and safely ignored. |
| PTY, filesystem, clock, timestamps | No OS |
| Renderer | `libghostty-vt` models state only. Draw the grid yourself, or use `html()`. |
| `web_canvas` font backend | Only relevant to the full browser app, not the VT-only library |

### Verification

```bash
cd wasm
npm run check    # header sync + typecheck + runtime/ABI tests + export dump
```

Reference for the export-count assertion: the ABI test requires the exported
function set to equal the consolidated header's declarations minus an explicit,
reasoned list — currently only the 16 `ghostty_kitty_graphics_*` entries.

### iOS note

The xcframework carries `ios-arm64` and `ios-arm64-simulator` slices of
`libghostty-vt`. The build system rejects the **full** Ghostty app for iOS (only
the library is supported there). No iOS build or run is recorded.

---

## 7. Feature availability by platform

| Feature | macOS | Linux | Windows | WASM |
|---|---|---|---|---|
| VT parsing / screen state | yes | yes | yes (library) | yes |
| Scrollback + reflow | yes | yes | yes (library) | yes |
| Snapshots | yes | yes | yes (library) | yes |
| Search | yes | yes | yes (library) | yes |
| Key / mouse / focus encoding | yes | yes | yes (library) | yes |
| Kitty graphics | yes | yes | yes (library) | **no** |
| C ABI | yes | yes | yes | via `wasm.h` |
| Rust wrapper | yes | yes | untested | n/a |
| JS/TS wrapper | n/a | n/a | n/a | yes |
| Native window | yes (Xcode) | yes (GTK4) | **no** | n/a |
| Clipboard integration | yes | yes | **no** | n/a |
| Agent IPC (3 actions) | yes | yes | **no** | n/a |
| Agent IPC (pane protocol) | **no server** | **no server** | **no server** | n/a |

"yes (library)" means the C library builds for that target and provides the
behaviour; it does not mean a Khostty application runs there.

---

## 8. What would change these verdicts

| Row | Evidence needed to move it |
|---|---|
| macOS app | A successful full build with a Metal toolchain present, then a launch |
| Linux | `zig build` on a Linux host, `zig build test`, and a GTK launch |
| Windows | `zig build -Dtarget=x86_64-windows` succeeding, then running the binary |
| WASM in a browser | A headless-Chromium smoke run (current tests are Node, exercising the same code path) |
| iOS | A build and run of a host app linking the xcframework slice |

Record the observation date with each result. A pass is only a pass for the
revision it was observed on.

---

## See also

- [BUILD.md](BUILD.md) — per-platform build commands
- [TESTING.md](TESTING.md) — how to produce the evidence above
- [FORK.md](FORK.md) — which platforms the fork actually adds
- [ARCHITECTURE.md](ARCHITECTURE.md) — the AppRT abstraction these defaults plug into
- Deep WBS: [`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](sessions/20260916-fork-assessment/02_DEEP_WBS.md)
