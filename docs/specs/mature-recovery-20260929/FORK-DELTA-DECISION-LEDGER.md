# Khostty fork-delta decision ledger — pass 1

Observed 2026-09-29. Frozen Khostty source: `a29aa9c6553d9f42aa68e2919116c0f6d53f329d`. Upstream comparison executed against current `ghostty-org/ghostty:main` base commit `f9e82709360d97b2246718f774c544de0f16787b`; merge base `d4c88d8069912b653d707191388ca98e24751f12`. Khostty is 207 commits ahead and 145 behind that upstream ref. This comparison is a research snapshot, not a promise that current upstream is the correct compatibility baseline for every historical Khostty change.

## Owned-delta decomposition

The GitHub compare shows the fork delta is multi-subsystem. Treating the repository as “agent IPC” is false.

| Delta family | Evidence in compare/current docs | Product role / status | Bootstrap decision |
|---|---|---|---|
| Terminal core/parser/render semantics | Fork policy says keep upstream core pristine; current official Ghostty exposes libghostty and GUI consumers | Commodity inherited core | USE/track upstream; reject custom rewrite |
| Conformance harness | `conformance/` added; historical 84-case gate | Verification infrastructure, potentially reusable outside fork | KEEP concept; prove it catches relevant upstream/fork regressions and can run against pinned upstream without requiring a broad fork |
| Windows application runtime | `src/apprt/windows/`, build/runtime work; current docs admit GUI App/windowing remains unimplemented despite CLI/DLL evidence | Candidate Khostty differentiation | EXPERIMENT before commitment. Compare current upstream/libghostty host path and maintenance burden; do not call Windows app complete |
| Agent IPC | `src/apprt/ipc/`, protocol/server/host; protocol says not app-started | Candidate integration, currently unmounted | CONTESTED. Compare Ghoztty/WezTerm/kitty; retain only accepted missing semantics |
| Rust/Go/Python/WASM wrappers | `khostty-vt/`, `khostty-go/`, `khostty-python/`, wasm/package work | Packaging/embedding candidate | Compare to upstream libghostty C API + generated bindings. Manifest-driven ABI idea may be transferable without terminal fork |
| ABI/type manifest | Fork docs describe `ghostty_type_json` target ABI metadata | Potentially genuine reusable improvement | Isolate exact source delta and upstream equivalent; consider upstreamable/thin companion rather than fork-only feature |
| Benchmarks | `bench/` and historical result artifacts | Verification, not product feature | KEEP only revision-pinned controlled runs; historical loaded/dirty runs are non-qualifying |
| Packaging/release/docs/CI | Large fork-owned docs/workflows/installers | Operational burden and support surface | Evaluate per accepted distribution. Do not treat documentation volume as product differentiation |
| Upstream lag | compare: 145 commits behind current upstream | Transition/maintenance debt | Must be measured continuously; each retained fork delta needs merge-conflict/semantic drift ownership |

## Strongest alternative architectures

**A. Upstream Ghostty/libghostty + thin host/control adapter.** Official Ghostty describes libghostty as the cross-platform C-ABI core used by native GUIs, and Ghostling demonstrates a minimal terminal host. This is the default architecture to beat for embedding/new-host needs.

**B. Ghoztty-class thin Ghostty fork.** External prior art adds Unix-socket agent window/split/close control and idempotent named targets while otherwise staying a Ghostty fork. It directly contests the proposition that a broad fork is necessary for coding-agent pane orchestration.

**C. Existing programmable terminal.** WezTerm CLI already creates targeted splits with cwd/program, returns pane IDs, sends child input and retrieves screen/scrollback. If the accepted need is agent control rather than Ghostty-specific UX/core, this is the strongest “product absent” baseline.

## Existence decision is subsystem-specific

The evidence does **not** justify either “delete Khostty” or “keep all of Khostty.” The defensible decision unit is each owned delta.

A retained delta must name: accepted user journey; upstream/alternative gap; exact source ownership; platform/configuration; independent witness; maintenance/merge cost; reversibility. If conformance or ABI-manifest work is valuable independently, it can survive even if agent IPC moves to a thinner architecture. If Windows native hosting is the actual differentiator, it must be judged separately from IPC.

## Required bake-off

Run the same K-J-AUTOMATE fixture against Khostty and the strongest viable alternative: create targeted child with known cwd → nonce child input → independent child receipt → inspect screen → focus/target → controller replacement → stale target rejection → close. Record LOC/delta, platform availability, security/authorization, identity semantics, recovery, maintenance and exact candidate revisions.

For embedding, run K-J-EMBED separately against Khostty wrapper and upstream libghostty/Ghostling-style host: create terminal → input/output → resize → snapshot/render/search as applicable → callback/thread ownership → free under sanitizer/instrumentation. Do not average desktop automation and embedding into one winner.

## Current architectural recommendation status

No architecture is frozen. The burden has shifted: **broad fork ownership is not the default assumption.** Preserve upstream core and prefer thin, composable deltas unless the Windows/embedding/ABI experiments demonstrate obligations that cannot be met cleanly otherwise.
