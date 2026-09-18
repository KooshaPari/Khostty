# Khostty — Product Dossier

**Gate:** G9.10 (product dossier per the Phenotype docs-3 contract)
**Observed:** 2026-09-18 · **Repository:** `Phenotype/repos/khostty`, branch `main`
**Precedence:** this file summarizes. `docs/` is canonical and `docs/sessions/`
holds dated evidence. Where this dossier and the tree disagree, the tree wins and
this file is wrong.

Status vocabulary (as in `docs/README.md`): **DONE** · **IN PROGRESS** ·
**SCAFFOLD** · **NOT STARTED** · **UNKNOWN**.

---

## 1. Product identity

| Field | Value | Evidence |
|---|---|---|
| Product name | **Khostty** | `docs/README.md` |
| Khostty version | **0.1.0** (source value `0.1.0-dev`) | `build.zig` → `lib_version` |
| ABI soname | `libghostty-vt.0.1.0.dylib` / `.so` / `.a` | `packaging/version.sh`, `zig-out/lib/` |
| Upstream base | **Ghostty 1.3.2-dev** | `build.zig.zon` → `.version` |
| Minimum Zig | 0.16.0 | `build.zig.zon` → `.minimum_zig_version` |
| Version scheme | `<major>.<minor>.<patch>[-pre][+ghostty.<base>.<sha7>]` | `packaging/version.sh`, WBS 10.1 |
| Manifest agreement | Rust `Cargo.toml` = 0.1.0 · Python `pyproject.toml` = 0.1.0 | observed 2026-09-18 |
| Lifecycle | pre-1.0; **no release produced** — G10 NOT STARTED, nothing published | WBS gate index |
| Upstream | fork of [`ghostty-org/ghostty`](https://github.com/ghostty-org/ghostty) | `docs/FORK.md` |

Khostty deliberately does **not** take the version of the Ghostty release it
tracks. `0.x` means the agent-facing surfaces (IPC v1, the polyglot bindings) are
not frozen. `lib_version` in `build.zig` is the single source of truth;
`packaging/version.sh` reads it and warns when the Rust or Python manifest drifts
away from it.

---

## 2. What it is

Khostty is the Phenotype fork of Ghostty: upstream's terminal emulator, terminal
core, and C library, plus four scoped deltas.

```
consumers   CLI (+new-window, +list-fonts, …)   agents (IPC)   embedders (C/Rust/Go/Python/JS)
                         │                          │                    │
                         ▼                          ▼                    ▼
layers      AppRT (src/apprt.zig: none|gtk|embedded|browser|ipc|windows)
            Agent IPC (src/apprt/ipc/: JSON over a local socket, 13 commands)
            Polyglot FFI (khostty-vt/, khostty-go/, khostty-python/, wasm/)
                         │
                         ▼
core        terminal engine (src/terminal/) — parser, screen, scrollback, search,
            snapshots, styles, selection, Kitty graphics. No platform calls.
                         │ exported as a C ABI
                         ▼
abi         libghostty-vt (include/ghostty/vt.h) — 203 GHOSTTY_API functions,
            34 headers → .a/.dylib/.so/.xcframework/ghostty-vt.wasm
```

The deltas, all confined to fork-owned directories:

1. **Windows application runtime** (`src/apprt/windows/`) — upstream has none.
   Cross-builds today; the runtime is still **SCAFFOLD**.
2. **Agent IPC v1** (`src/apprt/ipc/`) — line-delimited JSON, 13 commands, token
   auth. Modules implemented and unit-tested; **not yet constructed by a running
   instance**.
3. **Polyglot FFI** — Rust crate, Go module, Python package, WASM/ESM package,
   each wrapping the same C entry points and laying out structs from the
   `ghostty_type_json()` type manifest rather than hardcoded offsets.
4. **Conformance corpus** (`conformance/`) — 84 cases over 8 categories, the one
   gate with a fully independent, repeatable pass.

Explicit non-goals: rewriting the parser; diverging from upstream UX; modifying
`src/terminal/`, `src/renderer/`, `src/font/`, `src/config/`; claiming performance
superiority without a baseline; sending agent-authored PRs upstream. Details:
[`docs/FORK.md`](../FORK.md).

---

## 3. Platform support matrix

A row is **VERIFIED** only where this fork holds a dated observation. Upstream
capability and fork-verified capability are different claims.

| Platform | VT library | Terminal app | Agent IPC | FFI | Renderer | Verified in this fork |
|---|---|---|---|---|---|---|
| **macOS** arm64/x86_64 | **VERIFIED** (`-Demit-lib-vt`, ReleaseSafe) | Upstream AppKit (Xcode-driven) | v1 modules; no server constructed | C, Rust, WASM | Metal, else **OpenGL fallback** (`9d32ffc4c`) | **YES** — 2026-09-16/17 |
| **Linux** x86_64/arm64 | Upstream supported | Upstream GTK4 (`zig build run`) | same | C, Rust | OpenGL | **NO** — never built or tested here |
| **Windows** x86_64 | Cross-build **PASS** | **SCAFFOLD only** | Named-pipe stub (`error.Unimplemented`) | C, Rust (Go cgo untested) | OpenGL (unproven) | **PARTIAL** — cross-compile only, never executed |
| **WASM** `wasm32-freestanding` | **VERIFIED** artifact | n/a (headless) | n/a | JS/TS | n/a | **YES** — Node tests; no browser run |
| **iOS** | xcframework slice present | Not supported | n/a | C | Metal | Artifact only, never built/run |
| **FreeBSD** | Upstream supported | Upstream GTK4 | same | C, Rust | OpenGL | **NO** |

Windows cross-build evidence (2026-09-17): `zig build -Dtarget=x86_64-windows-gnu
-Dapp-runtime=windows` exits 0 and produces `ghostty.exe`, `ghostty-vt.dll`,
`ghostty.pdb`; `zig build test-windows-apprt` reports 80/85 steps passing
(commit `2d11fcb3a`). That is compile-and-link evidence, **not** runtime evidence:
no Windows binary has been launched, natively or under Wine.

WASM artifact: 813,670 bytes, sha256 `08ac8ed881ffdae68b9f96f9afa6c834e57ba7ea49280d220e882938508e5bf6`,
189 exports, 0 imports. Per-platform detail: [`docs/PLATFORMS.md`](../PLATFORMS.md).

---

## 4. FFI surfaces

| Surface | Artifact | Recorded test evidence | Notes |
|---|---|---|---|
| C | `libghostty-vt` — 203 `GHOSTTY_API` functions, 34 headers | conformance **84/84** (`conformance/build.sh`, 2026-09-17) | Header self-describes as work-in-progress and unstable; pin a revision |
| Rust | `khostty-vt/` crate (bindgen: 198 functions, 179 types, 779 constants) | **199/199** (WBS G5 record, 2026-09-17); crate README records 195 = 65 unit + 130 integration at its own run | RAII `Terminal`, snapshot, render, search, key/mouse; `tests/abi_layout.rs` asserts layout against the type manifest |
| Go | `khostty-go/` cgo module | **207** combined Go+Python (WBS G6 record) | Author-verified `go build` / `go vet`; 45 top-level `Test*` functions present |
| Python | `khostty-python/` cffi package (v0.1.0) | same 207 figure; README records **98** pytest cases | Library discovery + bindings |
| WASM / JS-TS | `@khostty/libghostty-vt-wasm` (ESM, `wasm/`) | **54/54** (WBS G7 record); `npm test` = 54 runtime + ABI tests | Node ≥ 20; Kitty graphics excluded by design (needs OS timestamps) |

Design rule honoured by every wrapper (**wrap, do not reimplement**): no language
reimplements parser logic, and none hardcodes a target-dependent number.
`ghostty_type_json()` publishes pointer width, endianness, alignment, per-type
offsets, and enum values; the Rust and WASM layers assert against it, so a struct
change fails loudly instead of corrupting memory silently.

Reproduce the surface-level tests: `cargo test` (`khostty-vt/`), `go test ./...`
(`khostty-go/`), `pytest tests/` (`khostty-python/`), `npm test` (`wasm/`),
`conformance/build.sh run`.

---

## 5. Agent/IPC surface

Two distinct things share the name:

**Upstream channel — DONE, narrow.** `src/apprt/ipc/mod.zig` exposes exactly three
actions (`new_window`, `new_tab`, `toggle_quick_terminal`) as the CLI
`+new-window`, `+new-tab`, `+toggle-quick-terminal`. No pane addressing, no state
query, no event stream.

**Khostty agent IPC v1 — IN PROGRESS (reachability).** Normative spec:
[`src/apprt/ipc/protocol.md`](../../src/apprt/ipc/protocol.md).

| Dimension | Value |
|---|---|
| Transport | Unix domain socket — macOS `~/Library/Caches/khostty/ipc.sock`; Linux/BSD `$XDG_RUNTIME_DIR/khostty/ipc.sock` (fallback `/tmp/khostty-$UID/ipc.sock`); override with `KHOSTTY_IPC_SOCKET` |
| Windows transport | Named pipe, same framing: `\\.\pipe\khostty-{server_pid}` (SCAFFOLD, `error.Unimplemented`) |
| Framing | one JSON value per line, UTF-8, `\n`-terminated; 1 MiB max frame; responses in request order; unsolicited events allowed |
| Commands | 13 — `ping`; `pane.create` / `close` / `focus` / `list` / `write` / `state` / `search`; `resize_split`, `equalize`, `zoom`; `events.subscribe` / `unsubscribe` |
| Auth | token, fail-closed, constant-time compare |
| Modules | `protocol.zig`, `auth.zig`, `state.zig`, `events.zig`, `pane.zig`, `handler.zig`, `server.zig`, `app_host.zig`, `fake_host.zig` — 130 unit tests across the first seven per `protocol.md` |
| Not yet true | Nothing in a running runtime constructs the server (`grep` finds no `Server.init` outside its own test), and the Windows frame header (`extern struct { action: u16, length: u32 }`) predates the JSON draft and needs reconciling |

`pane.write` writes **VT bytes into the terminal parser**; it does not type into
the child process. That is a documented v1 non-goal, not a defect.

---

## 6. Build commands per platform

Prerequisites and troubleshooting: [`docs/BUILD.md`](../BUILD.md). All commands run
from the repository root; `zig` must be 0.16.0.

```sh
# macOS — VT library (static + shared)       [VERIFIED 2026-09-16 ReleaseSafe; rebuilt 2026-09-18 Debug]
zig build -Demit-lib-vt -Doptimize=ReleaseSafe

# macOS — xcframework (macOS + iOS slices)                     [VERIFIED 2026-09-16]
zig build -Demit-lib-vt -Demit-xcframework -Doptimize=ReleaseSafe

# macOS — application (Xcode-driven .app); skip with =false    [library path verified]
zig build -Demit-macos-app=true -Doptimize=ReleaseSafe

# Linux / FreeBSD — GTK4 application                          [NOT verified in this fork]
zig build -Doptimize=ReleaseSafe
zig build run

# Linux / Windows — cross-compiled VT library                 [Windows VERIFIED, Linux not]
zig build -Demit-lib-vt -Dtarget=aarch64-linux -Doptimize=ReleaseSafe
zig build -Demit-lib-vt -Dtarget=x86_64-windows -Doptimize=ReleaseSafe

# Windows — execute + link, with the Windows AppRT            [VERIFIED 2026-09-17, exit 0]
zig build -Dtarget=x86_64-windows-gnu -Dapp-runtime=windows
zig build test-windows-apprt        # host-runnable Windows runtime tests

# WASM — freestanding module                                  [VERIFIED artifact]
zig build -Demit-lib-vt -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall
cd wasm && npm run check            # header sync + typecheck + runtime/ABI tests

# Tests and packaging
zig build test-lib-vt               # targeted: -Dtest-filter=<name>
zig build test-lib-vt-schema        # ABI type manifest
conformance/build.sh run            # 84-case behavioural gate
packaging/linux/deb.sh              # .deb (probe PASS, 2026-09-17)
packaging/wasm-dist.sh              # WASM dist tarball
packaging/version.sh --json         # version + upstream base + manifest agreement
```

**macOS renderer caveat.** Recent Xcode ships the Metal compiler as a separate
component. `build.zig` probes `xcrun -sdk macosx metal --version` and, when the
toolchain is absent, **falls back to the OpenGL renderer with a warning**
(commit `9d32ffc4c`); `-Drenderer=metal` still forces Metal, and `SharedDeps` only
creates the metallib step when Metal is selected.

---

## 7. Known limitations

1. **Metal toolchain absent on this host.** Default macOS builds auto-fall back to
   the OpenGL renderer (commit `9d32ffc4c`; re-observed 2026-09-18 — the fallback
   warning is the only output besides success, exit 0). Consequence: no
   Metal-shader or Metal-rendering claim is supported here.
2. **Windows runtime is never exercised on real Windows hardware.** Cross-compile
   and link pass; no native or Wine launch, no glyph rendered, no clipboard, no
   window created. `App`/`renderer.zig` still return `error.Unimplemented`.
3. **Windows named-pipe transport is not usable as documented.** `PIPE_PREFIX`
   resolves to a single leading backslash (not the Win32 pipe namespace), the unit
   test asserts the same wrong value, and the pipe has **no ACL design**
   ([`docs/SECURITY.md` §4](../SECURITY.md)). Also `keyboard.zig` is 734 lines,
   over the repo's 500-line limit.
4. **Agent IPC v1 is not reachable.** All modules and 130 unit tests exist against
   `fake_host.zig`, but no runtime constructs the server, and `app_host.zig` is not
   wired into the build graph as a live host.
5. **Linux is unverified.** No Linux build, test, or GTK launch is recorded, and no
   CI job builds or tests Linux (the Ubuntu job runs `zig fmt --check` only).
6. **No usable benchmark comparison.** The `bench/` harness exists and produced one
   run on 2026-09-17, but the upstream baseline file is empty and the run happened
   at load average 425 on a dirty tree at `1e6687dd2`, which the harness's own
   methodology says makes the medians unreliable. **No performance claim is
   supported.**
7. **No release.** G10 NOT STARTED: no tag, no verified installer set, no published
   crates/PyPI/npm packages. G9 packaging is partial (Linux `.deb` and WASM dist
   exist; macOS `.app`, Windows installer, install docs do not).
8. **C ABI is explicitly unstable.** `include/ghostty/vt.h` states the API is
   incomplete and "definitely going to change". Consumers must pin a revision.
9. **Shared-library load caveat.** Nothing is defended by default: no OS sandbox,
   no SAST/secret scanning in CI, no recorded fuzz or sanitizer run, no per-pane
   token scoping or rate limiting ([`docs/SECURITY.md` §11](../SECURITY.md)).
10. **Build fragility under concurrent edits.** The tree was broken twice in one
    day on 2026-09-17 (`e1277bea2` import depths; an unhandled `Runtime.windows`
    arm), each time blocking every gate that needs a fresh `libghostty-vt`.

---

## 8. Quality evidence

Gate record: [`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](../sessions/20260916-fork-assessment/02_DEEP_WBS.md)
(113 tasks; 96 DONE / 17 pending as of 2026-09-17).

| Gate | Scope | Status | Evidence |
|---|---|---|---|
| G0 | Fork hygiene | **DONE** | Boilerplate CI stripped, Zig-aware `ci.yml`, Metal skip |
| G1 | Native build validation | **DONE** | macOS artifacts in `zig-out/lib/` (2026-09-16) |
| G2 | Conformance evidence | **DONE** | 84/84 across 8 categories, `conformance/build.sh` (2026-09-17) |
| G3 | Windows app runtime | **DONE** (cross-build) / runtime SCAFFOLD | `2d11fcb3a`: exit 0, `ghostty.exe` + `ghostty-vt.dll`; 80/85 `test-windows-apprt` steps |
| G4 | Agent/IPC surface | **DONE** | `src/apprt/ipc/`: 130 unit tests, spec `protocol.md`; reachability is the open item |
| G5 | Polyglot FFI — Rust | **DONE** | 199/199 tests (WBS record) |
| G6 | Polyglot FFI — Go + Python | **DONE** | 207 tests (WBS record) |
| G7 | WASM cross-compilation | **DONE** | 54/54 tests, 189 exports, artifact hash above |
| G8 | Improvements + benchmarks | **DONE** (measured, not comparable) | Harness built; upstream baseline empty — see limitation 6 |
| G9 | Documentation + packaging | **IN PROGRESS** (11/15) | `docs/` set, `.deb`, WASM dist; this dossier is 9.10 |
| G10 | Release artifacts | **NOT STARTED** | — |

Verification rules the fork holds itself to: every status claim carries an
observation date; a historical pass is not a fresh pass; a percentage needs an
observed denominator; **UNKNOWN** is preferred over an inference.

**Current tree build (observed 2026-09-18, this host).** The 2026-09-17
"committed revision does not build" reports in `docs/BUILD.md` §11 are
**superseded**: `cd1ed5c60` fixed the `src/apprt/ipc/mod.zig` import depths, and
`9d32ffc4c` handles the Metal fallback. Re-verified here:
`zig build -Demit-lib-vt` (Debug) exited **0** after 2m30s, emitting only the
OpenGL-fallback warning, and produced fresh `zig-out/lib/libghostty-vt.a`
(21,851,904 B) and `libghostty-vt.0.1.0.dylib` (7,685,808 B). Debug artifacts are
larger than the 2026-09-16 ReleaseSafe pair (1,323,002 B / 2,215,792 B), so the
sizes are not comparable across the two rows.

**Not yet re-verified as of this observation:** the conformance suite against the
fresh library, the test suites of the four FFI surfaces, `test-windows-apprt`, and
any build on Linux. Each of those carries its dated result above and nothing
fresher.

---

## 9. Top 5 risks

| # | Risk | Evidence | Mitigation / next action |
|---|---|---|---|
| 1 | **The headline delta (Windows) never reaches runtime.** Spec, scaffold, cross-build and keyboard mapping exist, but no Windows binary has been launched on Windows hardware. | `docs/PLATFORMS.md` §5; G3 G3 exit criteria unmet (no window, no DirectWrite glyphs, no clipboard) | Run `ghostty.exe` on a Windows host or under Wine; record dated output; that result is what unblocks the value claim |
| 2 | **Windows IPC authorization hole.** Malformed pipe path (single leading backslash) plus no DACL design; the unit test encodes the same wrong value, so it cannot catch it. | `docs/SECURITY.md` §4; `src/apprt/windows/ipc.zig` | Fix the constant and its test; design an explicit DACL before G3/G4 converge; do not ship an unauthenticated pipe |
| 3 | **ABI/version drift across four language surfaces.** Upstream calls the C ABI unstable; a wrapper with a stale layout corrupts memory silently. | `include/ghostty/vt.h` warning; `docs/ARCHITECTURE.md` §4 | Keep `ghostty_type_json()` as the only layout source (already asserted by Rust/WASM); run `packaging/version.sh` agreement checks in CI; pin revisions |
| 4 | **No defensible performance or comparison claim.** Benchmarks exist but the baseline is empty and the only run was at load 425 on a dirty tree. | `docs/FORK.md` §4; `bench/results/upstream-20260917.txt` = 0 bytes | Re-run paired Khostty-vs-upstream on an idle machine, pinned to a committed revision; publish only then |
| 5 | **Gate progress outruns verification, and CI cannot catch regressions.** Gate labels say DONE while runtime behaviour is unobserved; CI builds only macOS lint plus one macOS build, and 12 inherited upstream workflows are ungated. | `docs/README.md` status caveat; `docs/CONTRIBUTING.md` §9; `docs/BUILD.md` §11 (tree broken twice on 2026-09-17) | Add a Linux build+test job; guard or delete the ungated upstream workflows; keep the "SCAFFOLD vs DONE" distinction visible in every superseding doc |

---

## 10. Ownership and next handoff

Recorded 2026-09-18. This section exists because the docs-5 dossier template requires an
ownership/next-handoff concern and the earlier revision had none. Nothing here is inferred
from convention; where a name is absent, that absence is the finding.

| Role | State |
|------|-------|
| Product owner | **UNASSIGNED.** No per-product owner is recorded in this repository. Commits carry `tx-agent` trailers identifying the tool (`jcode`, `human`), not a person accountable for the product. |
| Independent assurance owner | **UNASSIGNED.** The G2 conformance run (84/84) and the G3 apprt run (25/25) were produced in the same working session that produced the code under test. They are executed evidence, but they are **not independent verification** — no separate party has reproduced them. |
| Release authority | **Not established.** WBS G10 (9 tasks) is NOT STARTED. Publishing, tagging, and artifact distribution have not been authorised or performed. |

### Named next bounded task

**Close WBS 9.11 — the macOS `.app` bundle — on a host where the Metal toolchain is available.**

- Artifact: `zig-out/Ghostty.app`, produced by `packaging/macos-app.sh` (now tracked).
- Proof required: `packaging/macos-app.sh --probe` reports `metal compiler: usable`, then
  `--probe` → build → `codesign --verify` → launch, with the `.app` copied outside the source
  tree before launching.
- Why it is bounded: the blocker is external and singular. On this host
  `xcrun -sdk macosx metal --version` exits 1 and
  `xcodebuild -downloadComponent MetalToolchain` cannot fetch the catalog for Xcode 26.0 build
  17B5050g. On a host where that command succeeds, the build path is already wired.
- Why it is next: it is the only remaining item in G9 and the only thing gating a full G9 pass.
  It unblocks nothing else, so it is deliberately not treated as urgent.

Everything else in this dossier is either verified with a dated command (see §8) or explicitly
marked unverified.

## See also

- [`docs/README.md`](../README.md) — entry point and status table
- [`docs/ARCHITECTURE.md`](../ARCHITECTURE.md) — layer stack and fork surface discipline
- [`docs/PLATFORMS.md`](../PLATFORMS.md) — per-platform support matrix
- [`docs/FORK.md`](../FORK.md) — what the fork adds, and what the evidence does not support
- [`docs/BUILD.md`](../BUILD.md) — build commands and troubleshooting
- [`docs/AGENT.md`](../AGENT.md) — driving Khostty from an agent
- [`docs/SECURITY.md`](../SECURITY.md) — trust boundaries and undefended surfaces
- [`src/apprt/ipc/protocol.md`](../../src/apprt/ipc/protocol.md) — normative IPC v1 spec
- Dated evidence: [`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](../sessions/20260916-fork-assessment/02_DEEP_WBS.md)
