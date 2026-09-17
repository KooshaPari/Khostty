# What Khostty adds over upstream Ghostty

Benchmark-backed value-add summary for WBS 8.9-8.13. Gate references are to
`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md` (v2).

## Headline

Khostty is a **surfacing fork**, not a performance fork. Verified by diff:

```bash
git diff --name-only $(git merge-base HEAD upstream/main)..HEAD
```

There are **zero changes under `src/terminal/` or `include/ghostty/`**. The VT
engine is upstream's code, unmodified. Everything Khostty adds is either a
binding, an agent-facing surface, a platform runtime, or evidence tooling.

The correct claim is therefore not "Khostty's terminal is faster". It is
"Khostty exposes the upstream engine to Python, Go, Rust, JavaScript, and
agent IPC, on more platforms, with conformance and benchmark evidence, and it
does not regress the engine it carries".

## What the fork actually changes, by area

From `git diff --name-only <merge-base>..HEAD`, grouped by directory:

| Area | Files changed | Gate | What it is |
|---|---|---|---|
| `khostty-go/` | 21 | G6 | cgo bindings: terminal, render, search, snapshot, enums, integration tests |
| `wasm/js/` | 20 | G7 | ESM/TypeScript bindings and tests for the WASM build |
| `bench/` | 13 | G8 | This benchmark suite (5 sections, 156 metrics per run) |
| `docs/` | 12 | G9 | ARCHITECTURE, API, AGENT, PLATFORMS, BUILD, CONTRIBUTING, TESTING, GLOSSARY |
| `src/apprt/ipc/` | 8 | G4 | Agent IPC v1: protocol, auth, panes, events, state, fake host |
| `khostty-vt/tests/` | 8 | G5 | Rust wrapper integration tests |
| `src/apprt/windows/` | 7 | G3 | Windows app runtime: `App`, `Window`, `surface`, `renderer`, `interface`, `ipc`, `win32api`, input, keyboard, mouse |
| `khostty-vt/src/` | 7 | G5 | Safe Rust wrappers: terminal, snapshot, search, render, key, mouse, selection |
| `wasm/` | 5 | G7 | WASM build script, header export, package metadata |
| `khostty-python/khostty_vt/` | 5 | G6 | cffi ABI-mode bindings with struct-size verification |
| `conformance/` | 3 | G2 | C conformance harness, 84 cases in 8 categories |

## Gate-by-gate, with re-runnable evidence

| Gate | Status | Evidence |
|---|---|---|
| G0 Fork hygiene | DONE | Upstream boilerplate CI removed; Zig-aware CI added (`ci.yml`: fmt + build). WBS G0 tasks 0.1-0.4. |
| G1 Native build | DONE | `zig build -Demit-lib-vt -Doptimize=ReleaseSafe` produces `.a`, `.dylib`, `.xcframework`. Re-runnable; the command in this repo is the same one the benchmarks used. |
| G2 Conformance | DONE, 84/84 | `conformance/README.md` records 84 passed / 0 failed / 100%. Re-runnable with `conformance/build.sh`; it compiles a C harness against the same dylib the benchmarks use. |
| G3 Windows app runtime | IN PROGRESS | `src/apprt/windows/{surface,interface,ipc}.zig`, named-pipe IPC stub, renderer adapter stub. |
| G4 Agent IPC | IN PROGRESS | `src/apprt/ipc/{protocol,auth,pane,events,state,fake_host}.zig`; token auth is fail-closed. |
| G5 Rust FFI | IN PROGRESS | `khostty-vt` crate: typed `GhosttyError` mapping, allocator/buffer integration, ABI layout guard, bindgen cross-check of hand-written bindings. |
| G6 Go + Python FFI | IN PROGRESS | `khostty-go` (cgo, integration tests, examples) and `khostty-python` (cffi ABI mode; reproduces C struct layouts and validates them against the library's own type manifest). |
| G7 WASM | DONE, 54 tests | `wasm/khostty-vt.wasm` is 813,670 B (795 KiB) built from `build.zig`; ESM loader, `Terminal`/`Snapshot`/`Search` API, complete `.d.ts` surface, smoke and ABI-export tests. |
| G8 Improvements + benchmarks | THIS WORK | `bench/` suite; see `README.md` here. |
| G9 Docs + packaging | IN PROGRESS | Per-platform docs landed; packaging tasks open. |
| G10 Release artifacts | NOT STARTED | blocked on G9. |

## What the benchmarks prove about the fork

Measured 2026-09-17 against the sibling upstream checkout
(`4c52de80a`, 2026-08-05) with both libraries built `-Doptimize=ReleaseSafe`,
interleaved in two passes on the same machine. Full numbers and caveats in
`README.md` in this directory.

Consistent directional results in **both** passes:

| Dimension | Khostty | Upstream snapshot | Direction |
|---|---|---|---|
| Snapshot encode, 80x24 | 0.222-0.255 ms | 0.828-0.932 ms | 3.4-4.1x faster |
| Snapshot encode, 200x50 | 0.340-0.404 ms | 1.294-2.073 ms | 3.8-6.1x faster |
| Resize, 200x50 + 10k lines | 5.2-11.0 ms | 22.4-26.4 ms | 2.0-5.0x faster |
| Empty resize rate | 21,680-22,367 /s | 12,060-13,083 /s | 1.7-1.9x faster |
| Library allocator bytes, 80x24 | 23,192 B | 29,906 B | 22.5% smaller |
| Library allocator bytes, 200x50 | 48,744 B | 68,084 B | 28.4% smaller |
| OSC-title ingest | 9.5-15.5 MiB/s | 6.3-6.9 MiB/s | 1.5-2.5x faster |
| Plain-text ingest | 40.9-69.1 MiB/s | 43.3-65.4 MiB/s | no signal (order flips) |
| Grid page memory | 13.98 / 34.82 MiB | 14.09-14.11 / 34.93 MiB | within 1% |
| Snapshot size | 155,728 / 156,083 B | 155,792 / 156,147 B | within 0.04% |

**Attribution caveat, stated plainly:** none of those improvements are fork
work. Khostty does not touch the VT core, and the compared checkout is 41 days
older than Khostty's base (`d4c88d806`, 2026-09-15). The deltas are upstream's
own progress during those weeks, which the fork carries forward. Measuring
against `d4c88d806` is the way to isolate a fork-specific delta, and that
measurement is documented as open work in `README.md`.

What the numbers therefore establish is the claim the fork can actually make:
**Khostty carries a newer upstream engine and does not regress it.** All
measured directions are favourable or neutral; grid memory and snapshot size
are within 1% and 0.04%.

## Capabilities upstream could not be measured on

The scrollback search API is a working Khostty capability with measured cost,
and the compared upstream revision cannot be measured on it at all: it does not
export `ghostty_search_new` or any other `ghostty_search_*` symbol, so
`bench/build.sh` substitutes a stub and section 8.4 records "unavailable"
rather than inventing a number.

Measured on Khostty (10,000 records, ~20,000 retained rows):

| Path | Cost |
|---|---|
| Cold full scan, fresh needle | 243-352 ms |
| Full rescan with a changed needle | 301-310 ms |
| Warm re-run, same needle (results retained) | 0.51-0.53 ms |
| Cost per retained row | 12.1-17.6 us |

That split matters for embedders: a find bar that keeps its search object and
needle pays half a millisecond per frame, but opening a new query costs a
quarter to a third of a second over a 10k-line scrollback and belongs on a
background thread driven by `ghostty_search_tick()`.

## Engagement notes worth keeping

1. **Optimization mode is the first thing to check when comparing libraries.**
   The first upstream comparison in this session was invalid: a plain
   `zig build` in the upstream checkout defaults to **Debug**, and the suite
   ran ~50x slower. A `sample(1)` of the stalled process showed the only
   active thread accumulating 34 s of CPU in 7 minutes of wall clock, with the
   hottest stack `terminal.page.Page.verifyIntegrity` called from
   `terminal.PageList.grow` on every page grow. The
   harness reports `library_optimize` and `library_sha256` from
   `ghostty_build_info()` and the linked file specifically so this cannot go
   unnoticed.
2. **Intensity of use**: the `200x50` + 10k-line reflow path and cold
   scrollback search are the two operations with real cost. Everything else
   measured is sub-millisecond to low-milliseconds.
3. **No leaks**: after `ghostty_terminal_free()`, allocator residual is 0 B and
   anonymous memory returns to baseline in all four memory scenarios.

## Open work that would strengthen this gate

1. Measure against Khostty's exact base (`d4c88d806`) to attribute deltas to
   the fork. Exact commands are in `README.md`.
2. Re-run on a quiet machine: the passes here ran at load average 548-674 on a
   10-CPU machine, which inflates absolute values and widens throughput spread.
3. Wire `conformance/` and `bench/` into CI so both become regression gates
   rather than point-in-time evidence.
4. Investigate the slow full scan (12-18 us per retained row) and the
   superlinear step between 2,000 and 5,000 records in the scaling sweep. Both
   are upstream engine behaviour, so any fix belongs upstream rather than in
   the fork.
