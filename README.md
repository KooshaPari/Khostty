# Khostty

**Library-first fork of [Ghostty](https://github.com/ghostty-org/ghostty) — the Phenotype-flavored embeddable VT engine + polyglot FFI + agent IPC.**

> Khostty is the Phenotype fork of Ghostty. It ships the upstream terminal VT engine
> as a 0.1.0 library across six binding surfaces (C ABI, Rust, Go, Python, WASM,
> and the macOS / Windows / Linux applications), and adds a typed JSON agent-IPC
> layer for driving a hosted terminal from another program.

---

## Install

Three lines get a developer a working VT parser in any of the three target languages.
The downloads further down install the desktop applications.

```bash
# Rust — published on crates.io
cargo add khostty-vt

# Browser / Node — published on npm
npm install @khostty/libghostty-vt-wasm

# Python — pending PyPI publish (see Status); install from source today
pip install khostty-vt          # once PyPI trusted publisher is registered
# OR, today:
#   git clone https://github.com/KooshaPari/Khostty.git && cd Khostty/khostty-python
#   pip install .
```

### Other languages

```bash
# Go — local clone (no published module path yet)
go install github.com/KooshaPari/Khostty/khostty-go@latest
# OR today (no tagged release yet):
#   git clone https://github.com/KooshaPari/Khostty.git && cd Khostty/khostty-go
#   go build ./...

# C ABI — build from source (see docs/BUILD.md §2)
zig build -Demit-lib-vt -Doptimize=ReleaseSafe
# → zig-out/lib/libghostty-vt.{a,0.1.0.dylib,0.1.0.so}
```

### Desktop applications

Download from the GitHub release page: **<https://github.com/KooshaPari/Khostty/releases/tag/v0.1.0>**

| Platform                     | Asset                                    | Status                                                                                                                                         |
| ---------------------------- | ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| macOS                        | `Khostty-0.1.0-macos.zip`                | **shippable** (signed, interactive keystroke round-trip verified 2026-09-20; not notarized)                                                    |
| Linux (Debian/Ubuntu x86_64) | `khostty_0.1.0_amd64.deb`                | **shippable** (GTK application; install-verified on WSL Fedora 44, GUI launch half-verified via Xvfb 2026-09-19)                               |
| Windows                      | `Khostty-0.1.0-windows-x86_64-setup.exe` | **build + install + uninstall verified; GUI window not yet launched** — the runtime is a scaffold (Phase 0 → Phase B GTK priority; see Status) |

The macOS ZIP, Linux `.deb`, and Windows installer are all built and signed on a
release host. The Windows GUI launch is the one step still owed: the runtime
scaffold exists (`src/apprt/windows/`, ~3,300 lines), but its windowing + IPC
calls all return `error.Unimplemented` until G3 is lifted.

### Build from source

For a full build-from-source walkthrough see **[`docs/BUILD.md`](docs/BUILD.md)**.
The short version, which produces the VT library only (no GUI dependencies):

```bash
git clone https://github.com/KooshaPari/Khostty
cd Khostty
zig build -Demit-lib-vt -Doptimize=ReleaseSafe   # 84/84 conformance against the result
```

---

## What Khostty Is

Khostty is the **Phenotype-flavored fork of [Ghostty](https://github.com/ghostty-org/ghostty)**,
the fast, native, feature-rich terminal emulator written in Zig by Mitchell
Hashimoto and contributors. Ghostty ships `libghostty-vt`, a standalone C library
with 203 `GHOSTTY_API` functions across 30+ header files, 30 examples in C, Zig,
and WASM, fuzz tests, benchmarks, and a complete terminal emulator. The engine
covers parsing, screen state, scrollback, cursor handling, styles, selection,
search, render state, snapshots, Kitty graphics, SGR, OSC, and key and mouse
encoding.

Khostty does **not** rebuild that engine or maintain a separate terminal user
experience. It tracks upstream and focuses the fork delta on capabilities upstream
does not provide:

| Value area            | Upstream Ghostty                                                         | Khostty direction                                                                | Status                                                                                                                                               |
| --------------------- | ------------------------------------------------------------------------ | -------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Embedding             | `libghostty-vt` C ABI + 30 examples                                      | Polyglot FFI: Rust, Go, Python, WASM                                             | **0.1.0 SHIPPED** — Rust on crates.io; WASM on npm; Python sdist built (PyPI pending); Go local                                                      |
| Windows               | macOS AppKit + Linux/BSD GTK only                                        | Win32 + DirectWrite scaffold                                                     | **SCAFFOLD** — `ghostty.exe + ghostty-vt.dll` builds + installs + uninstalls; GUI window not yet launched (G3 deferred)                              |
| Agent IPC             | `ipc.zig`: 3 commands (`new_window`, `new_tab`, `toggle_quick_terminal`) | Typed JSON command/event protocol: 13 commands, 7 events, fail-closed token auth | **CODE-COMPLETE, RUNTIME WIRING IN PROGRESS** — 6,839 LOC, 458 tests, build-wired at `test-agent-ipc`; `Server.bind` not yet called from any runtime |
| Phenotype integration | None                                                                     | Reusable terminal surfaces in the Phenotype Fabric graph                         | Planned                                                                                                                                              |

If you want a finished desktop terminal today, use upstream Ghostty.
Khostty is the integration and extension path: embed the VT engine, drive a
terminal from an agent, or extend the binding surfaces.

---

## Status

> **Library-first 0.1.0 SHIPPED (2026-09-27)** — Rust `khostty-vt 0.1.0` on
> [crates.io](https://crates.io/crates/khostty-vt); WASM `@khostty/libghostty-vt-wasm 0.1.0`
> on [npm](https://www.npmjs.com/package/@khostty/libghostty-vt-wasm); Python
> `khostty_vt 0.1.0` **built locally, PyPI unpublished** (trusted-publishing
> workflow committed, pre-flighted, awaits operator action — see
> [`docs/RELEASE.md`](docs/RELEASE.md) §7); Go `khostty-go` local clone only (no
> tagged module path yet); C ABI `libghostty-vt` build from source; macOS `.app`
> and Linux `.deb` shipped; Windows installer build-verified but GUI not yet
> launchable. **Agent IPC: code-complete, runtime wiring in progress.**

| Surface                                  | Status                                                                                                                                                                                                           |
| ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| C ABI `libghostty-vt`                    | **shippable** — build from source; 84/84 conformance                                                                                                                                                             |
| Rust `khostty-vt 0.1.0`                  | **shipped** on crates.io                                                                                                                                                                                         |
| WASM `@khostty/libghostty-vt-wasm 0.1.0` | **shipped** on npm (with `wasm/package.json` 0.0.0 drift — Phase A6 fix)                                                                                                                                         |
| Python `khostty_vt 0.1.0`                | sdist built; **PyPI pending trusted publisher** (operator action)                                                                                                                                                |
| Go `khostty-go`                          | local clone only; no tagged module path                                                                                                                                                                          |
| macOS `Khostty.app`                      | **shipped** signed; not notarized                                                                                                                                                                                |
| Linux GTK `.deb`                         | **shipped**; install-verified; GUI-launch half-verified via Xvfb                                                                                                                                                 |
| Windows `setup.exe`                      | **build + install + uninstall verified**; GUI not yet launched (G3 scaffold)                                                                                                                                     |
| Agent IPC v1 (13 commands, 7 events)     | **code-complete, build-wired**; runtime `Server.bind` not yet called; 2 commands (`pane.focus`, `pane.search`) return `error.Unsupported` even after GTK wiring (upstream-core API work; out of fork-only scope) |
| Conformance (`conformance/`, 84/84)      | **shipped**                                                                                                                                                                                                      |
| EGL type-regression harness              | **shipped** (PR #19 / `795383` + BOTH-arms synthetic coverage `69e955cfc`/`5055d2c17`)                                                                                                                           |

### What the agent IPC story looks like today

- **Wire format and protocol:** finalized — 13 commands (`ping`, `pane.create`,
  `pane.close`, `pane.focus`, `pane.list`, `pane.write`, `pane.state`,
  `pane.search`, `pane.resize_split`, `pane.equalize`, `pane.zoom`,
  `events.subscribe`, `events.unsubscribe`), 7 events (`title_change`,
  `pane_exit`, `resize`, `bell`, `osc_*`), token auth (32-byte hex,
  constant-time SHA-256), max frame 1 MiB. See [`docs/SECURITY.md`](docs/SECURITY.md)
  §5 and `docs/src/apprt/ipc/protocol.md`.
- **Build status:** the 6 modules (`protocol`, `state`, `events`, `auth`,
  `pane`, `handler`, `server`, `app_host`) compile and pass unit tests
  (458/458) via the `test-agent-ipc` build step, wired on `main` at PR #15
  (`ebc033eba`, 2026-10-15).
- **Runtime status:** **no runtime currently calls `Server.bind`**.
  `rg 'Server.bind' src/` outside `src/apprt/ipc/` returns 0 hits. The GTK
  runtime is the intended call site; the macOS operator host cannot build GTK,
  so wiring is blocked on a GTK/Linux environment.
- **Honest disclosure:** even after GTK wiring, **`pane.focus` and `pane.search`
  return `error.Unsupported`** against the GTK runtime today. These commands
  need upstream-core APIs (focus-by-id, synchronous scan) that do not exist
  upstream — out of fork-only scope. Until then, the protocol advertises 13
  commands and delivers 11 on its single supported runtime. **Do not build
  against `pane.focus` or `pane.search` and do not report them as shipped.**
- **Cross-thread hazard:** `pane.write` (`app_host.zig:290-298`) currently
  touches the parser from a connection thread; this is a latent data race that
  will surface the moment GTK wiring lands. Fix is tracked alongside the
  runtime wiring (1 day of GTK work).

### Forward path

The polished reality is captured in detail at
[`docs/audits-archive/2026-10-17-final/FINAL-AUDIT.md`](docs/audits-archive/2026-10-17-final/FINAL-AUDIT.md)
and [`docs/audits-archive/2026-10-17-final/FWD-PATH.md`](docs/audits-archive/2026-10-17-final/FWD-PATH.md).
Summary: ~3h polish batch (Phase A, 7 low-risk tasks) + ~1d GTK runtime wire-up
(Phase B, the actual G4 finish line) + ~2d Phase 1 mux design (blocked on
operator windowed-runtime decision). Phase 1 mux implementation and Windows
GUI expansion are out of the "as close to finish as possible" scope.

### Authoritative handoff

- [`FINAL-AUDIT.md`](docs/audits-archive/2026-10-17-final/FINAL-AUDIT.md) —
  synthesis, current state, what's done, what's unfinished, MVP scoring
- [`FWD-PATH.md`](docs/audits-archive/2026-10-17-final/FWD-PATH.md) — Phases
  A/B/C task lists, operator decisions, effort budget
- [`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md)
  — the 115-task, ~19.2-hour Deep WBS that drove the 0.1.0 ship

---

## Architecture

Khostty keeps the upstream engine intact and places the fork surface above it.

```text
Khostty
├── apprt: platform-specific application runtimes
│   ├── embedded.zig       macOS AppKit runtime, upstream
│   ├── gtk.zig            Linux/BSD GTK runtime, upstream
│   ├── windows/            Win32/DirectWrite runtime, SCAFFOLD (G3 deferred)
│   └── ipc/                JSON IPC server + protocol, fork delta
├── terminal: headless upstream engine
│   ├── parser, screen, scrollback, cursor, selection, search
│   ├── render state, snapshots, Kitty graphics, SGR, OSC
│   └── key and mouse encoding
├── libghostty-vt: C ABI exported from the upstream engine
├── renderer and surfaces
│   ├── Metal and OpenGL for upstream platforms
│   └── DirectWrite planned for Windows
└── binding layer (this is the 0.1.0 ship)
    ├── Rust: khostty-vt         (crates.io 0.1.0)
    ├── Go: khostty-go           (local clone)
    ├── Python: khostty_vt       (sdist 0.1.0; PyPI pending)
    └── WASM: @khostty/libghostty-vt-wasm  (npm 0.1.0)
```

### Layer responsibilities

1. **`libghostty-vt`** is the stable C ABI and the source of terminal
   correctness. Khostty wraps it rather than reimplementing parser behavior in
   another language.
2. **`apprt`** owns platform shells, input, windowing, rendering integration,
   and the IPC server (when wired by a runtime).
3. **The Agent/IPC layer** (`src/apprt/ipc/`) translates JSON commands into
   terminal actions and exposes machine-readable state and events.
4. **The binding layer** provides safe language-specific ownership, error, and
   lifetime semantics around the C ABI.
5. **Phenotype Fabric** can embed the resulting terminal surface without
   depending on a particular GUI framework.

The fork surface is `src/apprt/khostty/`, `src/apprt/windows/`, `src/apprt/ipc/`,
plus the binding crates under `khostty-vt/`, `khostty-go/`, `khostty-python/`,
and `wasm/`. Upstream `src/terminal/` and `src/renderer/` remain the source of
truth.

---

## Agent/IPC surface

> **Status: CODE-COMPLETE, RUNTIME WIRING IN PROGRESS.** All 13 commands are
> implemented, tested (458/458 across 7 modules), and wired into the build at
> `test-agent-ipc` (PR #15 / `ebc033eba`). No runtime currently calls
> `Server.bind`. Until the GTK runtime wires the server, the protocol is
> readable but unreachable. **Even after GTK wiring, `pane.focus` and
> `pane.search` return `error.Unsupported`** (need upstream-core APIs; out of
> fork-only scope).

The IPC layer expands upstream's three commands into a versioned JSON command,
response, and event protocol. The architecture calls for a Unix domain socket on
Unix-like platforms and a Windows named pipe on Windows, with token-based
authentication.

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

The command set, with honest status:

| Command                                   | Status                              | Note                                          |
| ----------------------------------------- | ----------------------------------- | --------------------------------------------- |
| `pane.create`                             | implemented, runtime-wiring pending | split vertical/horizontal + cwd               |
| `pane.close`                              | implemented, runtime-wiring pending | by pane id                                    |
| `pane.list`                               | implemented, runtime-wiring pending | live panes                                    |
| `pane.write`                              | implemented, runtime-wiring pending | race fix must ship with wiring                |
| `pane.state`                              | implemented, runtime-wiring pending | cursor, title, size, scrollback               |
| `pane.resize_split`                       | implemented, runtime-wiring pending | resize split ratio                            |
| `pane.equalize`                           | implemented, runtime-wiring pending | equalize splits                               |
| `pane.zoom`                               | implemented, runtime-wiring pending | zoom toggle                                   |
| `pane.focus`                              | **returns `error.Unsupported`**     | needs upstream focus-by-id API                |
| `pane.search`                             | **returns `error.Unsupported`**     | needs upstream synchronous scan API           |
| `events.subscribe` / `events.unsubscribe` | implemented, runtime-wiring pending | title*change, pane_exit, resize, bell, osc*\* |
| `ping`                                    | implemented, runtime-wiring pending | only unauthenticated command                  |
| `surface.list`, `window.list`             | implemented, runtime-wiring pending | enumerate surfaces and windows                |

See [`docs/src/apprt/ipc/protocol.md`](docs/src/apprt/ipc/protocol.md) and
[`docs/SECURITY.md`](docs/SECURITY.md) §5 for the full protocol + auth design.

---

## Conformance

> **Status: 84/84 conformance checks pass** (2026-09-16; recomputed 2026-09-18).
> This was the critical gate before Windows, IPC, FFI, and feature work.

G2 must prove that Khostty has no unacceptable terminal correctness regression.
Build success is not enough. The gate covers the upstream Zig tests, the fuzz
corpus, and the complete set of upstream examples.

Acceptance criteria from the WBS:

- All 30 upstream examples build and run without crashing.
- The fuzz corpus in `test/fuzz-libghostty/` produces zero new crashes.
- A pass/fail matrix is committed to the session documentation with observed
  evidence.
- Failures include upstream issue references and a documented resolution path.

The conformance target includes parsing and streaming, SGR, key and mouse
encoding, Kitty graphics, snapshots, render state, search, formatting, grid
access, compression, colors, effects, selection, static and CMake builds, WASM
examples, Zig, C++, Swift, and Python examples.

```bash
zig build -Demit-lib-vt -Doptimize=ReleaseSafe
bash conformance/build.sh run
# expected tail: Passed: 84 / Failed: 0 / Total: 84 / Success Rate: 100%
```

---

## Platform support

| Platform      | Status        | Runtime or artifact                                                                                                                               |
| ------------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| **macOS**     | **shippable** | Upstream Swift/AppKit application runtime; `Khostty-0.1.0-macos.zip` signed + interactive keystroke round-trip verified 2026-09-20; not notarized |
| **Linux/BSD** | **shippable** | Upstream GTK application runtime; `khostty_0.1.0_amd64.deb` install-verified on WSL Fedora 44, GUI-launch half-verified via Xvfb 2026-09-19       |
| **Windows**   | **scaffold**  | `ghostty.exe + ghostty-vt.dll` build + install + uninstall verified 2026-09-19; GUI window not yet launched (G3 deferred; 3-4w scope to lift)     |
| **WASM**      | **shippable** | `@khostty/libghostty-vt-wasm 0.1.0` on npm; `wasm/package.json` shows 0.0.0 (drift; Phase A6 fix)                                                 |

The Windows runtime scaffold (`src/apprt/windows/`, ~3,300 lines, 11 files) is
intentionally kept; **every `error.Unimplemented` is test-asserted**
(`interface.zig:39-45`), so the scaffold cannot silently regress.

---

## Polyglot FFI

| Language   | Status                              | Package                                                                                    | Purpose                                                                                                                      |
| ---------- | ----------------------------------- | ------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| **Rust**   | **0.1.0 SHIPPED**                   | [`khostty-vt`](https://crates.io/crates/khostty-vt)                                        | Safe Rust wrapper with RAII handles, typed errors, 199/199 integration tests                                                 |
| **Go**     | **local clone**                     | `github.com/KooshaPari/Khostty/khostty-go`                                                 | cgo-based idiomatic Go wrapper with context and error handling (45/45 tests; no tagged module path yet)                      |
| **Python** | **sdist 0.1.0 BUILT; PyPI pending** | `khostty-vt` (`pip install khostty-vt`)                                                    | cffi-based Python package for terminal automation and scripting; PyPI trusted publisher registration pending operator action |
| **WASM**   | **0.1.0 SHIPPED**                   | [`@khostty/libghostty-vt-wasm`](https://www.npmjs.com/package/@khostty/libghostty-vt-wasm) | Hardened WASM package + typed JavaScript API; browser/Node consumption of the VT engine (54/54 tests)                        |
| **C ABI**  | **build from source**               | `libghostty-vt`                                                                            | The upstream C ABI; 203 `GHOSTTY_API` functions across 30+ headers                                                           |

The upstream C ABI and existing examples remain the baseline that these
packages wrap. The Rust design uses raw bindings isolated behind a documented
unsafe boundary, with safe `Terminal`, `Snapshot`, `RenderState`, `Search`,
`KeyEncoder`, and `MouseEncoder` types and an explicit `GhosttyError` result
type. Go and Python follow the same wrap-over-handroll rule.

---

## Repository pointers

- [`HACKING.md`](HACKING.md) — inherited upstream development workflow.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — contribution and review conventions.
- [`build.zig`](build.zig) — Zig build entrypoint and test targets.
- [`build.zig.zon`](build.zig.zon) — package metadata and minimum Zig version.
- [`docs/BUILD.md`](docs/BUILD.md) — compiling from source, flag reference, troubleshooting.
- [`docs/INSTALL.md`](docs/INSTALL.md) — per-platform install + verify.
- [`docs/audits-archive/2026-10-17-final/FINAL-AUDIT.md`](docs/audits-archive/2026-10-17-final/FINAL-AUDIT.md)
  — current-state audit (canonical).
- [`docs/audits-archive/2026-10-17-final/FWD-PATH.md`](docs/audits-archive/2026-10-17-final/FWD-PATH.md)
  — Phase A/B/C task lists.
- [`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md)
  — the 115-task Deep WBS that drove 0.1.0.

### Recommended workflow

1. Read the relevant gate in the Deep WBS before changing code.
2. Run formatting and the narrowest relevant build or test target.
3. Keep upstream engine changes separate from Khostty-specific apprt, IPC, and
   binding work.
4. Add conformance evidence for correctness-sensitive changes.
5. Update the README, API examples, and WBS status only after the evidence
   exists.

### Sync with upstream

```bash
git fetch upstream
git merge upstream/main
zig build
zig build test
zig fmt --check src/ build.zig
```

---

## Contributing

Issues, bug reports, and pull requests that change upstream code in
`src/terminal/`, `src/renderer/`, or the upstream `apprt` implementations
should go to [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty)
first. This keeps the shared engine aligned with upstream.

Khostty-specific contributions are welcome in:

- `src/apprt/windows/` (scaffold; lift G3 with operator)
- `src/apprt/khostty/`
- `src/apprt/ipc/`
- `bindings/`, `khostty-vt/`, `khostty-go/`, `khostty-python/`, `wasm/`

Before opening a pull request:

1. Run `zig fmt --check src/ build.zig`.
2. Run the relevant `zig build test` target.
3. For IPC work, add protocol examples and authentication tests.
4. For FFI work, add language-specific ownership, error, and integration tests.
5. Record conformance evidence when terminal behavior changes.
6. Keep commits focused and include the repository's transaction-ledger
   metadata when applicable.

---

## Links

- **Upstream Ghostty:** <https://github.com/ghostty-org/ghostty>
- **Upstream documentation:** <https://ghostty.org/docs>
- **Upstream download:** <https://ghostty.org/download>
- **0.1.0 release:** <https://github.com/KooshaPari/Khostty/releases/tag/v0.1.0>
- **crates.io:** <https://crates.io/crates/khostty-vt>
- **npm:** <https://www.npmjs.com/package/@khostty/libghostty-vt-wasm>
- **Khostty assessment history:** [`docs/sessions/20260916-fork-assessment/`](docs/sessions/20260916-fork-assessment/)
- **Deep WBS:** [`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md)
- **Audit snapshot (2026-10-17):** [`docs/audits-archive/2026-10-17-final/`](docs/audits-archive/2026-10-17-final/)
- **Phenotype handbook:** [`docs/GLOBAL_HANDBOOK.md`](docs/GLOBAL_HANDBOOK.md)

---

## License

Khostty is distributed under the **MIT License**, the same license as upstream
Ghostty. The complete repository license is in [`LICENSE`](LICENSE).

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

Khostty is built on [Ghostty](https://github.com/ghostty-org/ghostty) by
**Mitchell Hashimoto** and the Ghostty contributors. The fork exists to extend
Ghostty's embeddable terminal engine for Phenotype use cases while keeping the
upstream parser, renderer, and terminal behavior as the source of truth.

Thanks to the Phenotype team and community contributors for the integration
requirements, assessment work, and roadmap feedback.

---

<p align="center">
  <sub>Built on Ghostty. Maintained for the Phenotype platform.</sub>
</p>
