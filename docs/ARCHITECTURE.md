# Khostty Architecture

**Observed:** 2026-09-17 · **Source of truth:** repository files, not this document.
Every path below is real; every status label is dated and honest.

Khostty is the Phenotype fork of upstream Ghostty. It keeps the upstream terminal
experience and adds a scoped delta: a Windows application runtime, an agent-facing
IPC surface, polyglot FFI wrappers, and a WASM distribution. The architecture is
therefore **upstream core plus a small set of named extension points** — not a
rewrite.

Status vocabulary used throughout `docs/`:

| Label | Meaning |
|---|---|
| **DONE** | Merged, built, and observed passing with the date recorded |
| **IN PROGRESS** | Code exists and compiles; the gate's acceptance criteria are not all met |
| **SCAFFOLD** | Files and interfaces exist; every operation returns `error.Unimplemented` |
| **NOT STARTED** | No implementation in the tree |
| **UNKNOWN** | Not observed in this session; do not infer |

---

## 1. Layer stack

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Consumers                                                               │
│  CLI (+new-window, +list-fonts, …)   Agents (IPC)   Embedders (C/Rust/Go/ │
│                     src/cli/                        Python/JS/WASM)      │
└───────┬──────────────────────────┬────────────────────────┬──────────────┘
        │                          │                        │
        │ (Zig, in-process)        │ (JSON over socket or   │ (FFI)
        │                          │  named pipe)           │
        ▼                          ▼                        ▼
┌───────────────────┐   ┌──────────────────────┐   ┌───────────────────────┐
│  AppRT layer      │   │  IPC surface         │   │  Polyglot wrappers    │
│  src/apprt.zig    │   │  src/apprt/ipc.zig   │   │  khostty-vt/  (Rust)  │
│  comptime runtime │   │  (upstream actions)  │   │  wasm/js/     (JS/TS) │
│  switch:          │   │  src/apprt/windows/  │   │  include/ghostty/ (C) │
│  none|gtk|        │   │  ipc.zig (SCAFFOLD)  │   │                       │
│  embedded|browser │   └──────────┬───────────┘   └───────────┬───────────┘
└─────────┬─────────┘              │                           │
          │                        │                           │
          ▼                        ▼                           ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  Terminal core            src/terminal/                                  │
│  Parser.zig · Screen.zig · Terminal.zig · PageList.zig · Selection.zig    │
│  csi.zig · osc/ · apc/ · dcs.zig · sgr.zig · kitty/ · snapshot/ · search/ │
│  → scrollback-aware VT state machine, no I/O, no platform calls           │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ exported as a C ABI
                                ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  libghostty-vt                include/ghostty/vt.h                       │
│  Umbrella header including 34 module headers · 203 GHOSTTY_API functions │
│  Built as: libghostty-vt.a · libghostty-vt.0.1.0.dylib · .xcframework ·  │
│            ghostty-vt.wasm (wasm32-freestanding)                        │
└──────────────────────────────────────────────────────────────────────────┘
```

The important structural property: **the terminal core has no platform
dependency**. Everything platform-shaped (windows, input, clipboard, fonts) lives
behind the AppRT interface or behind the C ABI boundary. That is what makes the
same parser run in a native macOS app, a GTK4 app, a browser, and a Rust agent
tool.

---

## 2. Application runtime (AppRT) abstraction

`src/apprt.zig` is the compile-time indirection that lets one terminal core serve
several hosts. Exactly one runtime is selected per build:

```zig
// src/apprt.zig
pub const runtime = switch (build_config.artifact) {
    .exe => switch (build_config.app_runtime) {
        .none => none,
        .gtk  => gtk,
    },
    .lib        => embedded,   // macOS AppKit / Swift host
    .wasm_module => browser,
};
```

| Runtime | File | Platforms | Status |
|---|---|---|---|
| `embedded` | `src/apprt/embedded.zig` | macOS | DONE (upstream) |
| `gtk` | `src/apprt/gtk.zig` + `src/apprt/gtk/` | Linux, FreeBSD | DONE (upstream) |
| `browser` | `src/apprt/browser.zig` | wasm32 | DONE (upstream) |
| `none` | `src/apprt/none.zig` | headless | DONE (upstream) |
| `ipc` | `src/apprt/ipc.zig` | cross-platform | DONE, but narrow: 3 actions only |
| **`windows`** | **`src/apprt/windows/`** | **Windows** | **SCAFFOLD — not wired into `src/apprt.zig`** |

`src/apprt/runtime.zig` defines the `Runtime` enum and its default:

```zig
.linux, .freebsd => .gtk,
else             => .none,   // lib-only; the macOS app is built by Xcode
```

### Windows runtime (Khostty delta, gate G3)

`src/apprt/windows/` is an isolated scaffold. It is **not** reachable from
`src/apprt.zig`'s runtime switch today, so no build currently compiles it as a
runtime.

| File | Contents | Status |
|---|---|---|
| `mod.zig` | Module root: `App`, `Window`, `Surface`, `resourcesDir` | SCAFFOLD |
| `App.zig` | `init` / `registerWindowClass` / `run` / `terminate` | SCAFFOLD — all return `error.Unimplemented` |
| `Window.zig` | HWND handle type | SCAFFOLD |
| `surface.zig` | HWND surface; `WM_SIZE`, `WM_PAINT`, `WM_ERASEBKGND`, `WM_CLOSE`, `WM_DESTROY` routing | SCAFFOLD — messages routed, renderer delegated to a stub |
| `renderer.zig` | Renderer adapter (`init`/`resize`/`renderFrame`/`invalidate`) | SCAFFOLD — `error.Unimplemented` |
| `win32api.zig` | Win32 type aliases and `user32`/`kernel32`/`dwmapi` declarations | SCAFFOLD |
| `ipc.zig` | Named-pipe server/client over `\\.\pipe\khostty-{pid}` | SCAFFOLD — `error.Unimplemented` |

> **Known defect (observed 2026-09-17):** `src/apprt/windows/mod.zig` imports
> `"Surface.zig"`, but the tracked file is `surface.zig` (lowercase). The import
> only resolves on a case-insensitive filesystem. Any build on Linux or CI with a
> case-sensitive checkout will fail if and when `mod.zig` is pulled into the
> module graph. Recorded here rather than fixed, because G9 is a documentation
> gate.

---

## 3. Terminal core

`src/terminal/` is upstream Ghostty's VT engine. Khostty does not modify it; that
constraint is what keeps upstream merges cheap.

| Concern | Files |
|---|---|
| Parser / state machine | `Parser.zig`, `parse_table.zig`, `stream.zig`, `stream_terminal.zig` |
| Screen and scrollback | `Screen.zig`, `ScreenSet.zig`, `PageList.zig`, `page.zig` |
| Escape dispatch | `csi.zig`, `osc.zig` + `osc/`, `apc.zig` + `apc/`, `dcs.zig`, `sgr.zig` |
| Cursor / modes / focus | `cursor.zig`, `modes.zig`, `focus.zig` |
| Selection | `Selection.zig`, `SelectionGesture.zig`, `selection_codepoints.zig` |
| Search | `search.zig` + `search/` |
| Snapshots | `snapshot/` |
| Kitty graphics | `kitty.zig` + `kitty/` |
| Text formatting | `formatter.zig` |
| Shared data structures | `PageList.zig`, `StringMap.zig`, `ref_counted_set.zig` |

Two sibling libraries ship from the same core:

- **`src/lib_vt.zig`** — the `libghostty-vt` build target. This is the artifact
  other languages consume.
- **`src/lib/`** — the fuller `libghostty` surface used by the macOS embedded
  runtime.

---

## 4. C ABI boundary

`include/ghostty/vt.h` is the umbrella header. It includes **30 module
headers** (34 `.h` files ship under `include/ghostty/`; `key.h` and `mouse.h`
pull in their `event.h` / `encoder.h` sub-headers) and declares **203
`GHOSTTY_API` functions**. The Rust bindings cover 198 of them, across 179 types
and 779 constants.

```c
#include <ghostty/vt.h>
```

Representative groups (see `include/ghostty/vt/`):

| Group | Header | Example entry points |
|---|---|---|
| Terminal | `terminal.h` | `ghostty_terminal_new`, `_free`, `_reset`, `_resize`, `_set`, `_vt_write`, `_vt_write_until_ground` |
| Snapshot | `snapshot.h` | encode / decoder lifecycle |
| Render state | `render.h` | update + row iteration |
| Formatter | `formatter.h` | terminal → plain text / VT / HTML |
| Search | `search.h` | `new`/`feed`/`run`/`get` |
| OSC parser | `osc.h` | standalone OSC command parsing |
| SGR parser | `sgr.h` | standalone SGR attribute parsing |
| Key / mouse / focus encoding | `key/encoder.h`, `mouse/encoder.h`, `focus.h` | event → escape sequence |
| Selection | `selection.h` | gesture events, word/line/all selection |
| Paste | `paste.h` | safety check + encoding |
| Kitty graphics | `kitty_graphics.h` | image + placement iteration |
| Color | `color.h` | RGB, X11 names, palette generation |
| Grid refs | `grid_ref.h`, `grid_ref_tracked.h` | stable cell/row handles |
| Unicode | `unicode.h` | codepoint and grapheme width |
| Types / allocator / IO / wasm / sys | `types.h`, `allocator.h`, `io.h`, `wasm.h`, `sys.h` | ABI manifest, `alloc`/`free`, reader/writer, host callbacks |

`ghostty_type_json()` returns a JSON manifest of the library's own C ABI for the
current target (pointer width, `size_t` width, endianness, maximum alignment, and
every public type's size, alignment, field offsets, and enum values). Both the
WASM bindings and the Rust ABI test consume it, so no language hardcodes a
target-dependent number.

> The header itself carries this warning, reproduced verbatim because it is the
> current contract: *"This is an incomplete, work-in-progress API. It is not yet
> stable and is definitely going to change."* Consumers must pin a revision.

---

## 5. Polyglot FFI

```
khostty-vt/                     Rust (gate G5, IN PROGRESS)
  build.rs                      locate + link libghostty-vt, optional bindgen
  src/ffi.rs                    198 functions, 179 types, 779 constants (generated)
  src/error.rs                  GhosttyResult → GhosttyError
  src/sys.rs                    allocator integration, owned buffers, 2-pass encode
  src/terminal/                 safe RAII Terminal (mod/query/set/types)
  src/color.rs, src/style.rs    typed color and style values
  tests/terminal.rs             integration tests against the real library
  tests/abi_layout.rs           ABI layout assertions vs the type manifest

wasm/                           JS/TS over wasm32-freestanding (gate G7, IN PROGRESS)
  build.sh                      pinned, verified wasm32 build
  khostty-vt.wasm               artifact (813,670 bytes, sha256 08ac8ed8…)
  js/index.js                   loader + minimal bindings
  js/api.js                     Terminal, Snapshot, Search, openTerminal
  js/*.js, js/*.d.ts            one module, one declaration file
  include/ghostty-vt.h          consolidated self-contained C header
  test/                         runtime smoke, ABI export set, type-level tests
```

Design rule from the WBS, honoured by both: **wrap, do not reimplement.** No
language reimplements parser logic; each calls the same C entry points. The WASM
module is the same parser the desktop app runs, so the conformance corpus
describes its behaviour too.

---

## 6. IPC surface

Two separate things share the name "IPC":

**1. Upstream IPC — `src/apprt/ipc.zig` (252 lines, DONE but narrow).**
A typed action channel with only three actions:

```zig
pub const Action = union(enum) {
    new_window: NewWindow,          // optional config overrides
    new_tab: NewTab,                // target surface_id + overrides
    toggle_quick_terminal: void,
};
```

`Target` is either `class` (a named application instance) or `detect`. The CLI
exposes these as `+new-window`, `+new-tab`, `+toggle-quick-terminal`. There is no
pane creation, no state query, and no event stream.

**2. Khostty agent IPC — gate G4, NOT STARTED.**
The WBS specifies `src/apprt/ipc/` (`protocol.zig`, `server.zig`, `handler.zig`,
`pane.zig`, `state.zig`, `events.zig`, `auth.zig`) with a JSON command/response
protocol. That directory does not exist yet. Only the Windows transport stub
exists today, and it returns `error.Unimplemented`.

The drafted protocol (`pane.create`, `pane.write`, `pane.state`, `pane.list`,
plus async events such as `title_change`) is reproduced and clearly marked as a
draft in [AGENT.md](AGENT.md). Do not build against it yet.

---

## 7. CLI

`src/cli/ghostty.zig` defines the command set. Commands are invoked as
`khostty +<action>`.

| Command | Purpose | Depends on |
|---|---|---|
| `+version`, `--version` | Print version | — |
| `+help` | CLI or config help | — |
| `+list-fonts`, `+list-keybinds`, `+list-themes`, `+list-colors`, `+list-actions` | Introspection | config / platform |
| `+show-config`, `+explain-config`, `+validate-config`, `+edit-config` | Config tooling | config |
| `+show-face` | Report which font face serves a codepoint | font backend |
| `+ssh`, `+ssh-cache` | Remote terminfo integration | terminfo |
| `+crash-report` | Inspect crash reports | crash handler |
| `+new-window`, `+new-tab`, `+toggle-quick-terminal` | Drive a running instance | `src/apprt/ipc.zig` |
| `+boo` | Easter egg | — |

---

## 8. Build and artifact graph

`build.zig` composes artifacts from `src/build/`:

| Artifact | Selected by | Output |
|---|---|---|
| `libghostty-vt` shared | default for lib targets | `libghostty-vt.0.1.0.dylib` / `.so` |
| `libghostty-vt` static | `-Demit-lib-vt` | `libghostty-vt.a` |
| xcframework | `-Demit-xcframework` (Apple only) | macOS + iOS slices |
| WASM module | `-Dtarget=wasm32-freestanding` | `ghostty-vt.wasm` |
| macOS app | `-Demit-macos-app` | Xcode-driven `.app` |
| Docs / terminfo / themes / webdata | `-Demit-docs`, `-Demit-terminfo`, `-Demit-themes`, `-Demit-webdata` | `zig-out/share/` |
| Bench | `-Demit-bench` | bench executables |

Gate G8 (benchmarks) has **no** `bench/` directory in the tree as of 2026-09-17.
`-Demit-bench` selects upstream's bench tooling; it is not evidence of the G8
deliverable.

See [BUILD.md](BUILD.md) for commands and prerequisites.

---

## 9. Fork surface discipline

Khostty additions are confined to named locations. Everything else is upstream
and should stay upstream-mergeable.

| Kind | Location | Status |
|---|---|---|
| Windows runtime | `src/apprt/windows/` | SCAFFOLD (G3) |
| Agent IPC protocol | `src/apprt/ipc/` *(planned)* | NOT STARTED (G4) |
| Rust crate | `khostty-vt/` | IN PROGRESS (G5) |
| WASM package | `wasm/` | IN PROGRESS (G7) |
| Conformance corpus | `conformance/` | DONE (G2) |
| Benchmark harness | `bench/` *(planned)* | NOT STARTED (G8) |
| Docs | `docs/` | IN PROGRESS (G9) |

Explicitly **not** modified: `src/terminal/`, `src/renderer/`, `src/font/`,
`src/config/`. Keeping that boundary is the whole point of the fork.

---

## See also

- [API.md](API.md) — the three public surfaces in reference form
- [AGENT.md](AGENT.md) — driving Khostty from an agent
- [PLATFORMS.md](PLATFORMS.md) — honest support matrix per gate
- [BUILD.md](BUILD.md) — build from source
- [TESTING.md](TESTING.md) — conformance and gate structure
- [FORK.md](FORK.md) — what the fork adds
- [SECURITY.md](SECURITY.md) — trust boundaries
- [GLOSSARY.md](GLOSSARY.md) — terms
- Deep WBS: [`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](sessions/20260916-fork-assessment/02_DEEP_WBS.md)
