# Glossary

Terms used across Khostty documentation, code, and the Deep WBS. Where a term has
a precise in-repo meaning, the file that defines it is cited.

---

## Terminal protocol

**VT** — *Virtual Terminal.* The family of behaviours a terminal emulator
implements: escape sequence parsing, screen state, cursor movement, scrollback,
attributes. Khostty's engine lives in `src/terminal/`. "VT" is also shorthand for
the `libghostty-vt` library name.

**Escape sequence** — A byte string beginning with `ESC` (`0x1B`) that instructs
the terminal rather than printing a character. Introducers:

| Introducer | Name | Meaning | Header |
|---|---|---|---|
| `ESC [` (CSI) | Control Sequence Introducer | Cursor movement, erase, modes, SGR | `src/terminal/csi.zig` (no standalone C parser) |
| `ESC ]` (OSC) | Operating System Command | Window title, colours, cwd, hyperlinks, clipboard | `include/ghostty/vt/osc.h`, `src/terminal/osc/` |
| `ESC P` (DCS) | Device Control String | Device queries and responses | `src/terminal/dcs.zig` |
| `ESC _` (APC) | Application Program Command | Kitty graphics, clipboard protocol | `src/terminal/apc/` |
| `ESC (` / `ESC )` (SCS) | Select Character Set | `G0`/`G1` charset shift, line drawing | `src/terminal/charsets.zig` |

**CSI** — *Control Sequence Introducer.* The `ESC [` prefix. Examples:
`CSI 2 J` (erase display), `CSI 5 ; 10 H` (move cursor to row 5, column 10).

**SGR** — *Select Graphic Rendition.* The `CSI … m` subset that sets text
attributes: bold, dim, italic, underline (and styles), blink, reverse, strike,
foreground/background colour, including 256-colour and 24-bit RGB. Parsed by
`src/terminal/sgr.zig`; also exposed standalone as `include/ghostty/vt/sgr.h`.

**OSC** — *Operating System Command.* The `ESC ]` prefix. Relevant codes:
`OSC 0`/`2` window title, `OSC 7` working directory, `OSC 8` hyperlinks,
`OSC 10`/`11`/`12` foreground/background/cursor colour, `OSC 52` clipboard.

**DEC private mode** — A terminal mode toggled by `CSI ? n h` (set) or `CSI ? n l`
(reset). Examples: `DECCKM` (application cursor keys), `DECAWM` (autowrap),
`DECTCEM` (cursor visible), `DECOM` (origin mode). See `src/terminal/modes.zig`.

**Kitty graphics protocol** — An image-transport protocol sent over APC. Khostty
carries the upstream parser (`src/terminal/kitty/`, `include/ghostty/vt/kitty_graphics.h`).
It is *disabled* on freestanding/WASM targets, where the sequences are consumed
and ignored.

**Grapheme cluster** — One user-perceived character, which may be several
codepoints (base + combining marks, ZWJ sequences, regional indicators). Width
utilities: `include/ghostty/vt/unicode.h`.
See `src/terminal/selection_codepoints.zig` for selection on clusters.

**Reflow** — Re-laying out soft-wrapped lines when the terminal is resized, so
logical lines survive a width change. Lives in the page/scrollback layer
(`src/terminal/PageList.zig`, `page.zig`).

**Scrollback** — Lines scrolled off the top of the visible screen, retained for
history and search. Bounded, and compressible (`-Demit-lib-vt`'s compression API
in `include/ghostty/vt/terminal.h`).

---

## Khostty and Ghostty concepts

**AppRT** — *Application Runtime.* The compile-time abstraction over the host
application: creating windows, delivering input, reading the clipboard. Defined
in `src/apprt.zig`; the selected implementations are `embedded` (macOS),
`gtk` (Linux/FreeBSD), `browser` (wasm), `none` (headless), and `ipc`
(action channel). Khostty adds a Windows runtime under `src/apprt/windows/`
(currently SCAFFOLD).

**Surface** — One terminal viewport bound to one process. A surface owns a
`Terminal`, a renderer, input routing, and a PTY. `src/Surface.zig` is the generic
contract; platform runtimes wrap it (`src/apprt/gtk/Surface.zig`,
`src/apprt/windows/surface.zig`, `src/apprt/embedded.zig`).

**Pane** — A subdivision of a window holding a surface. Pane *creation* as an
external, addressable operation is Khostty's G4 delta: upstream exposes splits
only through the in-app action system (`src/apprt/action.zig`), not over IPC.

**Split** — The upstream action that creates a pane by dividing a surface.
Externally unreachable today; `pane.create` in the G4 draft wraps it.

**Quick terminal** — A drop-down/overlay terminal toggled by a hotkey. One of the
three upstream IPC actions (`toggle_quick_terminal`), also on the CLI as
`+toggle-quick-terminal`.

**Window vs tab vs split** — Upstream's hierarchy. A window contains tabs; a tab
contains one or more splits (panes). Upstream IPC can create a window and a tab,
but not a split.

**Snapshot** — A serialized encoding of terminal state (screen, cursor, styles,
scrollback metadata) that another terminal instance can restore. API:
`include/ghostty/vt/snapshot.h`; implementation: `src/terminal/snapshot/`.

**Formatter** — The component that renders terminal contents *out* as plain
text, re-emitted VT sequences, or HTML. API: `include/ghostty/vt/formatter.h`.
The conformance harness compares formatter output, because it is the same code
path that copies terminal text to the clipboard.

**Grid ref / tracked grid ref** — A stable handle to a cell or row that can
survive scrolling, and can report when it has lost its value. APIs:
`include/ghostty/vt/grid_ref.h`, `grid_ref_tracked.h`.

**libghostty-vt** — The standalone C library extracted from Ghostty: parser,
screen, scrollback, cursor, styles, selection, search, render state, snapshots,
Kitty graphics, SGR, OSC, and key/mouse encoding. Declared by
`include/ghostty/vt.h`. This is the fork's central artifact; the Khostty
principle is to *wrap* it, never to reimplement it.

**libghostty** — The larger library surface used by the macOS embedded runtime
(`src/lib/`). Broader than `libghostty-vt`.

**xcframework** — Apple's multi-platform binary bundle format. Built with
`-Demit-xcframework`; carries macOS (arm64 + x86_64) and iOS slices.

**wasm32-freestanding** — The WebAssembly target with no OS: no PTY, no
filesystem, no clock. `libghostty-vt` builds for it with `rdynamic` exports and a
128 KB stack. Produces `ghostty-vt.wasm`.

**ABI** — *Application Binary Interface.* The binary-level calling contract:
struct layouts, enum values, calling convention. Khostty treats it as data, not
assumption: `ghostty_type_json()` publishes the ABI as a JSON manifest
(pointer/`size_t` width, endianness, alignment, per-type offsets and enum values)
so wrappers lay out structs from the manifest instead of hardcoding numbers.

**ABI drift** — A wrapper's declared types diverging from the real library's
layout. Detected by `khostty-vt/tests/abi_layout.rs` against the type manifest,
and by the WASM type-level test against the same manifest.

**FFI** — *Foreign Function Interface.* Calling C from another language.
`khostty-vt` isolates all `unsafe` in `src/ffi.rs`; `wasm/js/abi.js` provides the
typed handle/allocation layer for JS.

**Type manifest** — The JSON returned by `ghostty_type_json()`. The single source
of truth for cross-language struct layout.

**Consolidated header** — `wasm/include/ghostty-vt.h`: the whole public C ABI
flattened into one self-contained file by running the C preprocessor and keeping
only regions originating under `include/ghostty/`. Generated and verified by
`wasm/tools/gen-consolidated-header.mjs` and `wasm/tools/verify-header.sh`.

---

## Verification vocabulary

**Conformance** — Behaviour preservation against a curated corpus of VT/ANSI
inputs with expected outputs. Khostty's corpus is `conformance/` — 84 cases
across 8 categories, gated by `conformance/build.sh`. A conformance failure means
the parser or formatter changed behaviour; that blocks feature work.

**Conformance case** — One input byte string plus its expected formatter output.
Canonical source is `conformance/cases/<category>/cases.zig`; the C harness keeps
a byte-identical mirror. Adding a case means updating both.

**Harness** — `conformance/harness.c`. Links the prebuilt `libghostty-vt` and
drives reset → resize → feed → snapshot → compare for each case.

**Gate (G0–G10)** — A milestone in the Deep WBS with its own objective, task
list, and acceptance criteria. Gates are ordered by dependency, not importance.

| Gate | Scope | Status (2026-09-17) |
|---|---|---|
| G0 | Fork hygiene (CI, README) | DONE |
| G1 | Native build validation | DONE |
| G2 | Conformance evidence | DONE — 84/84 |
| G3 | Windows application runtime | IN PROGRESS (SCAFFOLD) |
| G4 | Agent/IPC surface expansion | IN PROGRESS |
| G5 | Polyglot FFI — Rust | IN PROGRESS |
| G6 | Polyglot FFI — Go + Python | IN PROGRESS (Go only) |
| G7 | WASM cross-compilation | IN PROGRESS |
| G8 | Khostty improvements + benchmarks | NOT STARTED |
| G9 | Documentation + packaging | IN PROGRESS (this document set) |
| G10 | Release artifacts + ecosystem | NOT STARTED |

**Accepted gate, not accepted product** — G2 passing 84/84 proves the VT core did
not regress on that corpus. It does not mean Windows runs, IPC exists, or the
fork is released. Each gate has independent acceptance.

**Evidence date** — When a claim was observed. Any status statement in `docs/`
carries one. A historical pass is not a fresh pass; re-run before relying on it.

---

## Process vocabulary

**WBS** — *Work Breakdown Structure.* The authoritative task decomposition at
`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md` (681 lines, 100 tasks,
11 gates).

**DRAFT / NOT STARTED marking** — Protocol text in the WBS labelled "Draft" is a
design proposal, not a shipped interface. This documentation set marks such text
explicitly so no consumer builds against it by accident.

**Ledger** — This repository treats Git history as an append-only transaction
ledger. Agent commits carry metadata trailers; history is never rewritten. See
[CONTRIBUTING.md](CONTRIBUTING.md#commit-ledger).

| Trailer | Value | Meaning |
|---|---|---|
| `tx-agent` | `jcode`, `codex`, `forge`, `human` | Who authored the change |
| `tx-validated` | `lint`, `test`, `build`, `cargo-check`, `manual`, `none` | What was run before committing |
| `tx-task` | e.g. `9.1` | Which WBS task this closes |
| `tx-scope` | e.g. `docs` | Affected components |
| `tx-intent` | one line | What the change achieves |

**Status vocabulary** — `DONE`, `IN PROGRESS`, `SCAFFOLD`, `NOT STARTED`,
`UNKNOWN`, as defined in [ARCHITECTURE.md](ARCHITECTURE.md#khostty-architecture).
Never a percentage without an observed denominator.

---

## See also

- [ARCHITECTURE.md](ARCHITECTURE.md) — layers and extension points
- [API.md](API.md) — C, IPC, and CLI surfaces
- [TESTING.md](TESTING.md) — conformance and gate mechanics
- Deep WBS: [`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](sessions/20260916-fork-assessment/02_DEEP_WBS.md)
