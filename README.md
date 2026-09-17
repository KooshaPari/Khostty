# Khostty

**Working name:** `phenotype-khostty`
**Assessment snapshot:** 2026-09-16
**Scope owner:** Terminal runtime for Phenotype Fabric surfaces and embedded terminal consumers
**Upstream:** [`ghostty-org/ghostty`](https://github.com/ghostty-org/ghostty)

> Khostty is the Phenotype fork of Ghostty. It preserves the upstream terminal experience, validates the embeddable VT engine, and defines a focused delta for Windows, agent control, and polyglot consumers.

---

<!-- LOGO -->
<p align="center">
  <img src="https://github.com/user-attachments/assets/fe853809-ba8b-400b-83ab-a9a0da25be8a" alt="Ghostty logo" width="128">
</p>

<p align="center">
  <a href="#status">Status</a> · <a href="#platform-support">Platforms</a> · <a href="#quickstart">Quickstart</a> · <a href="#architecture">Architecture</a> · <a href="#agent-ipc-surface">Agent/IPC</a> · <a href="#polyglot-ffi">Polyglot FFI</a> · <a href="#conformance">Conformance</a> · <a href="#development">Development</a> · <a href="#contributing">Contributing</a> · <a href="#license">License</a>
</p>

---

[![AI slop inside](https://sladge.net/badge.svg)](https://sladge.net) [![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/KooshaPari/ghostty/total)](https://github.com/KooshaPari/ghostty/releases)

## What Khostty Is

Khostty is the **Phenotype-flavored fork of [Ghostty](https://github.com/ghostty-org/ghostty)**, the fast, native, feature-rich terminal emulator written in Zig by Mitchell Hashimoto and contributors.

Ghostty ships `libghostty-vt`, a standalone C library with 12,285 lines of headers across 32+ files, 30 examples in C, Zig, and WASM, fuzz tests, benchmarks, and a complete terminal emulator. The engine covers parsing, screen state, scrollback, cursor handling, styles, selection, search, render state, snapshots, Kitty graphics, SGR, OSC, and key and mouse encoding.

Khostty does not rebuild that engine or maintain a separate terminal user experience. It tracks upstream and focuses the fork delta on capabilities that upstream does not provide:

| Value area | Upstream Ghostty | Khostty direction | Status |
|---|---|---|---|
| Embedding | `libghostty-vt` C ABI and examples | Prove the embedding path end to end with Khostty-specific tooling | Roadmap; validation continues in G1/G2 |
| Windows | Native macOS AppKit and Linux/BSD GTK runtimes; no Windows app runtime | Native Win32 and DirectWrite application in `src/apprt/windows/` | **NOT STARTED, G3** |
| Agent/IPC | `ipc.zig` supports `new_window`, `new_tab`, and `toggle_quick_terminal` | JSON command and event protocol for panes, state, and automation | **NOT STARTED, G4** |
| Polyglot FFI | C and Zig APIs, with examples for other languages | Safe Rust, Go, Python, and hardened WASM wrappers | **NOT STARTED, G5-G7** |
| Phenotype integration | General-purpose terminal and embeddable VT engine | Reusable terminal surfaces in the Phenotype Fabric graph | Planned |

If you want a finished desktop terminal today, use upstream Ghostty. Khostty is the integration and extension path for embedding a terminal, driving it from an agent, or bringing the upstream engine to Windows and additional language ecosystems.

## Status

The authoritative task decomposition is [`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md). The assessment records G0 and G1 as complete. The remaining Khostty capability gates are not started.

| Gate | Scope | Tasks | Estimate | Status |
|---|---|---:|---:|---|
| **G0** | Fork Hygiene | 4 | 40m | **DONE** |
| **G1** | Native Build Validation | 3 | 30m | **DONE** |
| **G2** | Conformance Evidence | 12 | 120m | **NOT STARTED** |
| **G3** | Windows App Runtime | 15 | 150m | **NOT STARTED** |
| **G4** | Agent/IPC Surface Expansion | 14 | 140m | **NOT STARTED** |
| **G5** | Polyglot FFI — Rust | 10 | 100m | **NOT STARTED** |
| **G6** | Polyglot FFI: Go and Python | 8 | 80m | **NOT STARTED** |
| **G7** | WASM Cross-Compilation | 10 | 100m | **NOT STARTED** |
| **G8** | Khostty-Specific Improvements | 10 | 100m | **NOT STARTED** |
| **G9** | Documentation and Packaging | 8 | 80m | **NOT STARTED** |
| **G10** | Release Artifacts | 6 | 60m | **NOT STARTED** |

The WBS records 100 tasks and approximately 16.7 hours of planned work, with 70 minutes completed at the assessment snapshot. Status labels in this README follow that WBS and are not claims of shipped functionality.

## Platform Support

| Platform | Status | Runtime or artifact |
|---|---|---|
| **macOS** | **DONE** | Upstream Swift/AppKit application runtime; G1 build validation |
| **Linux/BSD** | **DONE** | Upstream GTK application runtime; G1 build validation |
| **Windows** | **NOT STARTED** | Planned Win32/DirectWrite runtime in `src/apprt/windows/` under G3 |
| **WASM** | **NOT STARTED** | Planned hardened WASM build and polyglot export under G7 |

G1 separately verified a 795KB `ghostty-vt.wasm` cross-compile artifact with 40+ function signatures. That evidence is not a claim that the Khostty-hardened WASM product, typed JavaScript API, or package distribution is complete.

## Quickstart

### Prerequisites

- Zig **0.16.0 or newer**, as declared by [`build.zig.zon`](build.zig.zon)
- A supported native platform for the current upstream runtimes
- The upstream development dependencies documented in [`HACKING.md`](HACKING.md)

### Build From Source

```bash
git clone https://github.com/1jehuang/khostty.git
cd khostty

# Build the repository with Zig
zig build
```

### Validate Formatting and Tests

```bash
# Check formatting
zig fmt --check src/ build.zig

# Run the Zig test suite
zig build test

# Build and run the libghostty-vt conformance target when G2 is active
zig build test-lib-vt
```

`zig build` and a passing test command establish build behavior only. They do not close G2. G2 requires the complete conformance corpus and fuzz evidence described below.

### Build the VT Library

The repository exposes `libghostty-vt` through the Zig build system. Use the build options documented by the project build help when producing a platform artifact:

```bash
zig build --help
```

Do not treat a library artifact as a completed Khostty binding. The Rust, Go, Python, and hardened WASM packages remain **NOT STARTED**.

## Architecture

Khostty keeps the upstream engine intact and places the planned fork surface above it.

```text
Khostty
├── apprt: platform-specific application runtimes
│   ├── embedded.zig       macOS AppKit runtime, upstream
│   ├── gtk.zig            Linux/BSD GTK runtime, upstream
│   ├── windows/            Win32/DirectWrite runtime, planned G3
│   ├── khostty/            Khostty-specific runtime, planned
│   └── ipc/                JSON IPC server, planned G4
├── terminal: headless upstream engine
│   ├── parser, screen, scrollback, cursor, selection, search
│   ├── render state, snapshots, Kitty graphics, SGR, OSC
│   └── key and mouse encoding
├── libghostty-vt: C ABI exported from the upstream engine
├── renderer and surfaces
│   ├── Metal and OpenGL for upstream platforms
│   └── DirectWrite planned for Windows
└── planned polyglot layer
    ├── Rust: khostty-vt
    ├── Go: khostty/vt
    ├── Python: khostty
    └── hardened WASM package
```

### Layer Responsibilities

1. **`libghostty-vt`** is the stable C ABI and the source of terminal correctness. Khostty wraps it rather than reimplementing parser behavior in another language.
2. **`apprt`** owns platform shells, input, windowing, rendering integration, and the eventual IPC server.
3. **The Agent/IPC layer** will translate JSON commands into terminal actions and expose machine-readable state and events.
4. **The polyglot layer** will provide safe language-specific ownership, error, and lifetime semantics around the C ABI.
5. **Phenotype Fabric** can embed the resulting terminal surface without depending on a particular GUI framework.

The planned minimal fork surface is `src/apprt/khostty/` and `src/apprt/windows/`. Upstream `src/terminal/` and `src/renderer/` remain the source of truth.

## Agent/IPC Surface

> **Status: NOT STARTED, G4.** The protocol below is a draft from the Deep WBS. It is a usage preview, not an implemented API.

The planned IPC layer expands upstream's three commands into a versioned JSON command, response, and event protocol. The architecture calls for a Unix domain socket on Unix-like platforms and a Windows named pipe on Windows, with token-based authentication.

```json
// Agent to Khostty: create a pane
{"cmd":"pane.create","opts":{"split":"vertical","cwd":"/tmp"}}

// Khostty to Agent: response
{"ok":true,"data":{"pane_id":"p-3","pid":12345}}

// Agent to Khostty: write VT sequences to the pane
{"cmd":"pane.write","pane_id":"p-3","data":"ls -la\n"}

// Agent to Khostty: query machine-readable state
{"cmd":"pane.state","pane_id":"p-3"}

// Khostty to Agent: state snapshot
{"ok":true,"data":{"cursor":{"row":12,"col":45},"title":"bash","size":{"cols":120,"rows":40}}}

// Agent to Khostty: list all panes
{"cmd":"pane.list"}

// Khostty to Agent: pane list
{"ok":true,"data":[{"id":"p-3","title":"bash","pid":12345},{"id":"p-7","title":"vim","pid":12389}]}

// Khostty to Agent: asynchronous event
{"event":"title_change","pane_id":"p-3","data":{"title":"~/projects/khostty"}}
```

The planned command set includes:

| Command or event | Planned purpose |
|---|---|
| `pane.create` | Create a pane with split and working-directory options |
| `pane.close` | Close a pane by identifier |
| `pane.focus` | Focus a pane by identifier |
| `pane.list` | List live panes |
| `pane.write` | Write a VT byte stream to a pane |
| `pane.state` | Return cursor, title, size, and scrollback metadata |
| `pane.search` | Search scrollback text |
| `pane.resize` | Resize a pane grid |
| `surface.list` and `window.list` | Enumerate surfaces and windows |
| `title_change`, `pane_exit`, `resize`, `bell`, `osc_*` | Asynchronous events |

G4 acceptance requires authenticated commands, pane lifecycle operations, state and scrollback queries, concurrent operation safety, protocol documentation, and examples. None of those acceptance criteria are complete yet.

## Polyglot FFI

> **Status: NOT STARTED, G5-G7.** The following table distinguishes the upstream ABI and examples from Khostty packages that still need to be built.

| Language | Status | Planned package | Purpose |
|---|---|---|---|
| **Rust** | **NOT STARTED, G5** | `khostty-vt` | Safe Rust wrapper with RAII handles, typed errors, and integration tests |
| **Go** | **NOT STARTED, G6** | `khostty/vt` | cgo-based idiomatic Go wrapper with context and error handling |
| **Python** | **NOT STARTED, G6** | `khostty` | cffi-based Python package for terminal automation and scripting |
| **WASM** | **NOT STARTED, G7** | Hardened WASM package and typed JavaScript API | Browser and sandbox consumption of the VT engine |

The upstream C ABI and existing examples remain the baseline that these packages wrap. The Rust design calls for raw bindings isolated behind a documented unsafe boundary, safe `Terminal`, `Snapshot`, `RenderState`, `Search`, `KeyEncoder`, and `MouseEncoder` types, and an explicit `GhosttyError` result type. Go and Python follow the same wrap-over-handroll rule.

## Conformance

> **Status: NOT STARTED, G2.** This is the critical gate before Windows, IPC, FFI, and feature work.

G2 must prove that Khostty has no unacceptable terminal correctness regression. Build success is not enough. The gate covers the upstream Zig tests, the fuzz corpus, and the complete set of upstream examples.

Acceptance criteria from the WBS:

- All 30 upstream examples build and run without crashing.
- The fuzz corpus in `test/fuzz-libghostty/` produces zero new crashes.
- A pass/fail matrix is committed to the session documentation with observed evidence.
- Failures include upstream issue references and a documented resolution path.

The conformance target includes parsing and streaming, SGR, key and mouse encoding, Kitty graphics, snapshots, render state, search, formatting, grid access, compression, colors, effects, selection, static and CMake builds, WASM examples, Zig, C++, Swift, and Python examples.

## Development

### Repository Pointers

- [`HACKING.md`](HACKING.md): inherited upstream development workflow.
- [`CONTRIBUTING.md`](CONTRIBUTING.md): contribution and review conventions.
- [`build.zig`](build.zig): Zig build entrypoint and test targets.
- [`build.zig.zon`](build.zig.zon): package metadata and minimum Zig version.
- [`docs/sessions/20260916-fork-assessment/`](docs/sessions/20260916-fork-assessment/): assessment history and the authoritative Deep WBS.
- [`docs/GLOBAL_HANDBOOK.md`](docs/GLOBAL_HANDBOOK.md): Phenotype platform handbook.

### Recommended Workflow

1. Read the relevant gate in the Deep WBS before changing code.
2. Run formatting and the narrowest relevant build or test target.
3. Keep upstream engine changes separate from Khostty-specific apprt, IPC, and binding work.
4. Add conformance evidence for correctness-sensitive changes.
5. Update the README, API examples, and WBS status only after the evidence exists.

### Sync With Upstream

```bash
git fetch upstream
git merge upstream/main
zig build
zig build test
zig fmt --check src/ build.zig
```

The assessment snapshot records Khostty as 14 commits ahead and 0 behind upstream. Treat that as historical assessment evidence and verify the current remote state before a release.

## Contributing

Issues, bug reports, and pull requests that change upstream code in `src/terminal/`, `src/renderer/`, or the upstream `apprt` implementations should go to [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) first. This keeps the shared engine aligned with upstream.

Khostty-specific contributions are welcome in the planned areas:

- `src/apprt/windows/`
- `src/apprt/khostty/`
- `src/apprt/ipc/`
- `bindings/`
- `crates/`
- WASM packaging and examples

Before opening a pull request:

1. Run `zig fmt --check src/ build.zig`.
2. Run the relevant `zig build test` target.
3. For IPC work, add protocol examples and authentication tests.
4. For FFI work, add language-specific ownership, error, and integration tests.
5. Record conformance evidence when terminal behavior changes.
6. Keep commits focused and include the repository's transaction-ledger metadata when applicable.

## Links

- **Upstream Ghostty:** <https://github.com/ghostty-org/ghostty>
- **Upstream documentation:** <https://ghostty.org/docs>
- **Upstream download:** <https://ghostty.org/download>
- **Khostty assessment history:** [`docs/sessions/20260916-fork-assessment/`](docs/sessions/20260916-fork-assessment/)
- **Deep WBS:** [`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md)
- **Phenotype handbook:** [`docs/GLOBAL_HANDBOOK.md`](docs/GLOBAL_HANDBOOK.md)

## License

Khostty is distributed under the **MIT License**, the same license as upstream Ghostty. The complete repository license is in [`LICENSE`](LICENSE).

```text
MIT License

Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Acknowledgments

Khostty is built on [Ghostty](https://github.com/ghostty-org/ghostty) by **Mitchell Hashimoto** and the Ghostty contributors. The fork exists to extend Ghostty's embeddable terminal engine for Phenotype use cases while keeping the upstream parser, renderer, and terminal behavior as the source of truth.

Thanks to the Phenotype team and community contributors for the integration requirements, assessment work, and roadmap feedback.

---

<p align="center">
  <sub>Built on Ghostty. Maintained for the Phenotype platform.</sub>
</p>
