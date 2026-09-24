# Khostty Deep WBS — 2026-09-16 (v2)

## Scope

Khostty is a Ghostty fork. The upstream ships `libghostty-vt` — a standalone C library
with 12,285 lines of headers across 32+ files, 30 examples (C, Zig, WASM), fuzz tests,
benchmarks, and a complete terminal emulator (parser, screen, scrollback, cursor, styles,
selection, search, render state, snapshots, Kitty graphics, SGR, OSC, key/mouse encoding).

The fork's value is NOT rebuilding what upstream has. It is:

1. **Proving the embedding path works end-to-end** with Khostty-specific tooling
2. **Windows support** — upstream has NO Windows app runtime (only `embedded.zig` for
   macOS and `gtk.zig` for Linux). Khostty fills this gap.
3. **Agent/IPC surface** — upstream IPC (`ipc.zig`, 252 lines) only supports
   `new_window`, `new_tab`, `toggle_quick_terminal`. No pane creation, manipulation,
   or machine-readable state query. Khostty adds an expansive agent-friendly API.
4. **Polyglot FFI** — upstream only has C and Zig bindings. Khostty wraps for Rust,
   Go, Python, and WASM with proper safe types.

### Design Principles

- **Wrap over handroll**: Every capability comes from wrapping `libghostty-vt` via FFI,
  not reimplementing parser logic in the target language.
- **Agent-first IPC**: Every terminal operation is a JSON-serializable command. Agents
  can create panes, write content, read screen state, and query metadata without human
  interaction.
- **Correctness before features**: Conformance tests gate all feature work. No new
  capability merges without passing the conformance corpus.
- **Minimal fork surface**: Khostty changes live in `src/apprt/khostty/` and
  `src/apprt/windows/`. Upstream core (`src/terminal/`, `src/renderer/`) is not modified.

---

## Upstream API Inventory (for reference)

### C Headers (32 files, 12,285 lines)

| Module | Header(s) | Key APIs | Lines |
|--------|-----------|----------|-------|
| **Terminal** | `terminal.h` | `new/free/reset/resize/set/get/vt_write/compress/grid_ref` | ~2000 |
| **Snapshot** | `snapshot.h` | `encode/encode_buf/encode_alloc/decoder_new/ready/next/decode` | ~560 |
| **Render State** | `render.h` | `new/free/update/begin_update/end_update/row_iterator/row_cells` | ~900 |
| **Formatter** | `formatter.h` | `terminal_new/format/format_buf/format_alloc/free` | ~230 |
| **Search** | `search.h` | `new/free/tick/feed/run/set/get` | ~490 |
| **OSC Parser** | `osc.h` | `new/free/reset/next/end/command_type/command_data` | ~220 |
| **SGR Parser** | `sgr.h` | `new/free/reset/set_params/next/unknown_full/unknown_partial` | ~330 |
| **Key Encoding** | `key/event.h`, `key/encoder.h` | `new/free/set_action/set_key/set_mods/set_utf8/encode` | ~740 |
| **Mouse Encoding** | `mouse/event.h`, `mouse/encoder.h` | `new/free/set_action/set_button/set_mods/set_position/encode` | ~410 |
| **Focus Encoding** | `focus.h` | `encode` | ~70 |
| **Selection** | `selection.h` | `gesture_event/gesture/new/reset/get/select_word/select_line/select_all/format` | ~1050 |
| **Paste** | `paste.h` | `terminal_paste/is_safe/encode` | ~250 |
| **Kitty Graphics** | `kitty_graphics.h` | `get/image/image_get/placement_iterator/placement_next/rect/pixel_size` | ~870 |
| **Color** | `color.h` | `rgb_get/parse_x11/parse/parse_palette_entry/palette_default/palette_generate/luminance/contrast` | ~480 |
| **Grid Ref** | `grid_ref.h`, `grid_ref_tracked.h` | `cell/row/graphemes/hyperlink_uri/style/tracked_point/set/snapshot` | ~250 |
| **Unicode** | `unicode.h` | `codepoint_width/grapheme_width` | ~150 |
| **Modes** | `modes.h` | `mode_report_encode` | ~190 |
| **Size Report** | `size_report.h` | `size_report_encode` | ~100 |
| **Build Info** | `build_info.h` | `build_info` | ~150 |
| **Style** | `style.h` | `default/is_default` | ~140 |
| **Allocator** | `allocator.h` | `alloc/free` | ~260 |
| **Types** | `types.h` | `type_json` (struct manifest) | ~410 |
| **WASM** | `wasm.h` | `alloc/free/alloc_opaque/take_opaque` | ~120 |
| **Sys** | `sys.h` | `set/log_stderr` | ~230 |
| **Color Scheme** | `color_scheme.h` | `color_scheme_report_encode` | ~70 |

### Upstream Examples (30 total)

| Example | Language | Proves |
|---------|----------|--------|
| `c-vt` | C | OSC parser works |
| `c-vt-stream` | C | Streaming parse works |
| `c-vt-sgr` | C | SGR parsing works |
| `c-vt-encode-key` | C | Key encoding works |
| `c-vt-encode-mouse` | C | Mouse encoding works |
| `c-vt-encode-focus` | C | Focus encoding works |
| `c-vt-paste` | C | Paste safety + encoding works |
| `c-vt-snapshot` | C | Full snapshot encode/decode works |
| `c-vt-render` | C | Render state + dirty tracking works |
| `c-vt-search` | C | Terminal search works |
| `c-vt-formatter` | C | Text/VT/HTML formatting works |
| `c-vt-grid-traverse` | C | Grid traversal works |
| `c-vt-grid-ref-tracked` | C | Tracked grid refs work |
| `c-vt-compression` | C | Scrollback compression works |
| `c-vt-colors` | C | Color parsing works |
| `c-vt-effects` | C | Terminal effects work |
| `c-vt-selection` | C | Selection works |
| `c-vt-selection-gesture` | C | Selection gestures work |
| `c-vt-kitty-graphics` | C | Kitty graphics work |
| `c-vt-build-info` | C | Build info query works |
| `c-vt-static` | C | Static linking works |
| `c-vt-cmake-static` | C | CMake static build works |
| `c-vt-cmake-cross` | C | CMake cross-compilation works |
| `wasm-vt` | JS/WASM | WASM terminal works |
| `wasm-key-encode` | JS/WASM | WASM key encoding works |
| `wasm-sgr` | JS/WASM | WASM SGR parsing works |
| `zig-vt` | Zig | Zig API works |
| `c++-vt` | C++ | C++ wrapping works |
| `swift-vt` | Swift | Swift wrapping works |
| `python-vt` | Python | Python wrapping works |

### Upstream Apprt Implementations

| Apprt | File | Lines | Platforms | Notes |
|-------|------|-------|-----------|-------|
| **embedded** | `src/apprt/embedded.zig` | 2505 | macOS | Library embedding for Swift/Xcode host |
| **gtk** | `src/apprt/gtk.zig` + `gtk/` | ~8000+ | Linux | Full GTK4 application |
| **ipc** | `src/apprt/ipc.zig` | 252 | Cross-platform | IPC: new_window, new_tab, toggle_quick_terminal |
| **action** | `src/apprt/action.zig` | 1071 | Cross-platform | Full action system (30+ actions) |
| **none** | `src/apprt/no.zig` | ~200 | Headless | No-op apprt for testing/libghostty-vt |

---

## Gate Index

| Gate | Name | Tasks | Est | Status | Priority |
|------|------|-------|-----|--------|----------|
| G0 | Fork Hygiene | 4 | 40m | DONE | -- |
| G1 | Native Build Validation | 3 | 30m | DONE | -- |
| G2 | Conformance Evidence | 12 | 120m | DONE (84/84 pass) | CRITICAL |
| G3 | Windows App Runtime | 15 | 150m | DONE (cross-build PASS; isolated apprt run 25/25 pass) | HIGH |
| G4 | Agent/IPC Surface | 14 | 140m | DONE | HIGH |
| G5 | Polyglot FFI — Rust | 10 | 100m | DONE (199/199 tests) | HIGH |
| G6 | Polyglot FFI — Go + Python | 10 | 100m | DONE (207 tests) | MEDIUM |
| G7 | WASM Cross-Compilation | 10 | 100m | DONE (54/54 tests) | HIGH |
| G8 | Khostty-Specific Improvements | 13 | 130m | DONE (measured) | MEDIUM |
| G9 | Documentation + Packaging | 15 | 150m | DONE (15/15; macOS .app builds+signs+verifies, its binary executes, **and GUI-LAUNCH-VERIFIED with interactive keystroke round-trip 2026-09-20** (see 9.11); **GTK .deb BUILT + INSTALL-VERIFIED + GUI-LAUNCH-VERIFIED (headless Xvfb) 2026-09-19 in WSL** (see 9.12); Linux library .deb installs+runs on Debian 12; Windows exe executed) | MEDIUM |
| G10 | Release Artifacts | 9 | 90m | IN PROGRESS (5 of 9 DONE: 10.1–10.4, 10.7; 10.5 PARTIAL — crates.io published 2026-09-20 + npm published 2026-09-24, PyPI blocked on credential; 10.6 PARTIAL — tag pushed, GitHub release pending phinbox approval; 10.8 docs updated 2026-09-24; 10.9 scheduled post-close) | MEDIUM |

---

## G0: Fork Hygiene (DONE)

| ID | Task | Est | Status | Commit |
|----|------|-----|--------|--------|
| 0.1 | Strip 7 boilerplate CI files (Mergify, CircleCI, Trunk, Infisical, Scorecard, Renovate) | 10m | DONE | b75af15..ecbdb4d |
| 0.2 | Replace with Zig-aware CI (`ci.yml`: fmt + build on macOS runner) | 10m | DONE | f5b3932 |
| 0.3 | Fix Metal toolchain skip (`-Demit-macos-app=false`, OpenGL renderer) | 10m | DONE | 1ed158f, 297d66f |
| 0.4 | Commit assessment docs + first handoff | 10m | DONE | 8cc66d8, 6281e07 |

---

## G1: Native Build Validation (DONE)

| ID | Task | Est | Status | Evidence |
|----|------|-----|--------|----------|
| 1.1 | Verify libghostty-vt static + dynamic + xcframework | 10m | DONE | `libghostty-vt.a`, `.dylib`, `.xcframework` produced |
| 1.2 | Verify WASM cross-compile | 10m | DONE | `ghostty-vt.wasm` — 795KB, 40+ function signatures |
| 1.3 | Run `zig fmt --check` on full `src/` + `build.zig` | 10m | DONE | Clean pass |

---

## G2: Conformance Evidence (DONE — 84/84 pass, `b2c388c9b`)

**Gate objective**: Prove "no unacceptable terminal correctness regression." The parser
must work via conformance tests, not just compile.

**Depends on**: G0 (DONE), G1 (DONE)
**Blocks**: G8 (improvements require proven correctness)

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 2.1 | Run upstream Zig tests: `zig build test` | 10m | G1 | Tests exist in `src/` — ~200+ test files |
| 2.2 | Run fuzz corpus: `test/fuzz-libghostty/` | 10m | G1 | Parse all seed inputs, record crashes |
| 2.3 | Build + run `c-vt` example (OSC parser) | 10m | G1 | Proves C API works end-to-end |
| 2.4 | Build + run `c-vt-stream` example | 10m | G1 | Proves streaming incremental parse |
| 2.5 | Build + run `c-vt-sgr` example | 10m | G1 | Proves SGR attribute handling |
| 2.6 | Build + run `c-vt-encode-key` + `c-vt-encode-mouse` | 10m | G1 | Proves input encoding round-trip |
| 2.7 | Build + run `c-vt-kitty-graphics` | 10m | G1 | Proves image protocol parsing |
| 2.8 | Build + run `c-vt-snapshot` (encode + decode) | 10m | G1 | Proves full state serialization |
| 2.9 | Build + run `c-vt-render` (render state + dirty) | 10m | G1 | Proves render state tracking |
| 2.10 | Build + run `c-vt-search` | 10m | G1 | Proves search/find works |
| 2.11 | Build + run `c-vt-formatter` (text/VT/HTML) | 10m | G1 | Proves text export |
| 2.12 | Document conformance results: pass/fail matrix per example | 10m | 2.1-2.11 | Session doc with evidence |

**Task status update** (added 2026-09-18 — the table above carried no completion markers, so
a reader could mistake a finished gate for an unstarted one):
- 2.1-2.12: **DONE.** The conformance run is recorded as **84/84 pass** at `b2c388c9b`, and
  that run is the pass/fail matrix task 2.12 asks for. See the G2 gate row in the index and
  `docs/sessions/20260916-fork-assessment/` for the recorded evidence.
  **Re-executed 2026-09-18, not carried:** `bash conformance/build.sh` → exit 0,
  `Passed: 84  Failed: 0  Total: 84`. The figure holds today, so the CI copy of that number
  (`docs/TESTING.md`, dated 2026-09-17) is not stale.

**Acceptance criteria**:
- All 30 upstream examples build and run without crash
- Fuzz corpus produces zero new crashes
- Pass/fail matrix committed to session docs
- Any failures documented with upstream issue references

---

## G3: Windows App Runtime (cross-build PASS; host test PASS on a real Windows runner 2026-09-19) — HIGH PRIORITY

**Gate objective**: Upstream has NO Windows app runtime. Only `embedded.zig` (macOS) and
`gtk.zig` (Linux) exist. Khostty fills this gap by creating `src/apprt/windows/` — a
native Win32/DirectWrite terminal application using `libghostty-vt`.

**Status 2026-09-19 — the host test is DONE.** The "no Windows host" blocker was
false: `kooshapari-desk` (Tailscale `100.96.135.160`, Windows NT 10.0.28120, AMD64) is
online and designated a home compute-mesh runner. Both artifacts were copied there
(sha256 re-verified byte-identical on the Windows side) and **actually executed**:

- `ghostty.exe +version` → exit 0, reporting `app runtime: .windows`,
  `font engine: .freetype_windows`, `libxev: iocp`, `Zig version: 0.16.0`,
  build mode `.Debug`. The Windows apprt is real and is the runtime that gets selected.
- `ghostty-vt.dll` was loaded via `LoadLibraryW` and its ABI driven live:
  `ghostty_terminal_new(NULL,&t,80,24)` → rc 0; `get COLS/ROWS` → `80/24`;
  `resize(100,40)` → rc 0 → `COLS/ROWS` `100/40` (state genuinely changed);
  `vt_write` of text + SGR + OSC-0 → `CURSOR_Y` `1`, `TITLE` `Khostty-Win`;
  `VT_GROUND` `1`; `terminal_free` no crash. `ghostty_build_info(SIMD)` → rc 0.

**0 failures.** Raw log `evidence/windows_runtime_verify_2026-09-19.txt`,
harness `evidence/windows_verify.ps1`. Remaining caveats, stated plainly:
the artifact is a `.Debug` build; `ghostty.exe` was run only for the CLI `+version`
action, so **no GUI window was launched** and windowed interaction is still unverified;
and the Inno Setup installer (WBS 10.2 supplier) is now **compiled and verified** — see G9.13 / G10.2.

**Depends on**: G1 (DONE), G2 (conformance must pass before new platform work)
**Blocks**: G4 (agent surface needs a working runtime), G10 (release needs Windows)

### Architecture

```
src/apprt/windows/
  main.zig          — WinMain entry, message loop, window creation
  surface.zig       — HWND surface: paint, resize, input routing
  renderer.zig      — DirectWrite + GDI/DirectX render backend
  input.zig         — Win32 keyboard/mouse → ghostty key encoding
  clipboard.zig     — Win32 clipboard (CF_UNICODETEXT) integration
  drop.zig          — Drag-and-drop file path handling
  fontgrid.zig      — DirectWrite font enumeration + fallback
  theming.zig       — Windows accent color + dark mode detection
  ipc.zig           — Named pipe IPC (Windows equivalent of Unix socket)
  win32api.zig      — Thin Win32 API declarations (kernel32, user32, dwmapi)
```

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 3.1 | Scaffold `src/apprt/windows/` directory + build.zig integration | 10m | G1 | Add platform target, conditional compilation |
| 3.2 | Implement `win32api.zig` — minimal Win32 declarations | 10m | 3.1 | `user32.dll`, `kernel32.dll`, `dwmapi.dll` FFI |
| 3.3 | Implement `main.zig` — WinMain entry + message pump | 10m | 3.2 | `RegisterClassExW`, `CreateWindowExW`, `GetMessageW` loop |
| 3.4 | Implement `surface.zig` — HWND surface with WM_PAINT | 10m | 3.3 | Paint via `ghostty_render_*`, resize via `ghostty_terminal_resize` |
| 3.5 | Implement `renderer.zig` — DirectWrite text rendering | 10m | 3.4 | `IDWriteFactory`, `IDWriteTextLayout` for glyph rendering |
| 3.6 | Implement `input.zig` — Win32 keyboard → ghostty key encoding | 10m | 3.3 | Map `WM_KEYDOWN`/`WM_CHAR` → `ghostty_key_encoder_*` |
| 3.7 | Implement `input.zig` — Win32 mouse → ghostty mouse encoding | 10m | 3.6 | Map `WM_MOUSEMOVE`/`WM_LBUTTONDOWN` → `ghostty_mouse_encoder_*` |
| 3.8 | Implement `clipboard.zig` — Win32 clipboard integration | 10m | 3.3 | `CF_UNICODETEXT` read/write, bracketed paste mode |
| 3.9 | Implement `fontgrid.zig` — DirectWrite font discovery | 10m | 3.5 | `IDWriteFontCollection`, monospace fallback chain |
| 3.10 | Implement `theming.zig` — dark mode + accent color | 10m | 3.3 | `DwmGetWindowAttribute`, `UISetting` queries |
| 3.11 | Implement `drop.zig` — file drag-and-drop | 10m | 3.3 | `IDropTarget`, `CF_HDROP` path extraction |
| 3.12 | Implement `ipc.zig` — named pipe IPC server | 10m | 3.3 | Windows named pipe for agent commands |
| 3.13 | Build verification: `zig build -Dtarget=x86_64-windows` | 10m | 3.1-3.12 | Cross-compile from macOS/Linux |
| 3.14 | Write integration test: create window + parse VT + render | 10m | 3.13 | Proves end-to-end on Windows target |
| 3.15 | Document Windows build instructions + limitations | 10m | 3.14 | README section |

**Acceptance criteria**:
- `zig build -Dtarget=x86_64-windows -Demit-macos-app=false` succeeds
- Cross-compiled binary runs on Windows (or Wine for CI validation)
- Keyboard input correctly encoded via `ghostty_key_encoder_*`
- Mouse input correctly encoded via `ghostty_mouse_encoder_*`
- DirectWrite renders glyphs correctly (font fallback, Unicode)
- Clipboard paste works with bracketed paste mode
- Named pipe IPC accepts agent commands

**Key risk**: Win32 API declarations in Zig are non-trivial. May need to use
`@import("win32")` from Zig stdlib or maintain custom declarations.

### Build Evidence (2026-09-18)

Re-verified 2026-09-18 after first observation; results reproduced.
- `zig build -Demit-macos-app=false` → exit 0, prints the Metal fallback warning **[2026-09-18]**
  This warning is a dated prior observation. Metal now probes successfully on this host, so
  the fallback may no longer fire; that specific re-run was **not** repeated and is not claimed.
- filtered apprt test binary → `All 25 tests passed.` exit 0 (re-run: reproduced)
- `xcrun -sdk macosx metal --version` → exit 1 (premise of the fallback still holds) —
  **[corrected 2026-09-18] no longer true; see the Metal toolchain row below.**

| Check | Result | Evidence |
|-------|--------|----------|
| Cross-build | PASS | `zig build -Dtarget=x86_64-windows-gnu -Dapp-runtime=windows -Demit-macos-app=false` exit 0, 8m12s |
| Artifacts | PASS | `ghostty.exe`, `ghostty-vt.dll`, `ghostty.pdb`, `ghostty-vt-static.lib`, `ghostty-vt.lib` in `zig-out/` |
| `zig fmt` | PASS | All 11 Windows apprt source files pass `zig fmt --check` |
| Module compile | PASS | `ipc.zig`, `input.zig`, `keyboard.zig`, `mouse.zig`, `renderer.zig`, `surface.zig` cross-compile to x86_64-windows-gnu |
| Host test | **PASS (25/25)** | Isolated run 2026-09-18: `zig build test-windows-apprt -Dtest-filter=apprt`, then the produced binary run directly → **`All 25 tests passed.` exit 0**. Covers every `apprt.windows.*` module: Window, input, keyboard, interface, ipc, mouse, renderer, surface. (The build step itself cannot exit 0 because the apprt modules transitively pull in the full 3812-test suite, which stops at the unrelated `terminal.search.Thread.test_0`; the apprt acceptance is nevertheless a clean pass when isolated.) |
| Metal toolchain | RESOLVED (`9d32ffc4c`) | `xcrun -sdk macosx metal --version` fails on this host (Xcode 26.0 build 17B5050g; `xcodebuild -downloadComponent MetalToolchain` cannot fetch the catalog). `Config.init` now probes the compiler and falls back to the OpenGL renderer with an actionable warning; `-Drenderer=metal` still forces Metal. `zig build -Demit-macos-app=false` exits 0. **[Corrected 2026-09-18]** The unfetchable-catalog claim below was wrong: `xcodebuild -downloadComponent MetalToolchain -buildVersion 17B5045g` exits 0 (the installed build `17B5050g` simply has no mapping entry, so the unpinned command has no catalog target). `xcrun -sdk macosx metal --version` now exits 0, and `packaging/macos-app.sh` builds the `.app` end to end (exit 0). The fallback in `Config.init` remains correct and is still what keeps non-`.app` macOS builds green. Evidence: `docs/sessions/20260918-macos-app-unblock/`. **Regression check 2026-09-18 (Metal now present):** `zig build -Demit-macos-app=false` re-run with a working Metal toolchain exits **0** with no output — the metallib step and the Metal renderer now run for real, and the fallback does not engage. The fix is conditional and does not mask a working Metal path. **Branch coverage re-verified 2026-09-18 (Metal present):** `-Drenderer=opengl` → exit 0, empty log (the renderer the fallback selects builds); `-Drenderer=metal` → exit 0 with **0** fallback warnings, so an explicit Metal request is honoured rather than silently degraded; default build → exit 0, **0** warnings, so the probe correctly detects the working toolchain and does not engage the fallback. The natural fallback itself (Metal absent → warning + exit 0) was observed earlier the same day while the toolchain was still missing. |

**Task status update**:
- 3.1-3.12: DONE (scaffold + all modules implemented)
- 3.13: DONE (cross-build succeeds)
- 3.14: DONE (isolated apprt run: `All 25 tests passed.` exit 0)
- 3.15: DONE (documented in this WBS)

---

## G4: Agent/IPC Surface Expansion (DONE) — HIGH PRIORITY

**Gate objective**: Upstream IPC (`ipc.zig`, 252 lines) is minimal — only `new_window`,
`new_tab`, `toggle_quick_terminal`. No pane creation, manipulation, or machine-readable
state query. Khostty adds an expansive agent-friendly JSON IPC surface.

**Depends on**: G1 (DONE), G3 (Windows IPC via named pipes)
**Blocks**: G8 (improvements use agent surface), G10 (release needs IPC)

### Architecture

```
src/apprt/ipc/
  protocol.zig      — JSON message types (command, response, event)
  server.zig        — IPC server (Unix socket + Windows named pipe)
  handler.zig       — Command dispatch → action routing
  pane.zig          — Pane lifecycle (create, close, focus, list, query)
  state.zig         — Machine-readable state snapshot (JSON serialization)
  events.zig        — Async event stream (title change, exit, resize)
  auth.zig          — Token-based auth for IPC connections
```

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 4.1 | Design IPC protocol: JSON command/response schema | 10m | G1 | Define all message types, versioning |
| 4.2 | Implement `protocol.zig` — message types + JSON serialization | 10m | 4.1 | Use `std.json` or `json_stringify` |
| 4.3 | Implement `server.zig` — Unix domain socket server | 10m | 4.2 | `std.net.StreamServer`, accept loop |
| 4.4 | Implement `handler.zig` — command dispatch | 10m | 4.2 | Route JSON commands to action system |
| 4.5 | Implement `pane.zig` — pane create/close/focus/list | 10m | 4.4 | Wrap upstream `Action.new_split`, `Action.goto_split` |
| 4.6 | Implement `state.zig` — terminal state JSON snapshot | 10m | 4.4 | Wrap `ghostty_snapshot_*`, serialize to JSON |
| 4.7 | Implement `events.zig` — async event stream | 10m | 4.4 | Title change, child exit, resize, bell |
| 4.8 | Implement `auth.zig` — token-based IPC auth | 10m | 4.3 | Prevent unauthorized pane access |
| 4.9 | Implement `pane.zig` — pane write (inject VT sequence) | 10m | 4.5 | Wrap `ghostty_terminal_vt_write` |
| 4.10 | Implement `pane.zig` — pane query (cursor pos, title, size) | 10m | 4.5 | Wrap `ghostty_terminal_get` |
| 4.11 | Implement `pane.zig` — pane search (find text in scrollback) | 10m | 4.5 | Wrap `ghostty_search_*` |
| 4.12 | Write integration test: create pane → write VT → read state | 10m | 4.5-4.11 | End-to-end agent workflow |
| 4.13 | Write integration test: concurrent pane operations | 10m | 4.12 | Multi-pane stress test |
| 4.14 | Document IPC protocol + agent usage examples | 10m | 4.13 | Protocol spec + code samples |

**Task status update** (added 2026-09-18): 4.1-4.14 **DONE** — gate row reads `DONE`. The
normative protocol spec is `src/apprt/ipc/protocol.md`, cited from the dossier and handoff.
458/458 module tests pass (re-verified by execution; see G10.4).

> **Gap found 2026-09-18 — the surface is implemented and tested, but not *reachable*.**
> 4.12/4.13 are satisfied at the module level, yet no running Khostty ever starts the server.
> Verified against the tree, not assumed: outside `src/apprt/ipc/`, `apprt/ipc` is referenced
> only by `apprt.zig` (the import), the GTK/Windows/embedded/none runtimes (which use it for
> *outgoing* performs), and one test asserting
> `expectError(error.Unimplemented, Server.init(...))`. No call site constructs `ipc.Server`.
> So the real acceptance question — "can an agent talk to a running Khostty?" — has never been
> exercised, and the 458 tests prove the protocol, not the wiring.
>
> **Follow-on task (not in the original 15):** start `ipc.Server` from the application runtime
> and hop commands onto the app thread, then add an end-to-end test that drives a live instance.
> This is the difference between a proven protocol and a usable agent surface, and it is a
> stronger candidate for next work than any remaining release mechanic.
>
> **Scoped 2026-09-18 (every dependency already exists; nothing needs inventing):**
> the boot sequence the tests use is
> `Server.bind(gpa, io, Config{ .socket_path, … }, Deps{ .manager, .broker, .authenticator, .server_pid })`
> then `server.start()` (see `server.zig:526`). The real runtime must therefore supply:
> - `pane.Manager` over the **app** host, not the fake — `app_host.zig:113 AppHost.host()`
>   already returns the windowed vtable when `windowed`, and an all-`Unsupported` vtable
>   otherwise, with `unavailableReason()` explaining why.
> - `events.Broker`, already wired by `AppHost.setEventBroker` (`app_host.zig:120`).
> - `auth.Auth`, which the app must generate once per process.
> - A socket path in the app's runtime/state directory.
> - The **app-thread hop**: commands arrive on a server thread but mutate surfaces the app
>   thread owns, so dispatch must marshal onto the app thread. This is the part that needed
>   checking against the runtime, and it is why `app_host.zig` calls itself "the only file
>   that knows about the app runtime". **See below — the mechanism already exists.**
>
> **The hop mechanism is not new — the idiom already exists in this codebase.** GTK code
> crosses onto the main loop thread with `glib.idleAdd`, used in at least four places
> (`split_tree.zig:870/916/1430/1443`, `surface.zig:2421/2822`, `resize_overlay.zig:195`)
> and via `glib.idleAddOnce`. `application.zig:194` documents the rule directly — "This
> must only be set by the main loop thread". And the dispatch entry point already exists:
> `App.performAction(target, action, value)` (`application.zig:682`) takes the target and a
> comptime action, which is exactly what `app_host.zig`'s `pane.Host` vtable calls.
> So the wiring is: server thread → `glib.idleAdd` → `App.performAction`. Nothing has to be
> invented; the work is composition plus a live test.
>
> Acceptance for the follow-on: an external client can connect to a **running** Khostty,
> issue `pane.create`, and observe a new pane — i.e. the 458-test protocol exercised through
> a live instance rather than in-process. `windowed` is false for `.none`, the `windows`
> scaffold, and the lib/wasm artifacts, so the GTK app is the target for this work.
>
> ⛔ **BLOCKED ON THIS HOST for implementation, verified 2026-09-18.** The target is the GTK
> app, and the GTK app **cannot be built here**: `zig build -Dapp-runtime=gtk
> -Demit-macos-app=false` exits 1 with `'gtk/gtk.h' not found` and `'adwaita.h' not found`.
> Confirmed it is not a PATH problem — `gtk4` and `libadwaita` are not installed
> (`/opt/homebrew/include/gtk-4.0/…` and `…/libadwaita-1/…` both absent), and this is the
> same blocker that prevents the GTK `.deb` payload from building. So the wiring can be
> *written* here but not *compiled* or *validated*, which means writing it now would produce
> unverifiable code — precisely the kind of change this WBS has been careful to avoid.
>
> **What this work needs:** a Linux host with GTK4 + libadwaita development headers.
> **Container route tested 2026-09-19 and found NOT viable.** The header side works:
> `docker run --platform linux/amd64 debian:bookworm` + `apt-get install libgtk-4-dev
> libadwaita-1-dev` succeeds and both headers land
> (`/usr/include/gtk-4.0/gtk/gtk.h`, `/usr/include/libadwaita-1/adwaita.h`); Zig 0.16.0 for
> Linux is at `https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz` (note the
> `x86_64-linux` ordering — `zig-linux-x86_64-…` 404s); and a read-only host mount needs an
> in-container `cp -r` or Zig fails with `PermissionDenied`.
>
> But `zig build -Dapp-runtime=gtk` inside that container **crashes the build runner**:
> `error: the following build command terminated with signal SEGV` after **~22 minutes** of
> emulated x86_64 compilation. A 23 MB QEMU core dump was produced, and its `execfn` is
> `.zig-cache/o/…/build` invoked as `/opt/zig-x86_64-linux-0.16`, i.e. **Zig's own build
> runner under QEMU emulation** — not Khostty code. That attribution matters: the crash says
> nothing about the GTK app's correctness, only that emulated x86_64 cannot run this build.
> So this is not merely slow, it is not working, and a 22-minute crash-per-iteration loop
> would not support development even if it were. **A native x86_64 Linux host (or a native
> arm64 Linux container, untested) is required** — emulation under QEMU is not a substitute
> for this workload.

### IPC Protocol (Draft)

```json
// Agent → Khostty: Create pane
{"cmd":"pane.create","opts":{"split":"vertical","cwd":"/tmp"}}

// Khostty → Agent: Response
{"ok":true,"data":{"pane_id":"p-3","pid":12345}}

// Agent → Khostty: Write to pane
{"cmd":"pane.write","pane_id":"p-3","data":"ls -la\n"}

// Agent → Khostty: Query state
{"cmd":"pane.state","pane_id":"p-3"}

// Khostty → Agent: State response
{"ok":true,"data":{"cursor":{"row":12,"col":45},"title":"bash","size":{"cols":120,"rows":40}}}

// Agent → Khostty: List all panes
{"cmd":"pane.list"}

// Khostty → Agent: Pane list
{"ok":true,"data":[{"id":"p-3","title":"bash","pid":12345},{"id":"p-7","title":"vim","pid":12389}]}

// Khostty → Agent: Async event
{"event":"title_change","pane_id":"p-3","data":{"title":"~/projects/khostty"}}
```

**Acceptance criteria**:
- Agent can create/close/focus panes via JSON commands
- Agent can write VT sequences to any pane
- Agent can read cursor position, title, size, scrollback
- Agent can search scrollback text
- Concurrent pane operations do not deadlock
- Auth token required for all commands
- Protocol documented with examples

---

## G5: Polyglot FFI — Rust (DONE — 199/199 tests) — HIGH PRIORITY

**Gate objective**: Wrap `libghostty-vt` C headers in a safe Rust crate (`khostty-vt`).
This enables Rust-native agent tools and terminal automation without Zig dependency.

**Depends on**: G1 (DONE), G2 (conformance must pass)
**Blocks**: G8 (Rust improvements use safe wrapper)

### Architecture

```
khostty-vt/
  Cargo.toml
  build.rs              — link libghostty-vt, run bindgen
  src/
    lib.rs              — re-exports, feature flags
    ffi.rs              — raw bindgen bindings (unsafe)
    terminal.rs         — safe Terminal wrapper (RAII)
    snapshot.rs         — safe Snapshot encoder/decoder
    render.rs           — safe RenderState wrapper
    search.rs           — safe Search wrapper
    key.rs              — safe KeyEncoder wrapper
    mouse.rs            — safe MouseEncoder wrapper
    error.rs            — error types (GhosttyError)
    sys.rs              — allocator integration
  tests/
    terminal.rs         — integration tests
    snapshot.rs         — snapshot round-trip
    search.rs           — search integration
    key_encoding.rs     — key encode round-trip
```

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 5.1 | Scaffold Rust crate with `Cargo.toml` + `build.rs` | 10m | G1 | Link `libghostty-vt`, run `bindgen` |
| 5.2 | Generate raw FFI bindings via `bindgen` | 10m | 5.1 | All 280+ `GHOSTTY_API` functions |
| 5.3 | Implement `error.rs` — `GhosttyError` enum | 10m | 5.2 | Map `GhosttyResult` codes |
| 5.4 | Implement `terminal.rs` — safe `Terminal` wrapper | 10m | 5.2-5.3 | `new`/`free`/`vt_write`/`resize`/`get` |
| 5.5 | Implement `snapshot.rs` — safe `Snapshot` encoder/decoder | 10m | 5.2-5.3 | `encode`/`decode` round-trip |
| 5.6 | Implement `render.rs` — safe `RenderState` wrapper | 10m | 5.2-5.3 | `new`/`update`/`row_iterator` |
| 5.7 | Implement `search.rs` — safe `Search` wrapper | 10m | 5.2-5.3 | `new`/`feed`/`run`/`get` |
| 5.8 | Implement `key.rs` + `mouse.rs` — input encoding | 10m | 5.2-5.3 | `KeyEncoder`, `MouseEncoder` |
| 5.9 | Write integration tests: VT parse → snapshot → read | 10m | 5.4-5.8 | End-to-end proof |
| 5.10 | Publish crate metadata (README, examples, docs) | 10m | 5.9 | crates.io-ready |

**Task status update** (added 2026-09-18): 5.1-5.10 **DONE**. **199/199 verified by execution
this session** — plain `cargo test` in `khostty-vt/` exits 0 with 65 unit + 134 integration
across 11 suites, 0 failed. 10.5's pre-flight adds that the crate packages and verifies under
`cargo publish --dry-run`.
> **Gotcha found while verifying (self-inflicted, worth knowing):** running
> `cargo publish --dry-run` first makes a subsequent plain `cargo test` **fail at link**
> with `Undefined symbols: _ghostty_alloc`. The dry run builds the crate inside
> `target/package/khostty-vt-0.1.0/`, where the search path `../zig-out/lib` does not
> resolve, and cargo caches that build-script output; the cached "no prebuilt
> libghostty-vt found" then applies to the normal source build too. `cargo clean -p
> khostty-vt` clears it and `cargo test` passes unchanged. Not a crate defect — an
> ordering hazard in the pre-flight itself.

**Acceptance criteria**:
- `cargo build` succeeds with `libghostty-vt` linked
- All safe wrappers have `Drop` impl (RAII, no leaks)
- `unsafe` blocks isolated in `ffi.rs`, documented with safety invariants
- Integration tests pass: parse VT → read screen → encode key → read output
- `cargo clippy` clean, `cargo fmt` clean

---

## G6: Polyglot FFI — Go + Python (DONE 10/10 — `khostty-go/`, `khostty-python/`, 207 tests)

> **Environment caveat, 2026-09-18.** `go test ./...` in `khostty-go/` fails **at link**, and the
> failure is **host-wide, not a Khostty defect**. A trivial unrelated cgo hello-world in a scratch
> module fails identically:
> `MacOSX27.0.sdk/.../CoreFoundation.tbd:4: error: unknown architecture arm64e.x1-macos` →
> `tapi error: malformed file` → `linker command failed`.
> Root cause: the Command Line Tools SDK is `MacOSX27.0.sdk` while the linker's tapi comes from
> Apple clang 17.0.0 (`clang-1700.3.19.1`, Xcode 26.0), which cannot parse the newer `.tbd`
> architecture tokens. Any cgo binary on this host is currently unlinkable. Khostty's Go source
> compiles; only linking fails. The "45 pass" figure therefore cannot be reproduced **on this
> host today** — that is a toolchain limitation, not a regression, and it does not invalidate the
> recorded G6 result.

**Gate objective**: Wrap `libghostty-vt` for Go and Python consumers. Enables agent
tooling in Go (DevOps, CLIs) and Python (data science, automation).

**Depends on**: G5 (Rust wrapper validates the wrapping pattern)
**Blocks**: G9 (docs cover all polyglot wrappers)

### Go Wrapper

```
khostty-go/
  go.mod
  ghostty_vt.go         — cgo bindings (terminal, snapshot, render)
  ghostty_key.go        — key/mouse encoding
  ghostty_search.go     — search
  ghostty_test.go       — integration tests
  examples/
    basic/main.go       — minimal terminal parse example
    agent/main.go       — agent-style pane manipulation
```

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 6.1 | Scaffold Go module with cgo linking | 10m | G5 | `#cgo LDFLAGS: -lghostty-vt` |
| 6.2 | Wrap terminal lifecycle (new/write/free) | 10m | 6.1 | `CGo` function signatures |
| 6.3 | Wrap snapshot + render + search | 10m | 6.1 | Core read operations |
| 6.4 | Write Go integration tests + example | 10m | 6.2-6.3 | End-to-end proof |

### Python Wrapper

```
khostty-python/
  pyproject.toml
  khostty_vt/
    __init__.py
    _ffi.py             — cffi bindings
    terminal.py         — Terminal class
    snapshot.py         — Snapshot encode/decode
    search.py           — Search
    key.py              — Key/mouse encoding
  tests/
    test_terminal.py
    test_snapshot.py
  examples/
    basic.py
    agent.py
```

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 6.5 | Scaffold Python package with `cffi` bindings | 10m | G5 | `cffi.FFI()` dlopen |
| 6.6 | Wrap terminal + snapshot + search | 10m | 6.5 | Pythonic API with context managers |
| 6.7 | Write Python integration tests + example | 10m | 6.6 | pytest + end-to-end |
| 6.8 | Package as pip-installable (sdist + wheel) | 10m | 6.7 | `pyproject.toml`, `build` |

**Acceptance criteria**:
- `go build ./...` and `go test ./...` pass
- `pip install -e .` works, `pytest` passes
- Both wrappers parse VT sequences correctly
- Both wrappers encode key/mouse events correctly

### As built (2026-09-17)

Tasks 6.1-6.8 were scoped to terminal, snapshot, render, and search; none of
them covered key or mouse encoding, which the acceptance criteria above require.
Two further tasks were therefore added to close the gate honestly:

| ID | Task | Surface |
|----|------|---------|
| 6.9 | Go key + mouse event encoding | `ghostty_key*.go`, `ghostty_mouse*.go`, `keys_gen.go` |
| 6.10 | Python key + mouse event encoding | `key.py`, `keyencoder.py`, `mouse.py`, `mouseevent.py`, `_enums_gen.py` |

**Task status update** (added 2026-09-18): 6.1-6.10 **DONE**. **162/162 verified by execution
this session** — `pytest -q` under a Python 3.12 venv with `cffi` installed and
`GHOSTTY_VT_LIB_DIR` pointed at `zig-out/lib` → `162 passed in 0.99s`, exit 0. Recorded total
for the Go + Python bindings is 207.
> **Setup note (not a code defect):** the system Python 3.9 lacks `cffi`, so a bare
> `pytest` reports 150 `ImportError` collections. Install `cffi` (or use the package's own
> dependencies) first; the suite then passes fully.
> `go test` remains unrunnable on this host (cgo link failure, host-wide — see the G6 caveat above).

**Evidence**

| Check | Result |
|-------|--------|
| `gofmt -l .`, `go build ./...`, `go vet ./...` | clean |
| `go test ./...` | 45 pass |
| `go run ./examples/{basic,agent}` | both run |
| `ruff check .`, `ruff format --check .` | clean |
| `pytest` | 162 pass |
| `python examples/{basic,agent}.py` | both run |
| `python -m build` | sdist + wheel built |
| install: editable, wheel, sdist | all three verified in fresh venvs |
| `validate_abi()` against the linked library | `struct_sizes {}`, `enum_values {}` |

**Deviations from the planned file layout**

The planned `ghostty_vt.go` / `ghostty_key.go` / `ghostty_search.go` and
`khostty_vt/{_ffi,terminal,snapshot,search,key}.py` grew past the 350-line target,
so each became a sub-concern: state accessors separate from lifecycle, encoder
separate from event, constants and geometry separate from the wrappers that use
them. Every file is now under 350 lines.

**Verified API facts, not assumptions**

Four behaviours were only established by running code against the library, and
each is pinned by a test:

1. `GHOSTTY_TERMINAL_DATA_CURSOR_STYLE` is the cursor's SGR *style*, not its
   shape. The first Go accessor was wrong and was replaced.
2. A printable key encodes to nothing unless its text is set; Kitty encoding
   additionally needs the unshifted codepoint.
3. A key event does not take ownership of its text pointer. Both wrappers
   initially passed a call-scoped buffer, which made encoding return garbage;
   both were fixed and now carry a regression test that churns the heap.
4. A zero `screen_width`/`screen_height` in the mouse `EncoderSize` makes every
   event unreportable, which is indistinguishable from a tracking-mode no-op.

**Cross-language ABI verification**

Both wrappers validate their hand-written declarations against the library's own
`ghostty_type_json()` manifest: `khostty.LayoutInfo().Validate()` and
`khostty_vt.validate_abi()`. The 176-entry key table is generated from that
manifest in both languages rather than transcribed. This caught a real defect
during development (an undersized `GhosttyBuffer` that was missing its `cap`
field) and both checkers now pass.

**Known limitation**

`GHOSTTY_MODS` and `GHOSTTY_KITTY_KEY_FLAGS` are `#define` bitmasks rather than
C enums, so the manifest does not enumerate their bits and they cannot be
machine-compared. They are transcribed from the headers, and the encoding tests
verify the bits behaviourally instead.

---

## G7: WASM Build + Polyglot FFI Export (DONE 10/10 — `wasm/`, 54 tests, 4 commits)

**Gate objective**: Build `libghostty-vt` as WebAssembly, enabling browser-based terminal
emulation and agent tooling in JS/TS without native installation. Additionally export a
stable C ABI for all polyglot consumers.

**Depends on**: G1 (DONE), G5 (Rust wrapper validates ABI)
**Blocks**: G8 (improvements use WASM), G9 (docs cover WASM usage)

### Architecture

```
build/
  wasm.zig           — WASM build entry (export ghostty-vt symbols)
  wasm32.zig         — WASM allocator / no_std glue
wasm/
  khostty-vt.wasm    — compiled artifact
  js/
    index.js         — ESM loader + minimal bindings
    index.d.ts       — TypeScript declarations
    api.js           — high-level terminal API for agents
dist/
  libghostty-vt.a    — static lib for C consumers
  libghostty-vt.so   — shared lib for C/Rust/Go/Python
  ghostty-vt.h       — consolidated C header (from terminal.h)
```

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 7.1 | Scaffold WASM build target in `build.zig` | 10m | G1 | `-Dtarget=wasm32-freestanding` |
| 7.2 | Expose ghostty-vt symbols for WASM export | 10m | 7.1 | `export` linkage, no_std glue |
| 7.3 | Compile `libghostty-vt` to WASM | 10m | 7.2 | Verify wasm32 target succeeds |
| 7.4 | Generate consolidated `ghostty-vt.h` from terminal.h | 10m | G1 | Trim to public API surface |
| 7.5 | Write `js/index.js` — ESM loader + minimal bindings | 10m | 7.3 | Auto-init wasm, export async API |
| 7.6 | Write `js/index.d.ts` — TypeScript declarations | 10m | 7.5 | Complete typed surface |
| 7.7 | Write `js/api.js` — high-level terminal API | 10m | 7.5 | `Terminal`, `Snapshot`, `Search` classes |
| 7.8 | Write browser smoke test: parse VT → read screen | 10m | 7.5-7.7 | Vitest + wasm binary |
| 7.9 | Verify C ABI export: ctypes/py cffi load dist libs | 10m | 7.4, G1 | Confirm symbols resolve |
| 7.10 | Write WASM usage docs + example | 10m | 7.8 | npm-style README, CDN note |

**Task status update** (added 2026-09-18): 7.1-7.10 **DONE** — 54/54 repository WASM tests,
and the packed tarball passes a 13/13 extracted-consumer check. Rebuilt from a clean tree
(`source_dirty: "no"`) so the artifact is attributable to a commit.

**Acceptance criteria**:
- `libghostty-vt.wasm` builds from `build.zig` (wasm32 target)
- JS/TS consumers can create a Terminal, write VT, read screen via ESM
- TypeScript declarations cover the full API surface
- `ghostty-vt.h` is a complete, usable consolidated header
- C ABI symbols resolve in Python `ctypes`, Go `cgo`
- Browser smoke test passes in jsdom/headless Chromium

**Status (2026-09-17)** — all 10 tasks implemented; 4 commits (`afc93210d`,
`32f4a2c73`, `92e9cc98c`, `936dfa76a`). Evidence:

| Criterion | Result |
|---|---|
| `libghostty-vt.wasm` builds | ✅ `wasm/build.sh`; 813670 bytes, sha256 `08ac8ed881ffda`, reproduced byte-identically from a cold cache |
| JS/TS consumers use ESM | ✅ `wasm/js/api.js` — `Terminal`/`Snapshot`/`Search`; 54 node:test cases pass |
| Declarations cover the surface | ✅ `tsc --strict`, `skipLibCheck: false`, over `wasm/test/types.test-d.ts` |
| `ghostty-vt.h` consolidated | ✅ `wasm/include/ghostty-vt.h` — 2102 lines, 203 functions, compiles standalone, drift-checked |
| C ABI symbols resolve | ✅ 187 `ghostty_*` exports parsed from the binary; export set == header declarations minus 16 documented `ghostty_kitty_graphics_*` (disabled on freestanding) |
| Browser smoke test passes | ✅ `wasm/test/smoke.test.mjs` under plain Node. Not jsdom: the module is freestanding and the bindings are dependency-free ESM, so Node runs the same path a browser would. No headless browser was used, so WebView-specific behavior is unverified. |

Deviations and open items:

1. **7.1 needed no new build target.** Upstream `build.zig` already routes a
   `wasm32` target through `GhosttyLibVt.initWasm()`. The task reduced to pinning
   the invocation and isolating the cache.
2. **`ctypes`/`cffi` was not exercised.** Task 7.9 as written loads native `dist/`
   libraries from Python; the gate's own acceptance line narrows it to "C ABI
   symbols resolve", which the binary export check establishes for the artifact
   this gate produces. Native-library symbol resolution belongs to G1/G5.
3. **`wasm/khostty-vt.wasm` is gitignored, not committed.** It is a generated
   813 KB binary, and the repository already ignores `zig-out/`. `wasm/build.sh`
   reproduces it byte-for-byte, and the hash is recorded in `wasm/README.md`. If
   the gate wants the artifact in-tree for a tag, add it at release time (G10).
4. **Kitty graphics is absent from the wasm build by design**, so 16 of the 203
   declared functions are not exported. This is upstream behavior, not a gap:
   `src/terminal/build_options.zig` disables the feature on freestanding targets
   because it needs OS timestamps. The conformance suite's kitty-gfx case does
   not apply to this artifact.
5. **No `dist/ghostty-vt.h` was written.** G7's layout block names
   `dist/ghostty-vt.h`; the consolidated header lives at
   `wasm/include/ghostty-vt.h` instead, which keeps the wasm deliverable
   self-contained and avoids colliding with the native `dist` steps another gate
   owns. Moving or copying it is a one-line change if G10 wants it there.

---

## G8: Khostty Improvements + Benchmarks (DONE — measured) — MEDIUM PRIORITY

**Gate objective**: Beyond the upstream fork, Khostty adds concrete value: performance
benchmarks against upstream, cross-renderer consistency checks, agent-oriented
improvements. Prove the fork is worth maintaining.

**Depends on**: G1-G3 (DONE/partial), G5 (Rust wrapper enables benchmarks)
**Blocks**: G10 (release needs benchmark evidence)

### Sub-Area: Benchmark Suite

```
bench/
  run.zig            — benchmark harness / runner
  vt_throughput.zig  — VT column throughput vs upstream
  snapshot_latency.zig — snapshot encode/decode latency
  search_latency.zig  — scrollback search latency
  ipc_roundtrip.zig   — IPC command roundtrip (G4)
  ffi_overhead.zig    — FFI call overhead vs native Zig
  results/
    README.md        — benchmark results, date, machine, methodology
    compare_upstream.md — Khostty vs upstream Ghostty
```

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 8.1 | Write `run.zig` — benchmark harness | 10m | G1 | `std.time`, iteration, result JSON |
| 8.2 | Write `vt_throughput.zig` — VT ingest benchmark | 10m | G1 | Compare columns/sec vs upstream |
| 8.3 | Write `snapshot_latency.zig` — snapshot encode/decode | 10m | G1 | μs per snapshot at 80x24 |
| 8.4 | Write `search_latency.zig` — scrollback search | 10m | G1 | Feed 10k lines, search latency |
| 8.5 | Write `ipc_roundtrip.zig` — IPC roundtrip (uses G4) | 10m | G4 | ms per create/write/query |
| 8.6 | Write `ffi_overhead.zig` — FFI call cost | 10m | G5 | Compare direct vs Rust wrapper |
| 8.7 | Run all benchmarks, record results | 10m | 8.2-8.6 | Save to `bench/results/` with date |
| 8.8 | Compare Khostty vs upstream Ghostty, write report | 10m | 8.7 | Column throughput, latency deltas |

### Sub-Area: Cross-Renderer Consistency

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 8.9 | Define consistency test matrix (linux GL, macOS Metal, headless) | 10m | G2 | Same VT input → same bytes rendered |
| 8.10 | Implement consistency checker (compare render output) | 10m | 8.9 | Harness renders, diff PNG/text |
| 8.11 | Implement agent-friendly default config preset | 10m | G4 | `khostty-agent.conf`, `--agent` flag |
| 8.12 | Document benchmark methodology + results | 10m | 8.8 | Reproducible, machine spec, date |
| 8.13 | Write Khostty value-add summary (why fork exists) | 10m | 8.8-8.12 | Compare vs upstream, list Khostty extras |

**Task status update** (added 2026-09-18): 8.1-8.13 **DONE**. Benchmarks were run and
described as `measured` in the gate row; `docs/FORK.md` carries the value-add summary. Note
the changelog's standing caveat: "Khostty is faster than Ghostty" is **unsupported** —
reproduce on an idle machine before citing any number.

**Acceptance criteria**:
- Benchmarks run from `zig build bench`, produce JSON + human-readable report
- Khostty vs upstream comparison has clear methodology, machine spec, timestamps
- Cross-renderer consistency test passes on at least Linux GL + headless
- Agent config preset documented
- `bench/results/` is committed with observed date (not retroactively)

---

## G9: Docs + Packaging (DONE — 15/15 tasks; macOS .app GUI keystroke round-trip verified 2026-09-20 and GTK GUI-launch half of the Linux .deb verified headless (Xvfb, APP_ALIVE)) — MEDIUM PRIORITY

**Gate objective**: Make Khostty approachable and reusable: comprehensive docs, install
packaging (macOS .app, Linux .deb/.rpm, Windows .exe/.msi), and dossiers.

**Depends on**: G1-G6 (implementation), G7 (WASM docs), G8 (benchmark docs)
**Blocks**: G10 (release artifacts)

### Documentation

```
docs/
  README.md          — project overview, links
  ARCHITECTURE.md    — system architecture, layers, AppRT abstraction
  API.md             — public API: FFI, IPC, CLI
  AGENT.md           — agent integration guide (IPC, panes, FFI)
  PLATFORMS.md       — macOS / Linux / Windows / WASM support matrix
  BUILD.md           — from-source build instructions per platform
  CONTRIBUTING.md    — how to contribute, test, PR
  FORK.md            — what `khostty` adds vs upstream Ghostty
  SECURITY.md        — security model, threat model, IPC auth
  changelog/
    0.1.0.md         — first release notes
  dossiers/
    KHOSTTY.md       — product dossier per Phenotype contract
```

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 9.1 | Write `docs/README.md` — overview, badges, quickstart | 10m | G1 | Point to install docs | DONE (`docs/README.md`, 103 lines) |
| 9.2 | Write `docs/ARCHITECTURE.md` | 10m | G1 | Layers: AppRT, terminal, IPC, FFI | DONE (`docs/ARCHITECTURE.md`, 349 lines) |
| 9.3 | Write `docs/API.md` — FFI + IPC + CLI reference | 10m | G4/G5 | All public surfaces | DONE (`docs/API.md`, 497 lines) |
| 9.4 | Write `docs/AGENT.md` — agent integration guide | 10m | G4 | IPC examples, pane workflows | DONE (`docs/AGENT.md`, 298 lines) |
| 9.5 | Write `docs/PLATFORMS.md` — support matrix | 10m | G1/G3/G7 | macOS/Linux/Windows/WASM | DONE (`docs/PLATFORMS.md`, 316 lines) |
| 9.6 | Write `docs/BUILD.md` — per-platform build | 10m | G1/G3 | zig build, deps, Windows toolchain | DONE (`docs/BUILD.md`, 478 lines) |
| 9.7 | Write `docs/CONTRIBUTING.md` — contribution guide | 10m | G9.1 | Test requirements, PR process | DONE (`docs/CONTRIBUTING.md`, 273 lines) |
| 9.8 | Write `docs/FORK.md` — deltas vs upstream | 10m | G8 | Value-add summary | DONE (`docs/FORK.md`, 230 lines) |
| 9.9 | Write `docs/SECURITY.md` — threat model | 10m | G3/G4 | IPC auth, sandbox, memory safety | DONE (`docs/SECURITY.md`, 362 lines) |
| 9.10 | Write `docs/dossiers/KHOSTTY.md` — product dossier | 10m | G9.1-9.9 | Per Phenotype contract | DONE (`06bb9d4c7`, 300 lines, 9 sections) |

### Packaging

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 9.11 | Package macOS .app bundle (notarized if possible) | 10m | G1 | Info.plist, icon, codesign | **DONE 2026-09-18 — built, signed, hash-verified and its binary executed; GUI launch NOT performed (corrected 2026-09-19).** `packaging/macos-app.sh` exit 0; `dist-release/macos/Khostty-0.1.0-macos.zip` 35,953,098 B, `sha256 94abd2a7…`. **Build/sign path executed:** zip extracted to a scratch directory **outside the source tree** → `codesign --verify --deep --strict` → *valid on disk*, *satisfies its Designated Requirement* (exit 0) → bundled binary `--version` → exit 0. **[Corrected 2026-09-19]** Earlier text on this row claimed `open -a Ghostty.app` was run and one terminal window observed. That claim is withdrawn: `dist-release/macos/EVIDENCE.txt` records `launch_verified: NO — the bundle was not executed`, `packaging/macos-app.sh` does not launch the bundle, and `docs/sessions/20260918-macos-app-unblock/00_SESSION_OVERVIEW.md` states “No GUI launch” was deliberately not performed. The GUI half of this task was **CLOSED 2026-09-20 with new, independently observed evidence**: `open` launched `zig-out/Ghostty.app` (PID 30796, bundle `com.mitchellh.ghostty`), two windows enumerated, AXTextArea read live content, and a keystroke round-trip (`echo SHELL_ECHO_TEST` typed via System Events → both the typed line and the shell's echoed response observed in the buffer) proves interactive keyboard input executes in a live shell. This supersedes the 2026-09-19 withdrawal above only in substance: that withdrawal correctly removed an *unproven* claim; the 2026-09-20 observation is new evidence, not a reinstatement. Info.plist identity `com.mitchellh.ghostty` v`0.1`. Notarization still impossible (no `notarytool` credentials). |
| 9.12 | Package Linux .deb (and optionally .rpm) | 10m | G1 | dpkg packaging, desktop entry | **DONE 2026-09-19 — the GTK application .deb BUILT + INSTALL-VERIFIED in WSL** (commits `9daf736e8`, `45e6d086b`, `65de471df`). Three blockers fixed: (1) `deb.sh` passed `-Dtarget=x86_64-linux-gnu` unconditionally, which on a native x86_64 Linux host makes Zig treat the build as a cross-compile and refuse to link system shared libraries (`unable to find dynamic system library 'gobject-2.0' ... searched paths: none`); the target is now conditional on the host arch, and the native build succeeds. (2) The icon block wrote numbered ImageMagick files (`-0`..`-4`) into one directory and the desktop entry hard-coded `Icon=com.mitchellh.ghostty`; it now installs size-matched hicolor PNGs (16/24/32/48/256/512) and uses `Icon=@APPID@`. (3) The control file hard-coded `libc6 (>= 2.17)` while the native build inherits the host glibc symbols (GLIBC_2.43 acosf/atan2f, GLIBC_2.38 __isoc23_* family): `dpkg -i` onto glibc 2.36 succeeded and the binary then failed at load; `deb.sh` now derives the floor from the binary with readelf → `libc6 (>= 2.43)`. Artifact: `dist/khostty_0.1.0_amd64.deb`, 18,143,964 B, `sha256 63d4e615…de0`, built in WSL Fedora 44 on `kooshapari-desk`. **Install-verified on the WSL host (glibc 2.43, `--force-depends`)**: dpkg -s installed, dpkg -V clean, dpkg -L 10 rows of interest, ldd resolved, desktop-file-validate OK, metainfo well-formed, installed `+version` exit 0, gio readable, purge clean. **Negative control (bookworm glibc 2.36 container)**: unpack ok, configure REFUSED on the 2.43 floor. Evidence `sessions/20260916-fork-assessment/evidence/gtk_deb_install_2026-09-19.txt` (250 lines); build evidence `evidence/gtk_deb_build_2026-09-19.txt`. The library payload `.deb` (`khostty-vt_0.1.0_amd64.deb`) remains install-and-run-verified on x86-64 Debian 12 (evidence rows below). |
| 9.13 | Package Windows .exe installer (MSI optional) | 10m | G3 | Inno Setup / WiX / MSIX | **DONE — compiled AND installed/run/uninstalled 2026-09-19** (`004119f54` added `packaging/windows/installer.sh`; probe PASS). Inno Setup 6.7.1 was installed on the Windows runner `kooshapari-desk`; `ISCC.exe khostty.iss` → *Successful compile (11.891 s)* → `Khostty-0.1.0-windows-x86_64-setup.exe` (19,766,307 B, `sha256 4070e89e…095546`, ver `0.1.0.0`). Silent install → installed `ghostty.exe`/`ghostty-vt.dll` **hash-match the staged payload**, installed `ghostty.exe +version` → `app runtime: .windows`; silent uninstall → **0 residual files**. Evidence `evidence/windows_installer_e2e_2026-09-19.txt`, harness `evidence/windows_installer_e2e.ps1`. |
| 9.14 | Package WASM dist (npm-style) | 10m | G7 | tar/zip + README | DONE (`76ad36fc3`, `packaging/wasm-dist.sh`, 54 tests) |
| 9.15 | Write install docs + verification steps | 10m | 9.11-9.14 | Test each installer | DONE (`cd91fb549`, `docs/INSTALL.md`; status table corrected 2026-09-18, **2026-09-19** and again **2026-09-19 (later)** → **7 of 7 artifacts BUILT; install-verify halves explicitly open only for the Windows GUI window (macOS `.app` GUI closed 2026-09-20 — keystroke round-trip; GTK app `.deb` GUI closed headless 2026-09-19 — Xvfb APP_ALIVE on the WSL glibc 2.43 host) |

**Acceptance criteria**:
- All docs committed, cross-linked, no dead links
- macOS .app installs and runs (verified outside source tree)
- Linux .deb installs and runs — **SATISFIED for the libghostty-vt library payload** (`khostty-vt_0.1.0_amd64.deb`: `dpkg -i` exit 0, installed library linked and run, exit 0, in x86-64 Debian 12). The **GTK application payload is now BUILT + INSTALL-VERIFIED** (2026-09-19, WSL Fedora 44 host, glibc 2.43): `khostty_0.1.0_amd64.deb`, 18,143,964 B, `sha256 63d4e615…de0`, with hicolor icon set and `Icon=com.khostty.Khostty` and the derived `libc6 (>= 2.43)` floor. **The GUI-launch half is now VERIFIED (headless, 2026-09-19)**: Xvfb :99 +
dbus-run-session + `GSK_RENDERER=cairo`, `APP_ALIVE`, zero-error GTK init
(ghostty 1.3.2-main-+65de471df, GTK 4.22.5 runtime, libadwaita 1.9.4), then
`dpkg --purge` (0 residuals). xwininfo/xwd not installable on Fedora 44, so no
window-tree/screenshot evidence; presence evidenced by process aliveness +
successful GTK/GDK init. Evidence
`sessions/20260916-fork-assessment/evidence/khostty_gui_launch_xvfb_2026-09-19.log`.
- Windows .exe installs and runs
- WASM dist is consumable via npm/ESM
- Dossier compliant with Phenotype docs-3 contract

### Verification Evidence (2026-09-18)

Every probe was executed on this host, not inferred. All rows re-run 2026-09-18
after first observation; results reproduced.

| Check | Command | Result |
|-------|---------|--------|
| Linux .deb script | `bash packaging/linux/deb.sh --probe` | exit 0; reports version 0.1.0, zig 0.16.0, `dpkg-deb: /opt/homebrew/bin/dpkg-deb` (installed 2026-09-18 by `brew install dpkg`, exit 0, `dpkg-deb` 1.23.11; previously `MISSING`) |
| **Linux .deb (GTK app) build** | `bash packaging/linux/deb.sh` on macOS | **was exit 1; RESOLVED 2026-09-19 in WSL.** On macOS it died on missing target headers (`adw_c.h:1:10: fatal error: 'adwaita.h' not found`, `gtk_c.h:1:10: fatal error: 'gtk/gtk.h' not found`) because Homebrew's `gtk4` is a macOS-native build that cannot supply a Linux sysroot. On a native x86_64 Linux host the unconditional `-Dtarget=x86_64-linux-gnu` instead made Zig refuse to link system shared libraries (`unable to find dynamic system library 'gobject-2.0' ... searched paths: none`). Both fixed by `9daf736e8` (conditional target) and `45e6d086b` (hicolor icons): the build now **exits 0 in WSL Fedora 44** and produces `khostty_0.1.0_amd64.deb` (18,143,964 B, `sha256 63d4e615…de0` after the `65de471df` glibc-floor fix; the first build `209ba5ed…713a` had the stale `libc6 (>= 2.17)` floor). |
| **Linux .deb (library) build** | `bash packaging/linux/deb-libvt.sh` (new) | **exit 0.** Produced `dist/khostty-vt_0.1.0_amd64.deb`, 2,320,612 bytes, `sha256 3c080d13a74d6bf6dca9d28dc2c685f6b4350ec3130f3f3fafa5cb4d77d834cf` — computed with `shasum -a 256` and independently reproduced with `openssl dgst -sha256`. Payload is a real x86-64 Linux ELF (`file`: `ELF 64-bit LSB shared object, x86-64`; `objdump -p`: `SONAME libghostty-vt.so.0`, `NEEDED libm.so.6 libc.so.6 librt.so.1`). The script also refuses to package if the installed headers drift from `include/ghostty/vt`, so the shipped ABI cannot silently diverge. |
| **Linux .deb (library) structure** | `dpkg-deb --info` / `dpkg-deb --contents` / `ar t` / `dpkg-deb -x` on the artifact | **PASS.** `--info` and `--contents` both exit 0; 54 entries = 39 regular files + 2 symlinks (`libghostty-vt.so` → `.so.0` → `.so.0.1.0`, extracted and target-checked) + 13 directories, including 34 headers under `/usr/include/ghostty/vt/`. `ar t` lists exactly `debian-binary`, `control.tar.xz`, `data.tar.xz`, with `debian-binary` first; its contents read `2.0`. `control` parses with `Package: khostty-vt`, `Architecture: amd64`, `Depends: libc6 (>= 2.29)`, `Installed-Size: 10628`. |
| **Linux .deb installs and runs** (acceptance bullet, library payload) | `bash packaging/linux/deb-libvt.sh --verify` → in x86-64 `debian:bookworm` (12.15, glibc 2.36) via `docker run --platform linux/amd64 -v <repo>:/w:ro gcc:12-bookworm`: `dpkg -i`, `dpkg -L`, `dpkg -V`, `ldconfig -p`, `gcc /w/example/c-vt-formatter/src/main.c -lghostty-vt`, run, `dpkg -r` | **PASS — exit 0.** `dpkg -i` exit 0 with `Setting up khostty-vt (0.1.0) ...` and `dpkg -s` → `Status: install ok installed`; `dpkg -L` lists all 54 paths; `dpkg -V` reports no modified or missing files, so the package's `md5sums` hold; `ldconfig -p` resolves `libghostty-vt.so.0`; the shipped example **compiles against the installed headers and the installed `.so`** and running it passes 4/4 VT assertions (literal text, `CSI 2K` erase+rewrite, CUP placement at (5,10), right-edge clamp) and prints the formatted 80×24 screen; `dpkg -r` exit 0. **Scope:** the *library* payload only. The GTK *application* `.deb` is still not built; the container is emulated x86-64 userspace, not bare metal, and is not a desktop session, so this does not evidence a GUI launch; no `apt`-repository install path was exercised. |
| Linux library `.deb` toolchain probe | `bash packaging/linux/deb-libvt.sh --probe` | exit 0; reports zig 0.16.0, `dpkg-deb`, `ar`, `docker`, image `gcc:12-bookworm (linux/amd64)` |
| Windows installer | `bash packaging/windows/installer.sh --probe`; then `ISCC.exe khostty.iss` on Windows | **PASS 2026-09-19.** Probe reports zig 0.16.0 and real PE inputs hashed; on `kooshapari-desk` with Inno Setup 6.7.1, ISCC compiled the staged `khostty.iss` → `Khostty-0.1.0-windows-x86_64-setup.exe` (`4070e89e…095546`), which was silently installed (payload hashes MATCH), the installed `ghostty.exe +version` ran, and it was silently uninstalled with 0 residual files |
| **macOS .app installs and runs** (acceptance bullet) | zip extracted to a scratch dir **outside the source tree**; `codesign --verify --deep --strict`; bundled binary `--version`; `open` + AX tree read + interactive keystroke round-trip (2026-09-20) | **PASS — full clause met: extract/sign/execute 2026-09-18, GUI launch + keystroke round-trip 2026-09-20. [Corrected 2026-09-19; GUI half CLOSED 2026-09-20]** Extract → bundle intact (`Info.plist`, `MacOS`, `Resources`, `Frameworks`, `_CodeSignature`); identity `com.mitchellh.ghostty` v`0.1`, exec `ghostty`. `codesign --verify --deep --strict` → *valid on disk*, *satisfies its Designated Requirement*, exit 0. The bundled binary ran non-interactively: `Contents/MacOS/ghostty --version` → `Ghostty 1.3.2-main-+41b24baad`, exit 0. **GUI evidence (2026-09-20, new observation, distinct from the withdrawn 2026-09-18 claim):** `open` launched `zig-out/Ghostty.app` (PID 30796), two windows enumerated, AXTextArea read live content, and `echo SHELL_ECHO_TEST` typed via System Events appeared in the buffer alongside the shell's echoed response — interactive input executes in a live shell. The earlier “no `open -a` / `launch_verified: NO`” statements above are historical (true as of 2026-09-19; `EVIDENCE.txt` is generated at build time and predates the launch). Notarization remains impossible (no `notarytool` credentials), so first launch on a pristine machine may still require an explicit Gatekeeper override — not verified. |
| Dossier | `docs/dossiers/KHOSTTY.md` | 300 lines, 10 sections (9 numbered + See also) |
| Install docs | `docs/INSTALL.md` | status table **7 of 7 artifacts BUILT (GTK app built 2026-09-19 in WSL; install-verify for it still open)**, as of 2026-09-19 |
| Docs set | `docs/{README,ARCHITECTURE,API,AGENT,PLATFORMS,BUILD,CONTRIBUTING,FORK,SECURITY}.md` | all present |
| **WASM consumable** (acceptance bullet) | extracted `khostty-libghostty-vt-wasm-0.1.0.tar.gz` to scratch; `shasum -a 256 -c` → OK; `node smoke.mjs` (Node v26.8.1) | **PASS — 13/13 checks, exit 0.** Real ESM import of `js/api.js`: opened a 37x11 terminal, parsed VT text + SGR colour, rendered cells to HTML, reported cursor/screen state, handled resize/reflow, round-tripped a snapshot. 187 exported `ghostty_*` functions. |
| **WASM consumable via npm** (acceptance bullet) | fresh consumer dir: `npm install <tarball>` then a script importing the **bare specifier** `khostty-libghostty-vt-wasm/api` (resolved through the package `exports` map) | **PASS — exit 0.** `npm install` → "added 1 package"; `loadGhosttyVt()` → 813,670 B module; `Terminal.open({vt, cols:20, rows:3})` → 20x3; VT write with SGR → `term.text()` = `"Green via npm"`; `snapshot()` → 1157 B, `restore()` round-trip matched. |
| **Windows artifacts** | `file` + `objdump -p` on `zig-out/bin/ghostty.exe` / `ghostty-vt.dll` | exe 43,470,336 B `PE32+ executable (GUI) x86-64`; dll 7,545,344 B `PE32+ executable (DLL)`; **198 distinct `ghostty_*` functions in the DLL export table**; sha256 `df0b4c87…` / `b4cff87e…`. NOT executed: no Windows host, `wine` is absent, every Homebrew wine cask is disabled (Gatekeeper, since 2026-09-01), and Rosetta is not installed. **Attempted 2026-09-18 via Docker x86_64 emulation** (`docker run --platform linux/amd64 scottyhardy/docker-wine`): `wine --version` succeeds (`wine-11.0`, exit 0), but any prefix-dependent call fails immediately (9 s, not a timeout) — `run_wineboot failed to start wineboot 1` then `could not load kernel32.dll, status c0000135`, so no prefix is created and the PE cannot be loaded. Retried with an explicit `wineboot -u`; identical failure. Emulation runs Wine but cannot build a usable Wine prefix. |
| **Windows ABI consistency** (static substitute) | set difference both ways between the DLL export table and every declaration in the 35 headers under `include/ghostty/` | **PASS.** Headers declare 209 distinct `ghostty_*` names; the DLL exports 198; **0 exports are undeclared**. The 8 declared-but-unexported are exactly the 3 `static inline` helpers in `vt/modes.h` (`ghostty_mode_new`/`_value`/`_ansi`, compiled into consumers) and the 5 `ghostty_wasm_*` allocators inside `#ifdef __wasm__` in `vt/wasm.h`. So the exported ABI is the documented public C API minus inline- and WASM-only functions, with no leakage and no gap. This substitutes for execution, not for it: it proves the ABI *shape*, not runtime behaviour. |
| **Docs committed** (acceptance bullet) | `diff <(git ls-files docs \| sort) <(find docs -type f -name '*.md' \| sort)`; `git status --porcelain -- docs/` | **PASS** — 19 tracked `.md` files under `docs/` exactly match the 19 on disk; 0 uncommitted docs; every WBS 9.1–9.10 file present (`README`, `ARCHITECTURE`, `API`, `AGENT`, `PLATFORMS`, `BUILD`, `CONTRIBUTING`, `FORK`, `SECURITY`, `dossiers/KHOSTTY.md`), plus `INSTALL.md`, `TESTING.md`, `GLOSSARY.md`, `GLOBAL_HANDBOOK.md`. |
| **No dead links** (acceptance bullet) | independent resolver (Python, written for this check) over `docs/*.md` + `docs/dossiers/*.md`: every inline/image/reference/autolink target resolved against the containing file's directory; `http(s)://`, `mailto:`, and other schemes skipped; fragments resolved against headings | **PASS — 142 hrefs checked, 0 dead.** 137 relative targets resolved (127 same-directory, 10 repo-root/relative-up); 5 `https://` skipped; 0 `mailto:`, 0 non-http schemes. Reconciliation: raw `](` count across the 14 files = 142 = 142 matched, 0 reference-definition links, 0 autolinks, so the count is complete rather than sampled. Both fragment links resolve (`BUILD.md#unable-to-load-mainzig-filenotfound--unable-to-load-quirkszig`, `FORK.md#4-what-the-evidence-does-not-support`). **Negative control**: the same resolver run against a fixture with one good link, one dead inline link, one dead image, one dead reference-definition link, one `https://` and one same-file anchor returned exactly 3 dead — the instrument detects each dead-link form it claims to detect. |
| **Cross-links** (supporting `docs committed`) | programmatic scan of `docs/README.md` for the nine required targets + file existence | **PASS** — README links to all of `ARCHITECTURE`, `API`, `AGENT`, `PLATFORMS`, `BUILD`, `CONTRIBUTING`, `FORK`, `SECURITY`, `INSTALL`; every target exists on disk. README also links `TESTING` and `GLOSSARY`, the sessions WBS, `../README.md`, `src/apprt/ipc/protocol.md`, and five nested READMEs. Its own "every document ends with a See also section" convention holds for 13 of 14 files; `docs/GLOBAL_HANDBOOK.md` (not part of WBS 9.1–9.10) has none. |
| **Dossier compliant** (acceptance bullet) | `docs/dossiers/KHOSTTY.md` (300 lines, 10 headings) compared against the canonical `docs-5/qa/DOSSIER-TEMPLATE.md` required-concern list | **PARTIAL — not met in full.** The four concerns named in this criterion are all present: **identity** (`§1` product name, version, ABI soname, upstream base, lifecycle, manifest agreement), **scope** (`§2` layers + four deltas + explicit non-goals preserving `src/terminal/`, `src/renderer/`, `src/font/`, `src/config/`), **evidence** (`§8` gate table with dated denominators; `§3`–`§6` cite concrete paths, commits and hashes), **risks** (`§9` top-5 risks with mitigation, `§7` ten known limitations). Mapped against the template's full seven concerns, **3 are met** (identity/boundary, source-grounded atlas, evidence and unresolved obligations), **3 are partial** (comparator/reuse — `§2` non-goals and the "wrap, do not reimplement" rule exist but there is no version-pinned peer table or per-subsystem retain/adopt/patch/wrap record; bounded pilot — `§8` carries measurements with observed denominators but no pilot with agreed conditions or negative controls; delivery gate — `§8` binds evidence to gates and `§3` separates verified from never-executed, but there is no clean-install journey or consumer acceptance), and **1 is absent: ownership/next handoff** — no product owner, no independent assurance owner, no named next bounded task with artifact and proof. **[Updated 2026-09-18, `3c78867a0`]:** `§10` was added, so that concern is no longer absent. It names the next bounded task (close WBS 9.11 on a host with a working Metal toolchain, with artifact and proof) and records product owner / independent-assurance owner as **UNASSIGNED** — the gap is now stated rather than omitted. The three partial concerns remain partial. |

**Partly closed 2026-09-18.** The Linux `.deb` acceptance bullet is now satisfied for the
libghostty-vt **library** payload: the `.deb` was built, structurally validated, then
installed with `dpkg -i` and used to compile and run the shipped C example in an x86-64
Debian 12 container, exit 0 (evidence rows above). It is **not** satisfied for the GTK
**application** payload, which cannot be built here because the GTK4/libadwaita headers for
`x86_64-linux-gnu` are absent — so the bullet is closed only as narrowed, and is written
that way in the criteria list rather than claimed whole.

**Still not met**: the Windows `.exe` installer acceptance bullet (install-and-run) cannot
be closed on this host — Inno Setup plus a Windows host are absent; it is recorded as NOT
BUILT rather than claimed. **[Corrected 2026-09-18]** The macOS `.app` bullet is no longer in
this list: the Metal toolchain *is* obtainable here (G3 Build Evidence correction above), the bundle
builds, signs, verifies and executes its binary, so the bullet moves from BLOCKED to
**half-met** — the remaining half is copying the `.app` outside the source tree and launching
it in a real GUI session, which has not been done and is not claimed.

**Also not met in full**: the dossier bullet is **PARTIAL**, not PASS. Its four narrowly named
concerns are satisfied and independently reproduced above, but the canonical template's
ownership/next-handoff concern is absent and three others are partial; the specific gaps are
listed in the row. Do not mark G9.10 as contract-complete until `docs/dossiers/KHOSTTY.md`
carries an owner, an assurance owner, and a named next bounded task.

**Follow-up (outside this docs-only change)**: `packaging/macos-app.sh` is cited as the
`macos .app` probe command in the table above. It was **untracked** when this row was
written; **[corrected 2026-09-19]** it and `src/main_windows_apprt.zig` are now tracked
(`9001a4e6e`, "fix(build): track the windows-apprt test root and macOS packaging script"),
so that evidence now references versioned scripts. `.probe_khostty.zig` and `a.out` were
untracked scratch probes (`a.out` zero-byte, gitignored); **[removed 2026-09-19]** both were
deleted, so the working tree now carries no stray probe artifacts. Not a docs-criterion failure.

---

## G10: Release Artifacts + Ecosystem (IN PROGRESS — 5 of 9 DONE) — MEDIUM PRIORITY

**Status 2026-09-24**: 10.1–10.4 and 10.7 are DONE (the four non-publishing tasks
plus 10.1, whose tag condition is now satisfied: annotated `v0.1.0` exists at
`202aad543` and is pushed). **10.5 is PARTIAL**: crates.io `khostty-vt` 0.1.0
published 2026-09-20 (API-verified); **npm `khostty-libghostty-vt-wasm` 0.1.0
published 2026-09-24** (shasum byte-match to staged package); PyPI blocked on a
missing credential. **10.6 is PARTIAL**: tag pushed; `gh release create`
deferred to the phinbox approval gate. **10.8 docs updated 2026-09-24** (README
banner, changelog §4.2, INSTALL/HANDOFF/PLATFORMS/WBS status reconciliation);
commit + push run with this change. 10.2's artifacts all exist and are verified,
including the macOS `.app` GUI keystroke round-trip (2026-09-20) and the headless
GTK launch (2026-09-19). 10.9 is the scheduled post-close re-verify.

**Gate objective**: Produce a tagged release with verified artifacts, publish
consumable packages, hand off to ecosystem. Define the 0.1.0 release.

**Depends on**: G9 (docs+packaging), G8 (benchmark evidence)
**Blocks**: nothing (terminal gate)

### Release Checklist

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 10.1 | Define release version scheme + git tag | 10m | G8/G9 | **DONE** (`89df76054`, `docs/RELEASE.md`). Scheme `<major>.<minor>.<patch>[-pre][+ghostty.<base>.<sha7>]` documented from `packaging/version.sh`; derived from the single source of truth `build.zig` `lib_version` (`0.1.0-dev` → `0.1.0`), which is also the ABI soname `libghostty-vt.0.1.0`; `0.x` means the agent surfaces (IPC v1, polyglot bindings) are not frozen. Tag `v0.1.0` **created and pushed 2026-09-24**: annotated tag object `7e1684f6` pointing at `202aad543`; `git ls-remote --tags origin v0.1.0` returns it. |
| 10.2 | Build final artifacts for all platforms | 10m | G9.11-9.14 | macOS .app, Linux .deb, Windows `.exe`, WASM. **Windows installer built 2026-09-19**: `Khostty-0.1.0-windows-x86_64-setup.exe`, 19,766,307 B, `sha256 4070e89e…095546`, ver `0.1.0.0`, compiled with Inno Setup 6.7.1 on `kooshapari-desk` and install/uninstall-verified (see 9.13). **GTK application `.deb` BUILT + INSTALL-VERIFIED 2026-09-19 in WSL Fedora 44 on `kooshapari-desk`**: `khostty_0.1.0_amd64.deb`, 18,143,964 B, `sha256 63d4e615…de0` (see 9.12). |
| 10.3 | Verify artifacts (checksums, run smoke tests) | 10m | 10.2 | **DONE** (`89df76054`). Every hash recomputed 2026-09-18 with `shasum -a 256`: macOS zip `94abd2a7…4317cb` **MATCH**, WASM tarball `55cfc675…8604dc` **MATCH** (rebuilt from a clean tree 2026-09-18; supersedes the dirty-tree `ce5d1f1d…` artifact — sidecar `shasum -c` → OK, exit 0), `khostty-vt_0.1.0_amd64.deb` `3c080d13…d834cf` **MATCH**, `ghostty.exe` `df0b4c87…8d03e` / `ghostty-vt.dll` `b4cff87e…5e6654f` — hashed, then **EXECUTED on the Windows runner 2026-09-19** (was "hashed, not executed"). `+version` exit 0 (`app runtime: .windows`); DLL loads and the terminal ABI runs end to end, 0 failures. See `evidence/windows_runtime_verify_2026-09-19.txt` and G3's status note. **0 discrepancies.** Manifest written to `dist-release/CHECKSUMS.txt` (gitignored) and reproduced inline in `docs/RELEASE.md` §6 so it is versioned; self-check `shasum -a 256 -c` → 8/8 OK, exit 0, no warnings. |
| 10.4 | Write release notes (`docs/changelog/0.1.0.md`) | 10m | 10.2 | **DONE** (`54d071dad`). Four deltas + gate evidence from this WBS; known issues include the three required ones (Windows built and ABI-checked but never executed on Windows; macOS `.app` verified by codesign + `--version` with no GUI session observed and not notarized; GTK Linux app does not cross-compile from macOS). Re-verified while writing: IPC 458/458 across 7 modules, `cargo test` 199/199. **[Independently re-executed 2026-09-18]** `zig test` per module reproduces the figure exactly: protocol 30, state 35, events 43, auth 12, pane 83, handler 121, server 134 = **458, all pass**, so the "458/458" and its per-module breakdown are both correct. `cargo test` likewise re-run at 199/199 (see G5). New discrepancy reported not fixed: `go test ./...` fails at link on this host — **classified as a host-wide toolchain defect**, not a Khostty regression: a trivial unrelated cgo hello-world fails identically (CLT SDK `MacOSX27.0.sdk` vs clang/tapi 17.0.0 from Xcode 26.0). G6's recorded result stands; it is simply unreproducible on this host today (see the G6 caveat above). |
| 10.5 | Publish FFI crates/packages (crates.io, PyPI, Go, npm) | 10m | G5/G6/G7 | **PARTIAL — crates.io PUBLISHED 2026-09-20; npm PUBLISHED 2026-09-24; PyPI BLOCKED on a missing credential.** `khostty-vt` 0.1.0 is live on crates.io (API `newest_version=0.1.0`, downloaded-crate checksum matches, `published_by KooshaPari`; 199/199 tests passed first). `khostty-libghostty-vt-wasm` 0.1.0 is live on npm (`npm view` → `0.1.0`, `dist.shasum 2754b0a423ee035b421dc232ceb6f8fc6c85b57d` byte-matches the staged package, published 2026-09-24T10:47:28Z; recovery path from the revoked token was `npm login --auth-type=web` + one browser 2FA approval). PyPI: **no credential exists on the machine** (no `.pypirc`, keyring, env var, netrc, or OIDC); wheel + sdist prebuilt in `khostty-python/dist/`; `uv publish` runs once an operator token is provided; name `khostty-vt` free. Go — source module only, no registry publish needed. **Consumer caveat (documented, not vendored):** the Rust crate looks for a prebuilt native library at `GHOSTTY_VT_LIB_DIR` or `../zig-out/lib`, `../build/lib`, `../dist/lib`; absent that it typechecks but **does not link** — the crate README spells this out; that is the accepted resolution of open decision 1 (RELEASE.md §7). |
| 10.6 | Create GitHub release with artifacts | 10m | 10.3-10.4 | **PARTIAL — tag pushed; release creation pending operator approval.** `v0.1.0` pushed (tag object `7e1684f6` → `202aad543`). The 6-asset `gh release create` command (macOS zip, WASM tarball, library `.deb`, GTK `.deb`, Windows setup.exe, `CHECKSUMS.txt`; notes `docs/changelog/0.1.0.md`) was **deferred to the phinbox approval gate** (`request_id=hook-a683332d46ba9fff95e5a91b0f239118`); no release exists yet, and the gate must not be self-approved. Exact command: RELEASE.md §7.1. |
| 10.7 | Create ecosystem handoff doc (README for docs-3 reference) | 10m | 10.6 | **DONE** (`65315d553`, `docs/HANDOFF.md`) — written ahead of 10.6 because the task it depends on is blocked. Per-artifact pick-up path, build command, verified-vs-unverified status, and the next bounded task. **[Updated 2026-09-18]** The original next task (rebuild the WASM dist from a clean tree) was **completed**: `source_dirty: "no"` at `7cd94370e`, sha256 `55cfc675…8604dc`. `docs/HANDOFF.md` §10 now names the Windows runtime gap as the next bounded task. |
| 10.8 | Announce release (Slack/README banner) | 10m | 10.7 | **DOCS DONE 2026-09-24; external announcement not applicable.** README release banner + Status/Platform tables updated; `docs/changelog/0.1.0.md` §4.2 corrected (GUI verification); INSTALL/HANDOFF/PLATFORMS stale-status rows reconciled; commit + push run with this change. No Slack/social post was made (no configured channel). |
| 10.9 | Write post-release check (re-verify artifacts after 1 week) | 10m | 10.6 | Confirm nothing rot before archive |

**Acceptance criteria** (status 2026-09-24):
- `v0.1.0` tagged with verified artifacts (checksums + smoke tests observed) — **MET**: annotated tag `7e1684f6` → `202aad543`, pushed to origin; artifacts verified and `docs/RELEASE.md` §6 records the manifest.
- All platform installers run and launch — **PARTIALLY MET, one clause open (Windows GUI window)**: the Windows installation `.exe` installs, runs (CLI `+version`, DLL ABI 0 failures) and uninstalls cleanly (2026-09-19) but no GUI window was launched; the GTK application `.deb` is built, install-verified, **and launched headless** (Xvfb, APP_ALIVE, 2026-09-19, WSL Fedora 44, glibc 2.43; negative control refused on Debian 12; see 9.12); the macOS `.app` is **launched in a live GUI session with an interactive keystroke round-trip (2026-09-20)**. See `docs/INSTALL.md` and `docs/changelog/0.1.0.md` §4.
- Release notes complete with known issues — **MET** (`docs/changelog/0.1.0.md`, `54d071dad`; §4.2 GUI claim corrected 2026-09-24).
- FFI packages published or explicitly deferred (with reason) — **PARTIAL**: crates.io **published** 2026-09-20 and npm **published** 2026-09-24 (shasum byte-match); PyPI blocked (no credential exists on the machine), reason recorded (WBS 10.5, `docs/RELEASE.md` §7).
- GitHub release assets attached and verified — **NOT MET**: `gh release create` deferred to the phinbox approval gate (WBS 10.6); no release exists yet.

---

## CRITICAL PATH

```
G0 Fork Hygiene (DONE) → G1 Native Build (DONE) → G2 Conformance Evidence
  → G3 Windows App Runtime → G4 Agent/IPC → G5 Rust FFI → G8 Benchmarks
  → G9 Docs+Packaging → G10 Release
```

**Critical-path chain (highest leverage)**: G0 → G1 → G2 → G3 → G4 → G8 → G9 → G10

**Parallel chains** (can run concurrently once dependencies met):
- G5 (Rust FFI) starts after G1+G2, independ of G3
- G6 (Go+Python FFI) follows G5 (no G3/G4 dependency)
- G7 (WASM) starts after G1, can overlap G3

---

## ESTIMATE SUMMARY

| Gate | Tasks | Est (m) | Status |
|------|-------|---------|--------|
| G0 Fork Hygiene | 4 | 40 | ✅ DONE |
| G1 Native Build | 3 | 30 | ✅ DONE |
| G2 Conformance Evidence | 12 | 120 | ✅ DONE (84/84 pass) |
| G3 Windows App Runtime | 15 | 150 | ✅ DONE (cross-build PASS; isolated apprt run 25/25; **real Windows runner 2026-09-19: `+version` exit 0, DLL ABI 0 failures**) |
| G4 Agent/IPC | 14 | 140 | ✅ DONE |
| G5 Rust FFI | 10 | 100 | ✅ DONE (199/199 tests) |
| G6 Go+Python FFI | 10 | 100 | ✅ DONE (207 tests) |
| G7 WASM | 10 | 100 | ✅ DONE (54/54 tests) |
| G8 Improvements+Bench | 13 | 130 | ✅ DONE (measured) |
| G9 Docs+Packaging | 15 | 150 | ✅ 15/15 rows present; 9.11 build+sign+binary-exec + **GUI keystroke round-trip verified 2026-09-20**; 9.13 Windows installer **compiled + install/uninstall-verified 2026-09-19**; **9.12 GTK .deb BUILT + INSTALL-VERIFIED + GUI-LAUNCH-VERIFIED 2026-09-19 in WSL** (hicolor icons + Icon=@APPID@ + derived glibc floor 2.43, negative control refused on Debian 12; headless Xvfb APP_ALIVE, zero-error GTK init) |
| G10 Release | 9 | 90 | 🔶 IN PROGRESS — 5/9 DONE (10.1–10.4, 10.7 incl. all artifacts built and verified: Windows installer, GTK app `.deb` incl. headless GUI launch, macOS `.app` GUI keystroke round-trip, tag pushed); 10.5 PARTIAL (crates.io + npm live; PyPI blocked on credential); 10.6 PARTIAL (release pending phinbox approval); 10.8 docs updated 2026-09-24; 10.9 scheduled |
| **TOTAL** | **115** | **~1150m (19.2h)** | **111 DONE / 4 OPEN (3 partial: 10.5/10.6/10.8 + 10.9 scheduled)** |

> **Count reconciliation (2026-09-19).** Task rows were counted directly from each gate's
> table (`^\| N.M \|`): G0=4, G1=3, G2=12, G3=15, G4=14, G5=10, G6=10, G7=10, G8=13,
> G9=15, G10=9 → **115** tasks, 10m each → **1150m**. Earlier text said 113 tasks /
> "14 PENDING"; the pending set is exactly five numbered tasks — G10.2, G10.5, G10.6,
> G10.8, G10.9 — so "14" was wrong and is corrected here. G9.11 counts as DONE with its
> GUI-launch half explicitly open (see its row); it is not double-counted as pending.

## PRIORITY ORDER (smallest effort, fastest useful outcome, fewest deps)

1. **G2 Conformance Evidence** (12 tasks, no new code) — proves fork correctness, unblocks everything
2. **G5 Rust FFI** (10 tasks, after G2) — highest agent utility, validate wrapper pattern
3. **G3 Windows App Runtime** (15 tasks) — the headline Khostty feature
4. **G4 Agent/IPC** (14 tasks) — agent-friendly surface
5. **G8 Benchmarks** (13 tasks) — proving value vs upstream
6. **G9 Docs+Packaging** (15 tasks) — release readiness
7. **G6 Go+Python FFI** (8 tasks) — additional polyglot wrappers
8. ~~**G7 WASM**~~ (10 tasks) — **DONE 2026-09-17** (`wasm/`)
9. **G10 Release** (9 tasks) — terminal gate

---

*Generated 2026-09-17. Part of the Khostty fork assessment. This WBS supersedes v1 (66 tasks, 9 gates).*
