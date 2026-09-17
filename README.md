<!-- LOGO -->
<p align="center">
  <img src="https://github.com/user-attachments/assets/fe853809-ba8b-400b-83ab-a9a0da25be8a" alt="Ghostty logo" width="128">
</p>

<h1 align="center">Khostty</h1>

<p align="center">
  <strong>Phenotype fork of Ghostty, focused on Windows support, an agent-first IPC surface, and polyglot FFI for the modern terminal.</strong>
  <br />
  Native GUI terminal on macOS, Linux, and (soon) Windows — plus a first-class embeddable VT engine (<code>libghostty-vt</code>) wrapped for Rust, Go, Python, and WASM.
</p>

<p align="center">
  <a href="#status">Status</a> · <a href="#platform-support">Platforms</a> · <a href="#quickstart">Quickstart</a> · <a href="#architecture">Architecture</a> · <a href="#agent-ipc-surface">Agent/IPC</a> · <a href="#polyglot-ffi">Polyglot FFI</a> · <a href="#conformance">Conformance</a> · <a href="#contributing">Contributing</a> · <a href="#license">License</a>
</p>

---

## What Khostty Is

Khostty is the **Phenotype-flavored fork of [Ghostty](https://github.com/ghostty-org/ghostty)**, the fast, native, feature-rich terminal emulator written in Zig by Mitchell Hashimoto and contributors.

We do **not** maintain a divergent terminal UX. Khostty tracks upstream Ghostty and adds a focused, well-scoped delta on top. The fork exists so we can:

1. **Run the world's best terminal on Windows** — upstream Ghostty ships a native macOS app (Swift/AppKit) and a Linux/BSD app (GTK), but has **no Windows runtime**. Khostty fills that gap with a native Win32/DirectWrite application.
2. **Expose a machine-friendly IPC surface** — upstream IPC supports `new_window`, `new_tab`, and `toggle_quick_terminal` only. Khostty adds a JSON command/event protocol for pane creation, manipulation, content writing, and state query, designed for agents and embedded use.
3. **Wrap `libghostty-vt` for every language that matters** — upstream exposes a C API and a Zig API. Khostty wraps that C API with safe idiomatic bindings for **Rust, Go, Python, and WASM** so agents and tools in any ecosystem can embed a correct terminal.
4. **Embed the terminal in Phenotype Fabric** — the VT engine becomes a reusable surface in the Phenotype Fabric graph alongside windows, routes, and other composable elements.

If you just want a terminal, use upstream [Ghostty](https://ghostty.org/). If you want to embed a terminal, drive one from an agent, or run one on Windows, Khostty is for you.

---

## Status

Khostty is on the critical path of the Phenotype platform. The fork delta is well-defined, validated end-to-end for the native build, and has a sequenced WBS for everything else.

| Gate | Scope | Tasks | Estimate | Status |
|------|-------|-------|----------|--------|
| **G0** | Fork Hygiene (CI replacement, Metal toolchain fix, docs seed) | 4 | 40m | **DONE** |
| **G1** | Native Build Validation (`libghostty-vt` static + dynamic + xcframework, WASM cross-compile, `zig fmt --check`) | 3 | 30m | **DONE** |
| **G2** | Conformance Evidence (run all 30 upstream examples + fuzz corpus) | 12 | 120m | NOT STARTED |
| **G3** | Windows App Runtime (Win32 + DirectWrite + named-pipe IPC) | 15 | 150m | NOT STARTED |
| **G4** | Agent/IPC Surface Expansion (JSON protocol, pane CRUD, state query, events) | 14 | 140m | NOT STARTED |
| **G5** | Polyglot FFI — Rust (`khostty-vt` safe crate) | 10 | 100m | NOT STARTED |
| **G6** | Polyglot FFI — Go + Python | 8 | 80m | NOT STARTED |
| **G7** | WASM Cross-Compilation + FFI export | 10 | 100m | NOT STARTED |
| **G8** | Khostty-specific Improvements + Benchmarks | 10 | 100m | NOT STARTED |
| **G9** | Documentation + Packaging | 8 | 80m | NOT STARTED |
| **G10** | Release Artifacts + Ecosystem Sign-off | 6 | 60m | NOT STARTED |
| | **Total** | **100** | **~1000m (16.7h)** | **70m done** |

**Fork state:** 14 commits ahead of `ghostty-org/ghostty`, 0 behind. Upstream sync runs through the same Zig-aware CI we added in G0.

The full task decomposition lives at [`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md).

---

## Platform Support

| Platform | Status | Runtime | Renderer | Notes |
|----------|--------|---------|----------|-------|
| **macOS** | **DONE** (upstream) | `src/apprt/embedded.zig` (Swift/AppKit) | Metal / OpenGL | Native shell, full UI. Builds and runs today. |
| **Linux / BSD** | **DONE** (upstream) | `src/apprt/gtk.zig` (GTK4) | OpenGL | Native shell, full UI. Builds and runs today. |
| **Windows** | **NOT STARTED** (Khostty G3) | `src/apprt/windows/` (Win32 + DirectWrite) — planned | GDI/DirectX — planned | No upstream Windows runtime. Khostty adds one. |
| **WASM** | Partial (upstream example only) | `libghostty-vt.wasm` (795KB, 40+ signatures) | n/a | Upstream ships a WASM example. G7 hardens + exports for embedding. |

The `libghostty-vt` C library itself — parser, screen, scrollback, cursor, styles, selection, search, render state, snapshots, Kitty graphics, SGR, OSC, key/mouse encoding — is **fully functional on every platform with a C compiler** today. The platform-support matrix above tracks the *GUI shell*, not the embeddable library.

---

## Quickstart

### Prerequisites

- **Zig 0.16.0+** (see `.zig-cache/` or `zig version`)
- A C11-compatible C toolchain (Xcode CLT on macOS, `build-essential` + `pkg-config` on Linux, MSVC on Windows)
- macOS users: Xcode Command Line Tools (`xcode-select --install`)
- Linux users: GTK4 development libraries (`libgtk-4-dev`, `libadwaita-1-dev`)

### Build

```bash
# Build everything (libghostty-vt + apprt targets)
zig build

# Run the macOS GUI shell
zig build run

# Build the embeddable C library only
zig build -Demit-lib-vt=true
```

Outputs land under `zig-out/`:

```
zig-out/
  lib/
    libghostty-vt.a              # static archive
    libghostty-vt.dylib          # shared library (macOS/Linux)
    libghostty-vt.xcframework    # Apple multi-arch bundle
  bin/
    ghostty                       # native GUI shell
```

### Test

```bash
# Run all Zig tests (~200+ files)
zig build test

# Run only the libghostty-vt example tests (the conformance gate)
zig build test-lib-vt

# Build (but do not run) the libghostty-vt examples
zig build test-lib-vt-build

# Validate the JSON C-types schema
zig build test-lib-vt-schema
```

### Format

```bash
zig fmt --check src/ build.zig
```

CI runs `fmt --check` and a debug build on every push. See `.github/workflows/ci.yml`.

---

## Architecture

Khostty inherits Ghostty's clean three-layer architecture and extends only the topmost layer (`apprt`).

```
┌──────────────────────────────────────────────────────────────────────┐
│  apprt (Application Runtime)                                         │
│  ─────────────────────────                                           │
│  Platform-specific GUI shells. This is the ONLY layer Khostty        │
│  diverges from upstream.                                             │
│                                                                      │
│    src/apprt/embedded.zig   — macOS shell (Swift/AppKit)  [upstream] │
│    src/apprt/gtk.zig        — Linux/BSD shell (GTK4)      [upstream] │
│    src/apprt/windows/       — Windows shell (Win32/DW)    [PLANNED]  │
│    src/apprt/khostty/       — Khostty-specific runtime    [PLANNED]  │
│    src/apprt/ipc/           — JSON IPC server (planned)   [PLANNED]  │
└──────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  terminal (Headless Engine)                                          │
│  ─────────────────────────                                           │
│  Cross-platform terminal logic: parser, screen, scrollback, cursor,  │
│  styles, selection, search, render state, snapshots, Kitty graphics, │
│  SGR, OSC, key/mouse encoding. NO GUI dependencies.                  │
│                                                                      │
│  Exposed to the world as libghostty-vt (C ABI).                     │
│  src/terminal/ contains the Zig source and src/terminal/c/ the      │
│  generated C headers (32 files, 12,285 lines).                       │
└──────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  renderer + Surface                                                  │
│  ──────────────────                                                  │
│  Metal/OpenGL/DirectWrite renderers + per-platform surface           │
│  implementations. Unchanged from upstream.                           │
└──────────────────────────────────────────────────────────────────────┘
```

**Design principles:**

- **Wrap, do not handroll.** Every Khostty capability comes from wrapping `libghostty-vt` over FFI, not from reimplementing parser logic in the target language.
- **Agent-first IPC.** Every terminal operation is a JSON-serializable command. Agents can create panes, write content, read screen state, and query metadata without a human at the keyboard.
- **Correctness before features.** Conformance tests (G2) gate all new feature work. No capability merges without passing the conformance corpus.
- **Minimal fork surface.** Khostty-specific code lives in `src/apprt/khostty/` and `src/apprt/windows/`. Upstream core (`src/terminal/`, `src/renderer/`) is untouched.

---

## Agent/IPC Surface

> **Status: NOT STARTED (G4)** — protocol below is a *draft* in the WBS and is **not implemented yet**. We document it here so consumers know what to expect.

Khostty extends Ghostty's IPC from three commands to a full JSON command/event protocol. The shell listens on a Unix domain socket (or a Windows named pipe) and accepts authenticated JSON commands.

```json
// Agent → Khostty: create a pane
{"cmd":"pane.create","opts":{"split":"vertical","cwd":"/tmp"}}

// Khostty → Agent: response
{"ok":true,"data":{"pane_id":"p-3","pid":12345}}

// Agent → Khostty: write VT sequences to the pane
{"cmd":"pane.write","pane_id":"p-3","data":"ls -la\n"}

// Agent → Khostty: query machine-readable state
{"cmd":"pane.state","pane_id":"p-3"}

// Khostty → Agent: state snapshot
{"ok":true,"data":{"cursor":{"row":12,"col":45},"title":"bash","size":{"cols":120,"rows":40}}}

// Agent → Khostty: list all panes
{"cmd":"pane.list"}

// Khostty → Agent: pane list
{"ok":true,"data":[{"id":"p-3","title":"bash","pid":12345},{"id":"p-7","title":"vim","pid":12389}]}

// Khostty → Agent: async event push
{"event":"title_change","pane_id":"p-3","data":{"title":"~/projects/khostty"}}
```

Planned capabilities:

| Command | Description |
|---------|-------------|
| `pane.create` | Create a new pane (vertical/horizontal split, custom cwd) |
| `pane.close` | Close a pane by id |
| `pane.focus` | Focus a pane by id |
| `pane.list` | List all live panes |
| `pane.write` | Write a VT byte stream to a pane |
| `pane.state` | Snapshot cursor, title, size, scrollback range |
| `pane.search` | Search scrollback text |
| `pane.resize` | Resize the pane's grid |
| `surface.list` / `window.list` | Enumerate top-level surfaces and windows |
| events | `title_change`, `pane_exit`, `resize`, `bell`, `osc_*` |

All commands require a token (generated at first launch, stored with 0600 permissions on Unix, DPAPI on Windows). The protocol will be versioned (`protocol_version: 1`) for forward compatibility.

---

## Polyglot FFI

> **Status: NOT STARTED (G5/G6/G7)** — bindings below are *planned*, not shipped. Upstream ships a C header set (32 files, 12,285 lines) and a WASM example; Khostty wraps that for additional languages.

`libghostty-vt` exposes a stable C ABI. Khostty ships first-class safe bindings for every language our agents run in.

| Binding | Status | Crate / Module | Notes |
|---------|--------|----------------|-------|
| **C** (upstream) | DONE | `libghostty-vt.h` (32 headers) | The ABI everything else wraps. |
| **Zig** (upstream) | DONE | `src/terminal/c/` | Native API. |
| **C++** (upstream example) | DONE | `examples/cpp-vt/` | Demonstrates C++ wrapping. |
| **Swift** (upstream example) | DONE | `examples/swift-vt/` | Demonstrates Swift wrapping. |
| **WASM** (upstream example) | DONE | `examples/wasm-vt/`, `zig-out/lib/ghostty-vt.wasm` | 795KB, 40+ function signatures. G7 hardens this. |
| **Rust** (`khostty-vt`) | NOT STARTED (G5, HIGH) | `crates/khostty-vt/` (planned) | Safe wrapper using `bindgen` + newtype + `Result<T, Error>`. |
| **Go** (`khostty/vt`) | NOT STARTED (G6, MEDIUM) | `bindings/go/khostty/` (planned) | `cgo`-based, idiomatic Go errors, context support. |
| **Python** (`khostty`) | NOT STARTED (G6, MEDIUM) | `bindings/python/khostty/` (planned) | `cffi`-based, follows CPython API conventions. |
| **WASM (Khostty-hardened)** | NOT STARTED (G7, HIGH) | `pkg/wasm/` (planned) | Smaller surface, typed JS API, npm package. |

The Rust crate design wraps the C functions 1:1 and adds:

- `Result<T, GhosttyError>` instead of integer error codes
- Newtypes for handles (`TerminalHandle`, `OscHandle`) so they cannot be mixed up
- Lifetime tracking via `PhantomData` where Zig uses pointers
- `Send + Sync` enforcement where upstream's allocator is thread-safe

---

## Conformance

> **Status: NOT STARTED (G2, CRITICAL)** — the gate has 12 sub-tasks and **must pass before Windows/IPC/FFI work begins**.

The fork's correctness bar is: every one of upstream Ghostty's 30 examples builds and runs without crash, plus the upstream fuzz corpus produces zero new crashes.

| Example | Language | What it proves | Status |
|---------|----------|----------------|--------|
| `c-vt` | C | OSC parser works end-to-end | not yet run |
| `c-vt-stream` | C | Streaming incremental parse works | not yet run |
| `c-vt-sgr` | C | SGR attribute handling works | not yet run |
| `c-vt-encode-key` / `c-vt-encode-mouse` / `c-vt-encode-focus` | C | Input encoding round-trips | not yet run |
| `c-vt-paste` | C | Paste safety + bracketed-paste encoding | not yet run |
| `c-vt-snapshot` | C | Full state encode/decode round-trip | not yet run |
| `c-vt-render` | C | Render-state tracking + dirty regions | not yet run |
| `c-vt-search` | C | Scrollback search/find | not yet run |
| `c-vt-formatter` | C | Text/VT/HTML export | not yet run |
| `c-vt-grid-traverse`, `c-vt-grid-ref-tracked` | C | Grid cell access | not yet run |
| `c-vt-compression` | C | Scrollback compression | not yet run |
| `c-vt-colors`, `c-vt-effects` | C | Color + effect parsing | not yet run |
| `c-vt-selection`, `c-vt-selection-gesture` | C | Selection + gestures | not yet run |
| `c-vt-kitty-graphics` | C | Kitty graphics protocol | not yet run |
| `c-vt-build-info` | C | Build-info query | not yet run |
| `c-vt-static`, `c-vt-cmake-static`, `c-vt-cmake-cross` | C | Static + CMake builds | not yet run |
| `wasm-vt`, `wasm-key-encode`, `wasm-sgr` | JS/WASM | WASM surface works | not yet run |
| `zig-vt` | Zig | Zig API works | not yet run |
| `c++-vt` | C++ | C++ wrapping works | not yet run |
| `swift-vt` | Swift | Swift wrapping works | not yet run |
| `python-vt` | Python | Python wrapping works | not yet run |
| `test/fuzz-libghostty/` | fuzz | Fuzz corpus produces zero new crashes | not yet run |

Pass/fail results will be committed as a conformance matrix under `docs/sessions/` once G2 runs.

---

## Repository Layout

```
khostty/
├── src/
│   ├── apprt/                  # Application runtime (the layer we extend)
│   │   ├── embedded.zig        # macOS shell [upstream]
│   │   ├── gtk.zig             # Linux/BSD shell [upstream]
│   │   ├── windows/            # Windows shell [PLANNED, G3]
│   │   ├── khostty/            # Khostty-specific runtime [PLANNED]
│   │   └── ipc/                # JSON IPC server [PLANNED, G4]
│   ├── terminal/               # Headless engine (untouched upstream core)
│   │   ├── c/                  # C headers (generated, 32 files, 12,285 lines)
│   │   ├── Parser.zig
│   │   ├── Screen.zig
│   │   ├── ...
│   └── renderer/               # Metal/OpenGL/DirectWrite renderers
├── pkg/translate-c/            # C translation helper (Zig dependency)
├── examples/                   # 30 upstream C/Zig/WASM/C++/Swift/Python examples
├── test/fuzz-libghostty/       # Fuzz corpus
├── docs/
│   ├── GLOBAL_HANDBOOK.md      # Phenotype platform handbook
│   └── sessions/
│       └── 20260916-fork-assessment/
│           ├── 00_SESSION_OVERVIEW.md
│           ├── 02_DEEP_WBS.md        # full 681-line task decomposition
│           └── ...
├── build.zig                   # Zig build entrypoint
├── build.zig.zon               # Package metadata (name: ghostty, version 1.3.2-dev)
├── HACKING.md                  # Upstream dev workflow (still valid)
├── CONTRIBUTING.md             # Upstream contribution guide (still valid)
├── LICENSE                     # MIT (Ghostty)
└── README.md                   # ← you are here
```

---

## Development

### Day-to-day workflow

The upstream Ghostty development workflow (Zig toolchain, `zig fmt`, `zig build test`) applies unchanged. See [`HACKING.md`](HACKING.md) for the developer guide inherited from upstream.

### Working on Khostty-specific gates

Each gate has a 10-minute-task decomposition in `docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`. The file is the source of truth for what "done" means for each gate and what evidence is required.

**The critical path** (smallest remaining effort, fastest useful outcome, fewest dependencies):

```
G2 (conformance)  →  G3 (Windows runtime)  →  G4 (agent/IPC)  →  G10 (release)
                                  ↓
                          G5 (Rust FFI)  →  G6 (Go/Python FFI)  →  G7 (WASM)
```

G2 must complete first — it proves we have not regressed upstream correctness. Everything else builds on a green conformance suite.

### Sync with upstream

```bash
git fetch upstream
git merge upstream/main        # or use the configured sync workflow
zig build && zig build test    # verify nothing broke
zig fmt --check src/ build.zig # verify formatting
```

We track upstream aggressively. The current fork is **14 commits ahead, 0 behind**.

---

## Contributing

Issues, bug reports, and pull requests that touch **upstream code** (`src/terminal/`, `src/renderer/`, upstream `apprt/`) should go to [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) first. We do not want Khostty to drift from upstream on shared code.

Contributions to Khostty-specific code (`src/apprt/windows/`, `src/apprt/khostty/`, `src/apprt/ipc/`, `bindings/`, `crates/`) are welcome here.

Before opening a PR:

1. Run `zig fmt src/ build.zig` (CI runs `--check`)
2. Run `zig build test` and confirm all tests pass
3. If your change touches the IPC protocol, update the JSON schema and add an example under `examples/`
4. If your change touches the FFI, run the relevant `test-lib-vt-*` target
5. Commit messages follow the [immutable transaction ledger](https://github.com/1jehuang/jcode) convention:
   ```
   feat(apprt/windows): implement DirectWrite renderer
   
   tx-agent:     jcode
   tx-task:      G3.5
   tx-validated: test
   tx-scope:     src/apprt/windows/renderer.zig
   tx-intent:    First-cut DirectWrite text rendering for Khostty Windows shell
   ```

See [`CONTRIBUTING.md`](CONTRIBUTING.md) (inherited from upstream) for general style and review conventions.

---

## Upstream

Khostty is a fork of [**Ghostty**](https://github.com/ghostty-org/ghostty) by **Mitchell Hashimoto** and the Ghostty contributors. Every line of parser, screen, and renderer logic in this repository is upstream work. Khostty adds only the platform-specific shells, IPC layer, and polyglot FFI wrappers needed for our use cases.

- **Upstream:** [github.com/ghostty-org/ghostty](https://github.com/ghostty-org/ghostty)
- **Upstream docs:** [ghostty.org/docs](https://ghostty.org/docs)
- **Upstream download:** [ghostty.org/download](https://ghostty.org/download)
- **Upstream CI:** the upstream project's GitHub Actions

We thank Mitchell and the Ghostty contributors for building the best terminal emulator available and licensing it under MIT so forks like ours can extend it freely.

---

## License

Khostty is licensed under the **MIT License** — the same license as upstream Ghostty.

```
MIT License

Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors
Copyright (c) 2026 Phenotype — Khostty fork contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the above copyright notice and this
permission notice appearing in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND...
```

See [`LICENSE`](LICENSE) for the full text.

---

<p align="center">
  <sub>Built on the shoulders of <a href="https://github.com/ghostty-org/ghostty">Ghostty</a> · Maintained by the <a href="https://github.com/1jehuang/jcode">Phenotype</a> platform team</sub>
</p>
