# Fork Delta: Khostty vs Upstream Ghostty

**Observed:** 2026-09-17 · What this fork adds, what it deliberately does not, and
what the evidence does and does not support.

Upstream: [`ghostty-org/ghostty`](https://github.com/ghostty-org/ghostty).
This repository is a fork. The WBS states the fork's premise in one line: the value
is **not** rebuilding what upstream has.

---

## 1. What upstream already ships

Buying nothing by duplicating:

| Upstream asset | Scale |
|---|---|
| `libghostty-vt` — standalone C library | 203 `GHOSTTY_API` functions across 34 headers |
| Terminal engine | Parser, screen, scrollback with reflow, cursor, styles, selection, search, render state, snapshots, Kitty graphics, SGR, OSC, key/mouse/focus encoding, text formatting, colour utilities, Unicode widths, grid refs |
| Application runtimes | macOS AppKit (`embedded`), Linux/BSD GTK4 (`gtk`), browser (`browser`), headless (`none`) |
| C and Zig examples | 35 example projects under `example/` |
| Fuzz harnesses | AFL++ targets (`osc`, `parser`, `stream`) with 4,002 seed files |
| Benchmarks | Upstream bench tooling (`-Demit-bench`) |
| Test suite | ~289 Zig source files containing tests |
| Packaging | `.deb`/`.rpm` inputs, Flatpak, Snap, Nix flake, macOS Xcode project |
| Docs | `HACKING.md`, `PACKAGING.md`, Doxygen config, per-example READMEs |

Anything on that list is inherited, not contributed. A fork that "adds" a terminal
parser would be adding nothing.

---

## 2. The four deltas the fork claims

From the WBS scope section:

### 2.1 Prove the embedding path end to end (G1, G2)

| Claim | Evidence | Status |
|---|---|---|
| `libghostty-vt` builds as static, shared, xcframework, and WASM | Artifacts in `zig-out/` dated 2026-09-16 | **DONE** |
| The C API behaves as specified | `conformance/` — 84 cases, 8 categories, 84/84 pass (2026-09-17) | **DONE** |
| Conformance is repeatable tooling, not a one-off | `conformance/build.sh` + `harness.c` + per-category case files | **DONE** |

This is the fork's most solid contribution: a *Khostty-owned* behavioural gate over
an upstream library. It answers "did we break the terminal?" with a number.

### 2.2 Windows application runtime (G3)

| Item | Upstream | Khostty |
|---|---|---|
| `Runtime` enum | `none`, `gtk` | `none`, `gtk`, **`windows`** (added; uncommitted at time of writing) |
| Windows executable | **None** — `Runtime.default` returns `.none` for Windows | Intended `src/apprt/windows/` |
| Win32 integration | — | Scaffold only: `App.zig`, `Window.zig`, `surface.zig`, `renderer.zig`, `win32api.zig`, `ipc.zig` |
| Behaviour | — | Every operation returns `error.Unimplemented` |

**Honest state: scaffold, not a runtime.** No window has been created, no glyph
rendered, no binary run. The enum variant exists; the implementation does not.
Additionally the scaffold is not wired into `src/apprt.zig`, `mod.zig` has a
case-sensitivity defect in its `Surface.zig` import, and adding `windows` to the
enum currently breaks the build because the exhaustive switch in
`src/build/SharedDeps.zig` was not updated.

This is the headline *prospect*. It is not yet a headline *result*.

### 2.3 Agent/IPC surface (G4)

Upstream IPC is a typed three-action channel:

```zig
new_window, new_tab, toggle_quick_terminal
```

No pane creation, no state query, no event stream, no JSON.

Khostty adds a v1 agent protocol, specified in
[`src/apprt/ipc/protocol.md`](../src/apprt/ipc/protocol.md):

| Dimension | Upstream | Khostty v1 |
|---|---|---|
| Wire format | C ABI struct | Line-delimited JSON |
| Commands | 3 | 13 (`ping`, pane create/close/focus/list/write/state/search/resize_split/equalize/zoom, events subscribe/unsubscribe) |
| Pane addressing | — | `pane_id` handles |
| Machine-readable state | — | Cursor, title, pid, cwd, size, modes, bell count, scrollback depth |
| Scrollback search | — | `pane.search` |
| Async events | — | Broker with subscribe/unsubscribe |
| Auth | — | Token, fail-closed, constant-time compare |
| Platform transport | — | Unix socket; Windows named pipe specified |

**Honest state: designed and partly implemented, not reachable.** `protocol.zig`,
`state.zig`, `events.zig`, `auth.zig`, `pane.zig`, and `fake_host.zig` exist.
`server.zig` and `app_host.zig` do not. Nothing is re-exported or wired, so no
running instance listens.

One genuine engineering contribution even at this stage: a documented, honest
handling of upstream's fire-and-forget `new_split`. Because the action returns
nothing, the adapter diffs the surface registry before and after and **fails** with
`internal` rather than fabricating a pane id when the registry does not report one.

### 2.4 Polyglot FFI (G5, G6, G7)

Upstream ships C and Zig APIs with examples in other languages. The fork's claim is
**safe, packaged** wrappers.

| Ecosystem | Upstream | Khostty | Status |
|---|---|---|---|
| Rust | Example only | `khostty-vt` crate: RAII `Terminal`, snapshot, render, search, key, mouse, selection; ABI layout guard; bindgen drift check | IN PROGRESS — modules present, `cargo test` not re-run |
| Go | Example only | `khostty-go`: cgo bindings for terminal, snapshot, render, search, style, queries, with tests | IN PROGRESS — author-verified `go build`/`go vet` |
| Python | Example only | `khostty-python`: cffi bindings and library discovery, `pyproject.toml` | IN PROGRESS (G6.5) — scaffold |
| WebAssembly | Hand-written HTML demos | `@khostty/libghostty-vt-wasm`: typed ESM package, 189 exports, manifest-driven struct layout, generated consolidated header, 52 tests | IN PROGRESS |

The strongest technical idea here is the **type manifest**: `ghostty_type_json()`
publishes the C ABI (pointer width, endianness, alignment, per-type offsets and enum
values) and every wrapper lays out structs from it. A hand-written offset table
corrupts memory silently on the next struct change; a manifest lookup fails loudly.
That is a real, transferable improvement over "write the offsets down and hope".

---

## 3. What the fork deliberately does not do

| Non-goal | Reason |
|---|---|
| Rewrite the parser | Wrap, do not reimplement. WBS design principle. |
| Maintain a divergent terminal UX | The fork tracks upstream's UX. |
| Modify `src/terminal/`, `src/renderer/`, `src/font/`, `src/config/` | Keeping these pristine is what makes upstream merges tractable. |
| Replace upstream's packaging | G9 adds docs; it does not re-platform `.deb`/Flatpak/Snap. |
| Claim performance superiority | **No benchmark exists.** See §4. |
| Send agent-authored PRs upstream | Upstream `AGENTS.md` forbids it and `AI_POLICY.md` requires a human owner. See [CONTRIBUTING.md](CONTRIBUTING.md). |

---

## 4. What the evidence does not support

Stated plainly, because the alternative is a fork that overclaims.

**No performance claim is justified yet.** The harness now exists (gate G8,
observed 2026-09-17), so the situation is narrower than "no benchmarks" but still
short of usable evidence:

| Benchmark asset | State |
|---|---|
| `bench/` harness | **Exists** — C harness linked against the shipped library: VT ingest throughput, snapshot latency, scrollback search, memory footprint, resize cost |
| `bench/results/khostty-20260917.{txt,json}` | **Captured** — 2026-09-17 03:57 PT, Apple M1 Pro, macOS 27.0 |
| `bench/results/upstream-20260917.txt` | **0 bytes — the upstream comparison did not complete** |
| `bench/results/README.md` | Absent, though `bench/README.md` points readers at it |
| Cross-renderer consistency run | Not attempted |
| IPC round-trip and FFI overhead benchmarks | Not attempted |

Why the captured numbers are not yet a claim:

1. **No upstream baseline.** The comparison file is empty, so there is nothing to
   compare against. "Khostty is faster than Ghostty" remains unsupported.
2. **Measured under extreme load.** The run recorded a 1-minute load average of
   **425** on a 10-core machine. The harness's own README states that observed
   medians moved by more than 3x between a loaded and an idle window, and that a
   run on a quiet machine is required for the numbers to mean anything.
3. **Tree was dirty.** The JSON records `git_status: dirty` at `1e6687dd2`, so the
   numbers do not describe a specific committable revision.

Reproduce on an idle machine before citing anything:

```bash
UPSTREAM_REPO=/path/to/ghostty bench/run.sh --upstream
```

Additional gaps:

| Gap | Consequence |
|---|---|
| No completed upstream comparison | No relative performance claim is possible |
| Benchmark run under load 425 | Captured medians are not stable enough to cite; only the paired back-to-back method would be |
| Benchmarks ran against a dirty tree | No revision-pinned result |
| Cross-renderer consistency untested | No evidence that macOS Metal and Linux GL produce the same output for the same input |
| WASM browser run never executed | Tests are Node-only; the same code path, but not a browser |
| Linux build and test never run | The GTK runtime is inherited and unexercised here |
| No agent config preset | WBS 8.11 (`khostty-agent.conf`, `--agent`) not started |
| Release not produced | G10 not started; no tagged artifacts |
| Build currently broken | Commit `e1277bea2` broke relative imports in `src/apprt/ipc/mod.zig`. See [BUILD.md](BUILD.md#unable-to-load-mainzig-filenotfound--unable-to-load-quirkszig) |

---

## 5. Fork hygiene ledger

| Aspect | State |
|---|---|
| Upstream core modified? | No (by policy) |
| Fork-owned directories | `conformance/`, `khostty-vt/`, `khostty-go/`, `wasm/`, `src/apprt/windows/`, `src/apprt/ipc/`, `docs/` |
| CI owned by the fork | `ci.yml` only (2 jobs) |
| CI inherited but inert | `test.yml`, `nix.yml`, `flatpak.yml`, `update-colorschemes.yml` (gated to `ghostty-org/ghostty`) |
| CI inherited and ungated | 12 workflow files, including release and publish workflows |
| Upstream merge cost | Low while `src/terminal/` and friends stay untouched |

The 12 ungated inherited workflows are a hygiene risk worth its own task: they
include `release-tag.yml`, `publish-tag.yml`, and vouch/release automation written
for upstream's repository, not this fork.

---

## 6. Is the fork worth maintaining?

The WBS asks this explicitly. An honest read of the current evidence (observed
2026-09-17):

**Yes, on one axis; unproven on the others.**

- **Proven:** an independent conformance gate over `libghostty-vt` is real,
  working, and reusable. It is the only artefact here that a consumer could adopt
  today without caveats.
- **Proven in design, unproven in behaviour:** the type-manifest approach to
  polyglot FFI is sound and already shipping in two ecosystems.
- **Unproven:** Windows support, agent IPC reachability, and any performance claim.
  All three are the reasons the fork exists, and none has an observed result.
- **Present but not yet evidence:** a benchmark harness exists and has produced one
  run, but with no upstream baseline and under load 425 it does not support a claim.
- **Missing entirely:** a completed benchmark comparison and a release.

The fork is currently a well-documented *plan* with one completed and verified gate.
That is a legitimate state to be in, provided it is described as such.

---

## See also

- [ARCHITECTURE.md](ARCHITECTURE.md) — how the deltas fit the layer stack
- [PLATFORMS.md](PLATFORMS.md) — per-platform honest status
- [AGENT.md](AGENT.md) — the agent-facing delta in practice
- [TESTING.md](TESTING.md) — the gate structure and evidence rules
- [BUILD.md](BUILD.md) — including the current build blocker
- Deep WBS: [`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](sessions/20260916-fork-assessment/02_DEEP_WBS.md)
