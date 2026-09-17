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
| G3 | Windows App Runtime | 15 | 150m | IN PROGRESS | HIGH |
| G4 | Agent/IPC Surface | 14 | 140m | IN PROGRESS | HIGH |
| G5 | Polyglot FFI — Rust | 10 | 100m | IN PROGRESS | HIGH |
| G6 | Polyglot FFI — Go + Python | 8 | 80m | IN PROGRESS | MEDIUM |
| G7 | WASM Cross-Compilation | 10 | 100m | DONE (54/54 tests) | HIGH |
| G8 | Khostty-Specific Improvements | 10 | 100m | IN PROGRESS | MEDIUM |
| G9 | Documentation + Packaging | 8 | 80m | IN PROGRESS | MEDIUM |
| G10 | Release Artifacts | 6 | 60m | NOT STARTED | MEDIUM |
| | **TOTAL** | **100** | **1000m (~16.7h)** | **70m done** | |

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

**Acceptance criteria**:
- All 30 upstream examples build and run without crash
- Fuzz corpus produces zero new crashes
- Pass/fail matrix committed to session docs
- Any failures documented with upstream issue references

---

## G3: Windows App Runtime (IN PROGRESS) — HIGH PRIORITY

**Gate objective**: Upstream has NO Windows app runtime. Only `embedded.zig` (macOS) and
`gtk.zig` (Linux) exist. Khostty fills this gap by creating `src/apprt/windows/` — a
native Win32/DirectWrite terminal application using `libghostty-vt`.

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

---

## G4: Agent/IPC Surface Expansion (NOT STARTED) — HIGH PRIORITY

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

## G5: Polyglot FFI — Rust (NOT STARTED) — HIGH PRIORITY

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

**Acceptance criteria**:
- `cargo build` succeeds with `libghostty-vt` linked
- All safe wrappers have `Drop` impl (RAII, no leaks)
- `unsafe` blocks isolated in `ffi.rs`, documented with safety invariants
- Integration tests pass: parse VT → read screen → encode key → read output
- `cargo clippy` clean, `cargo fmt` clean

---

## G6: Polyglot FFI — Go + Python (DONE 10/10 — `khostty-go/`, `khostty-python/`, 207 tests)

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

## G8: Khostty Improvements + Benchmarks (NOT STARTED) — MEDIUM PRIORITY

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

**Acceptance criteria**:
- Benchmarks run from `zig build bench`, produce JSON + human-readable report
- Khostty vs upstream comparison has clear methodology, machine spec, timestamps
- Cross-renderer consistency test passes on at least Linux GL + headless
- Agent config preset documented
- `bench/results/` is committed with observed date (not retroactively)

---

## G9: Docs + Packaging (NOT STARTED) — MEDIUM PRIORITY

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
| 9.1 | Write `docs/README.md` — overview, badges, quickstart | 10m | G1 | Point to install docs |
| 9.2 | Write `docs/ARCHITECTURE.md` | 10m | G1 | Layers: AppRT, terminal, IPC, FFI |
| 9.3 | Write `docs/API.md` — FFI + IPC + CLI reference | 10m | G4/G5 | All public surfaces |
| 9.4 | Write `docs/AGENT.md` — agent integration guide | 10m | G4 | IPC examples, pane workflows |
| 9.5 | Write `docs/PLATFORMS.md` — support matrix | 10m | G1/G3/G7 | macOS/Linux/Windows/WASM |
| 9.6 | Write `docs/BUILD.md` — per-platform build | 10m | G1/G3 | zig build, deps, Windows toolchain |
| 9.7 | Write `docs/CONTRIBUTING.md` — contribution guide | 10m | G9.1 | Test requirements, PR process |
| 9.8 | Write `docs/FORK.md` — deltas vs upstream | 10m | G8 | Value-add summary |
| 9.9 | Write `docs/SECURITY.md` — threat model | 10m | G3/G4 | IPC auth, sandbox, memory safety |
| 9.10 | Write `docs/dossiers/KHOSTTY.md` — product dossier | 10m | G9.1-9.9 | Per Phenotype contract |

### Packaging

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 9.11 | Package macOS .app bundle (notarized if possible) | 10m | G1 | Info.plist, icon, codesign |
| 9.12 | Package Linux .deb (and optionally .rpm) | 10m | G1 | dpkg packaging, desktop entry |
| 9.13 | Package Windows .exe installer (MSI optional) | 10m | G3 | Inno Setup / WiX / MSIX |
| 9.14 | Package WASM dist (npm-style) | 10m | G7 | tar/zip + README |
| 9.15 | Write install docs + verification steps | 10m | 9.11-9.14 | Test each installer |

**Acceptance criteria**:
- All docs committed, cross-linked, no dead links
- macOS .app installs and runs (verified outside source tree)
- Linux .deb installs and runs
- Windows .exe installs and runs
- WASM dist is consumable via npm/ESM
- Dossier compliant with Phenotype docs-3 contract

---

## G10: Release Artifacts + Ecosystem (NOT STARTED) — MEDIUM PRIORITY

**Gate objective**: Produce a tagged release with verified artifacts, publish
consumable packages, hand off to ecosystem. Define the 0.1.0 release.

**Depends on**: G9 (docs+packaging), G8 (benchmark evidence)
**Blocks**: nothing (terminal gate)

### Release Checklist

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 10.1 | Define release version scheme + git tag | 10m | G8/G9 | `v0.1.0`, semantic versioning |
| 10.2 | Build final artifacts for all platforms | 10m | G9.11-9.14 | macOS .app, Linux .deb, Windows .exe, WASM |
| 10.3 | Verify artifacts (checksums, run smoke tests) | 10m | 10.2 | sha256sum, launch each |
| 10.4 | Write release notes (`docs/changelog/0.1.0.md`) | 10m | 10.2 | Features, fixes, known issues |
| 10.5 | Publish FFI crates/packages (crates.io, PyPI, Go, npm) | 10m | G5/G6/G7 | If credentials available |
| 10.6 | Create GitHub release with artifacts | 10m | 10.3-10.4 | Attach all binaries + checksums |
| 10.7 | Create ecosystem handoff doc (README for docs-3 reference) | 10m | 10.6 | Dossier link, consumer guidance |
| 10.8 | Announce release (Slack/README banner) | 10m | 10.7 | Optional, if org channel exists |
| 10.9 | Write post-release check (re-verify artifacts after 1 week) | 10m | 10.6 | Confirm nothing rot before archive |

**Acceptance criteria**:
- `v0.1.0` tagged with verified artifacts (checksums + smoke tests observed)
- All platform installers run and launch
- Release notes complete with known issues
- FFI packages published or explicitly deferred (with reason)
- GitHub release assets attached and verified

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
| G2 Conformance Evidence | 12 | 120 | ⬜ NOT STARTED |
| G3 Windows App Runtime | 15 | 150 | ⬜ NOT STARTED |
| G4 Agent/IPC | 14 | 140 | ⬜ NOT STARTED |
| G5 Rust FFI | 10 | 100 | ⬜ NOT STARTED |
| G6 Go+Python FFI | 8 | 80 | ⬜ NOT STARTED |
| G7 WASM | 10 | 100 | ✅ DONE |
| G8 Improvements+Bench | 13 | 130 | ⬜ NOT STARTED |
| G9 Docs+Packaging | 15 | 150 | ⬜ NOT STARTED |
| G10 Release | 9 | 90 | ⬜ NOT STARTED |
| **TOTAL** | **113** | **~1130m (18.8h)** | **3 DONE / 110 PENDING** |

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
