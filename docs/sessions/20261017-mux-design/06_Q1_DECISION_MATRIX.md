# Q1 Decision Matrix — Phase 1 Windowed Runtime

**Repo:** `/Users/kooshapari/CodeProjects/Phenotype/repos/khostty`
**Date:** 2026-10-17
**Author:** VP-Eng (jcode orchestrator, tier-0 M3) — decision-matrix writer lane
**Status:** draft for operator decision

**Companion documents:**
- [`20261017-FWD-PATH.md`](../../audits-archive/2026-10-17-final/FWD-PATH.md) §4 (Phase 2 — Phase 1 mux shell, blocked on this decision)
- [`20261017-FINAL-AUDIT.md`](../../audits-archive/2026-10-17-final/FINAL-AUDIT.md) §8 row Q1
- [`20261017-mux.md`](../../audits-archive/2026-10-17-final/mux.md) §5 (Phase 1 design sketch) + §8 #3 (gap: embedded-on-macOS feasibility unverified)
- [`20261017-state.md`](../../audits-archive/2026-10-17-final/state.md) §3.2 (runtime table) + §8 #1 (the `windowed` gate is the real fork boundary)

**Binding (operator 2026-10-15):** FORK-ONLY. No `gh pr/issue/discussion create` or `gh api POST/PATCH/DELETE` against `ghostty-org/ghostty` or any other upstream repo. Reading, copying, tracking, `zig build` against upstream: fine. Push to `KooshaPari/*`: fine.

**File status (binding rule #10):** This file lives under `docs/sessions/`, which is **tracked**. It may be staged and committed normally.

---

## §1. TL;DR

**Pick option (c) — mock-only prototype, defer real runtime to a later release.** Confidence: **medium-high**.

The agent-IPC story is already shippable as a library-first 0.1.0 (Rust + WASM + macOS app + upstream CLI IPC). The Phase 1 mux shell is a *new capability* that the operator has not asked for in the current "as close to finish as possible" scope, and the only path that does not depend on operator infra (a Linux box with GTK, option (a)) or on a missing feasibility audit (option (b)) is option (c) — which validates the architecture without betting on a runtime.

Rationale (3 lines):
1. **Operator infra is the binding constraint, not design.** macOS host cannot build GTK; Tailscale `kooshapari-desk` is offline (no remote Linux box reachable); the build host is at 96–98% disk (state §7). Option (a) requires new infra. Option (b) requires a 1d audit (`01_EMBEDDED_AUDIT.md`, which does not yet exist) and is unproven. Only option (c) lands without operator-owned prerequisites.
2. **Phase 1 design tasks (C1–C5) are NOT blocked by Q1.** 2d of audit + docs + mock skeleton can run today. The gate is *Phase 1 implementation* (Phase D, 1w+), which is gated by Q1 *and* by the Phase B GTK wireup that is already in flight on `khostty-phase-b-gtk-spec-20261017`.
3. **Option (c) is reversible.** If the operator later lifts Q1 in favor of (a) or (b), the mock skeleton becomes the architecture reference and the routing-table unit tests survive intact. Reversing (a) (a GTK-only Phase 1) onto a fork that suddenly wants macOS-native panes is far harder.

---

## §2. Options compared

| Dimension | (a) Linux box + GTK | (b) `embedded.zig` surface-within-surface on macOS | (c) Mock-only prototype, defer real runtime |
|---|---|---|---|
| **Effort to enable** | ~3d: 1d Linux host + GTK build infra, 1d Phase C1/C2/C3 audits, 1d Phase C4 architecture + C5 mock | ~3d: 1d C1 audit (missing), 1d C2/C3, 1d C4 architecture (Phase D work same) | **1d**: C5 mock skeleton + C4 architecture doc; C1/C2/C3 can be done as docs-only on the side |
| **Risk** | **High** — depends on operator-owned infra + a Linux GTK runner that does not currently exist. Build host at 96–98% disk (state §7). If GTK build is broken upstream, fork cannot validate. | **Medium-high** — `embedded.zig` is 2,576 lines of C-callconv AppKit glue designed for "embedded within a parent host" (per file header). Re-embedding Khostty's `embedded App` inside itself to host multiple panes is architecturally plausible but **unproven**. Surface creation API + lifecycle are not documented. | **Low** — no runtime integration, no host infra. `fake_host.zig` (446 lines) already exists as the test-only IPC backend; C5 reuses its pattern. Risk is "throwaway work if the operator later picks (a) or (b)", which is mitigated because the routing table + command surface survive intact. |
| **Capability delivered** | **Real Phase 1 mux shell**: agents can connect to `khostty-mux.sock`, fan out to per-instance `khostty.sock`, render real panes via GTK, route keyboard focus, persist layouts. GTD/E2E acceptance per mux §5 is met. | Same surface, rendered via AppKit inside AppKit. **Same GTD/E2E acceptance**, plus a macOS-developer-loop advantage (the operator can iterate on their own host). | **Compile-checked skeleton only**: routing table type, command dispatch, `mux.list`/`mux.focus`/`mux.attach`/`mux.detach`/`mux.layout.save`/`mux.layout.restore` as wire types + unit tests against `fake_host.zig`. **No real panes, no real keyboard routing, no real layout persistence against a running host.** |
| **Reversibility** | **Low** — Phase D work locks the fork onto GTK as the Phase 1 runtime. Lifting this later to macOS-native panes would discard GTK-specific code paths. | **Medium** — same risk in the other direction (locked onto `embedded.zig`); lifting to GTK would discard the embedded-host harness. | **High** — the mock skeleton is an architecture reference, not a runtime. The fork's Phase 1 architecture doc (C4) can target any runtime without rewriting the routing layer. |

### Operator burden (5-axis summary)

| Burden | (a) | (b) | (c) |
|---|---|---|---|
| **Time to enable** | ~1d operator time: provision Linux box + GTK + SSH access. Plus dev iteration after. | ~5m operator time: read C1 audit, accept/extend the embedded surface API as the Phase 1 presenter. | **~5m operator time**: read this doc, pick (c), unblock Phase C. |
| **Money / infra cost** | Linux box rental or re-purposed hardware; ~$5–20/mo for cloud; or a spare physical box. | Zero. macOS-only. | Zero. |
| **Cognitive load** | Operator learns GTK debug loop + Linux build environment. | Operator reads `embedded.zig` C-callconv (2,576 lines) to sign off on surface-within-surface. | Lowest. Mock-only is operator-readable in 5m. |
| **Schedule risk** | Highest — depends on infra availability, GTK build stability, fork-disk-pressure headroom. | Medium — depends on whether C1 audit says "yes". | Lowest — no infra, no audit gate. |
| **Future-proofing** | Locks onto GTK. Future macOS-native panes require option (b) work later. | Locks onto AppKit. Future GTK-native panes require option (a) work later. | None locked. Future option-pick is open. |

---

## §3. Decision criteria

The operator should consider these in order. Each is binary or near-binary; weigh in the listed priority.

1. **Is "Phase 1 mux shell" in scope for the current "as close to finish as possible" goal?**
   The operator scope per FWD-PATH §1: "Bring the project as close to finish as possible" — EXCLUDING scaling, sunset, user feedback, intent evolution. **Phase 1 is not in the operator-asked scope** (it is a Phase 2 / Phase D deliverable per FWD-PATH §4). It is also not in the MVP (per FINAL-AUDIT §5: "a developer can consume today" is `cargo add khostty-vt` + WASM + macOS `.app` + upstream CLI IPC). If "finish" is the goal, Phase 1 implementation is **out of scope by definition**, and the question collapses to: do we want to start it?

2. **Is a Linux box with GTK available *and reachable* from the build host?**
   State §7: Tailscale `kooshapari-desk` offline 2026-10-15, last seen 2 days ago, no remote wake. The r4 WSL sync is blocked. If option (a) is selected, the operator must first provision and connect a Linux host — that is a real ops prerequisite, not a "later today" item.

3. **Is `embedded.zig` actually able to host multiple panes?**
   Per mux §8 #3, this is a documented gap. `embedded.zig` exists at 89,852 bytes per state §3.2 (or 2,576 lines per a fresh `wc -l`); it is a C-callconv AppKit glue layer designed for *single-embedded-instance* use (file header: "embedded within a parent host application, rather than owning the application lifecycle itself"). Re-embedding Khostty's embedded App inside itself to host multiple panes is a hypothesis. **Until C1 audit lands, option (b) is conditional on a feasibility audit the fork has not yet performed.**

4. **Does the operator value a working demo on macOS over a working demo on Linux?**
   The two paths deliver different surfaces. (a) delivers a Linux GTK binary; (b) delivers a macOS AppKit binary. If the operator's test audience is macOS-native, (b) is the right answer *if* C1 says yes. If the audience is cross-platform or CI-driven, (a) is the right answer.

5. **Does the operator want to keep Phase 1 architecture open until Phase 2 design lands?**
   Phase 2 (durable sessions + `pane.execute` pty injection) is not designed (state §8 #9). The Phase 1 lock-ordering contract (carry-forward #23, the highest-risk design decision in Phase 1 per mux §5 risk #2) composes with Phase 2's pty-injection needs. Picking a runtime today means committing to a lock-ordering shape that Phase 2 may not survive. Option (c) defers that commitment by 1–2 weeks of Phase 2 design work.

---

## §4. Per-option deep dive

### Option (a) — Linux box with GTK

**Plain language:** Stand up a Linux machine (or a cloud VM) with GTK + Zig 0.16.0 + the fork's build dependencies. Build `khostty` with `-Dapp-runtime=gtk`. Wire Phase B (B1–B5) into the GTK runtime. Build `khostty-mux` against the GTK runtime. The agent connects to `khostty-mux.sock`; the mux fans out to per-instance `khostty.sock` over Unix sockets; panes are real GTK windows; keyboard focus routes via GTK's event system.

**What unlocks (Phase D scope):**
- Phase B finish (B1–B5: GTK `Server.bind`, `pane.write` mailbox hop, event publish hooks, snapshot counters, `max_connections`/rate limit) — the actual G4 finish line, carry-forward #5–#9.
- Phase D implementation (1w+): `khostty-mux` binary, fan-out to per-instance sockets, new commands `mux.list`/`mux.focus`/`mux.attach`/`mux.detach`/`mux.layout.save`/`mux.layout.restore`.
- E2E acceptance per mux §5: agent connects to mux, `mux.list` returns multiple instances, `mux.focus` routes keyboard, `mux.attach` survives client disconnect.

**What's blocked (what can't ship until it lands):**
- Operator host is macOS-only. macOS cannot build GTK (per state §3.0). So GTK-on-Linux must be a *separate host*. The build host is at 96–98% disk (state §7); a Linux VM with full Zig build cache needs ~30 GB free for cold-cache (`zig build` 27–30m cold-cache per state §1).
- Phase B1 (`Server.bind` from GTK App.zig) requires reading 28 files in `src/apprt/gtk/` (per FWD-PATH §3) to find the lifecycle hook called after the GTK loop is up. The wire-up spec is already drafted on `khostty-phase-b-gtk-spec-20261017` (Phase B GTK spec, 1,411 lines) but implementation is not started.
- Tailscale `kooshapari-desk` is offline (state §5 #8); there is no known-reachable Linux host today. The operator must provision + connect one.
- `ci/zig-fork-tests.yml` does NOT include a GTK-side harness (state §8 #3). It runs `test-windows-apprt` + `test-agent-ipc` only. The Phase 1 E2E acceptance requires GTK to *run* (not just compile). The CI gap must be closed too.

**Operator time / cost to enable:**
- ~1d operator time to provision a Linux box (or accept a free-tier cloud VM), install GTK + Zig 0.16.0, configure SSH access from the macOS build host. **~$5–20/mo cloud cost** or a re-purposed physical box.
- ~5m per Phase B iteration after the box is up.
- ~30m cold-cache build per GTK regression. Disk headroom matters.

**Risk of regret:**
- **High.** If upstream GTK moves break the fork, the entire Phase 1 effort is blocked until upstream fixes land. The fork is 366 commits behind upstream (state §2), and upstream GTK can change in ways that do not break Zig builds but do break runtime behavior.
- If the operator later wants macOS-native panes, the GTK work is sunk cost. (You can lift a runtime, but you cannot lift a codebase.)
- Disk pressure is real. A 30 GB Linux build cache + GTK runtime libraries + the existing macOS build cache will exceed 96% disk on the operator's build host.

---

### Option (b) — `embedded.zig` surface-within-surface on macOS

**Plain language:** Audit `src/apprt/embedded.zig` to verify it can host multiple `CoreSurface` instances within a single `embedded App` host. If yes, write a new Zig binary (`khostty-mux`) that re-embeds Khostty's `embedded App` *inside itself*, owns multiple `Surface`s, and exposes them via the same `protocol.zig` + `auth.zig` wire types as the GTK path. The agent connects to `khostty-mux.sock`; the mux fans out to per-instance `khostty.sock`; panes are AppKit `NSView`s owned by the mux's `embedded App`.

**What unlocks (Phase D scope):**
- All of Phase D implementation (same as option (a)), but the dev loop runs on macOS — the operator's actual host.
- The agent-IPC G4 finish line (Phase B wire-up) becomes reachable on macOS without GTK, because the vtable bodies that fire `error.Unsupported` under `.embedded` would be re-implemented (or partially replaced) by the mux's `embedded App` host. This would mean **Phase B is partially obviated**, since the mux binary IS the runtime.
- E2E acceptance per mux §5, on the operator's own host. Dev iteration is fast (no remote Linux box, no SSH, no Linux GTK debug loop).

**What's blocked (what can't ship until it lands):**
- **C1 audit (`01_EMBEDDED_AUDIT.md`) does not exist on disk.** `find . -name '01_EMBEDDED_AUDIT.md'` returns 0 hits. The audit must answer whether `embedded.zig`'s lifecycle can host multiple `CoreSurface` instances and whether the surface-creation API is exposed for the mux to call. Without this audit, option (b) is conditional on unverified feasibility.
- `embedded.zig` is upstream code (89,852 bytes / 2,576 lines, C-callconv). The fork does not own it. Any fix to support multi-pane embedding would either (i) live in a fork-only file (a wrapper), (ii) require upstream coordination (out of fork-only scope per binding rule), or (iii) be implemented as a thin orchestrator that calls the public `App.Options` API without modification. Option (iii) is the only feasible fork-only path, and it has not been audited.
- The Phase C work that option (a) needs (Phase B wire-up) is **not obviated** for option (b) — `khostty-mux` still needs to bind the existing per-instance `khostty.sock` (which itself requires the Phase B wire-up). Option (b) only obviates Phase B if the mux binary fully replaces the per-instance runtime. That is a much bigger scope.
- macOS AppKit threading semantics differ from GTK; the Phase 1 lock-ordering contract (carry-forward #23) will need a macOS-specific composition. This is real design work, not a re-skin.

**Operator time / cost to enable:**
- ~5m operator time to approve the audit's findings once C1 lands.
- ~1d of agent time to perform C1 audit (the audit is not yet on disk; it is its own 1d task per FWD-PATH §4 Phase C).
- **~$0 / zero infra cost** if C1 says yes.
- ~5–10m per Phase D iteration once the audit clears.

**Risk of regret:**
- **Medium-high.** The fork is locked onto AppKit as the Phase 1 runtime. Future GTK-native panes require option (a) work later.
- The audit is the gating risk. If C1 finds that `embedded.zig` *cannot* host multiple panes (e.g., lifecycle assumes a single `Surface` per `App`, which is plausible for an embedded resource API), the option collapses to either (c) or (a), and 1d of audit time is sunk.
- The "embedded App inside an embedded App" pattern is unconventional and may surface downstream issues (NSApplication lifecycle, focus stealing, modal dialog ownership) that are not visible until Phase D work begins.

---

### Option (c) — Mock-only prototype, defer real runtime

**Plain language:** Land Phase C only (C1–C5 from FWD-PATH §4): 2d of audit + docs + a compile-checked `mux_shell.zig` skeleton that reuses `fake_host.zig` as the IPC backend. The skeleton validates the routing-table type, the new command wire types, and the lock-ordering contract without binding any runtime. Do not start Phase D. Defer the real runtime decision to a later release.

**What unlocks (Phase D scope, deferred):**
- A documented Phase 1 architecture (C4 doc) that any future Phase D implementation can target.
- A routing-table unit-test suite (C5 mock) that survives intact when Phase D lands, regardless of which runtime is chosen.
- The Phase C design artifacts (mailbox integration 1-pager, event-hook insertion map, `embedded.zig` audit, lock-ordering contract) are prerequisites for *both* option (a) and option (b) — they are reusable.

**What's blocked (what can't ship until it lands):**
- Real Phase 1 mux shell binary. Agents cannot connect to `khostty-mux.sock`. No E2E acceptance per mux §5 is met.
- The Phase B GTK wire-up (B1–B5) is *not* blocked by Q1; it has its own runtime prerequisite (a Linux GTK host). Option (c) does not change Phase B status.
- The "agent drives a GUI terminal" CVP item stays at 11/13 commands (`pane.focus` and `pane.search` remain `error.Unsupported` on GTK per `app_host.zig:177-178`; the GTK path is not even attempted under option (c)).

**Operator time / cost to enable:**
- **~5m operator time**: read this doc, pick (c), unblock Phase C. No infra. No Linux box. No audit. No C1 dependency.
- **~$0 / zero infra cost.**
- 2d of agent time to land Phase C.

**Risk of regret:**
- **Low.** The mock skeleton is reversible. Phase C design artifacts (mailbox 1-pager, event-hook map, lock-ordering contract) are reusable regardless of future Q1 outcome.
- The risk is *missed opportunity*: if the operator had chosen (a) or (b), Phase D would have started. Option (c) defers Phase D by the time it takes to re-decide Q1 (estimate: 5m operator time + 1d of audit work if (b), or 1d of infra setup if (a)).
- The risk is *also* "Phase 1 never happens" — if the operator's "as close to finish as possible" goal is interpreted strictly, Phase 1 is out of scope anyway, and option (c) is the right answer because it lands the Phase 1 *architecture* without committing to Phase 1 *implementation*.

---

## §5. Recommendation

**Pick option (c).** Defend:

- **It matches the operator's stated scope.** "Bring the project as close to finish as possible" (FWD-PATH §1) does not include Phase 1 implementation. Phase 1 is a *new capability*, not a finish-line polish item. Option (c) lands the Phase 1 architecture (a finish-line doc + a compile-checked skeleton) without starting a 1w+ Phase D build that the operator has not asked for.
- **It does not depend on operator infra.** Option (a) needs a Linux box; option (b) needs an audit. Option (c) needs neither. The Tailscale `kooshapari-desk` host is offline (state §7); provisioning a fresh Linux host is a real ops prerequisite, not a 5m decision.
- **It produces reusable artifacts.** The Phase C1–C5 design docs are prerequisites for both option (a) and option (b). Option (c) lands them without committing to a runtime.
- **It is the most reversible option.** If the operator later lifts Q1, the architecture reference and routing-table unit tests survive. The Phase B GTK wire-up work (which is operator-asked-scope and in flight on `khostty-phase-b-gtk-spec-20261017`) is unaffected.

### What changes if (c) is rejected

If the operator picks (a):
- Phase C runs as today (2d design).
- A Linux box with GTK must be provisioned (~1d operator). The build host disk pressure must be addressed (state §7).
- Phase D begins immediately after Phase C, targeting the GTK runtime. The Phase B wire-up (B1–B5) becomes Phase D's first half.
- A GTK-side harness must be added to `ci/zig-fork-tests.yml` to validate E2E.
- The fork is locked onto GTK as the Phase 1 runtime.

If the operator picks (b):
- C1 audit (`01_EMBEDDED_AUDIT.md`) becomes a hard prerequisite — not optional. If C1 says "no", option (b) collapses and the operator must re-decide.
- Phase C runs as today, with the embedded-on-macOS feasibility audit as input.
- Phase D targets `embedded.zig` surface-within-surface. The Phase B wire-up is *partially* obviated (the mux binary is the runtime), but the per-instance `khostty.sock` wire-up still needs Phase B work.
- The fork is locked onto AppKit as the Phase 1 runtime.

If the operator picks (c) but later decides Phase 1 should ship in 0.2.0 or 0.3.0, the Phase C artifacts are reusable and the runtime decision can be re-made with more data (upstream GTK stability, `embedded.zig` audit, operator's Linux-host availability).

---

## §6. If you can't decide today

**Safe intermediate:** pick option (c) for now, defer Phase D to a later release (target 0.3.0). The Phase C design artifacts (mailbox integration, event-hook map, `embedded.zig` audit, lock-ordering contract) ship in 0.1.1 alongside the Phase A polish batch (FWD-PATH §2).

Rationale: option (c) is the no-regret default. It does not consume operator infra time, does not depend on a missing audit, and produces artifacts that any future Q1 decision can reuse. If the operator re-decides Q1 in a quarter, the only sunk cost is 2d of agent time and the architecture doc itself, both of which are net-positive deliverables regardless of runtime choice.

**Do not** block on Q1 by deferring Phase C as well. Phase C is independent of Q1 and unblocks the *next* Q1 decision by providing the design inputs (mailbox integration, `embedded.zig` audit, lock-ordering contract). The only item Phase C depends on is operator approval for the design direction.

---

## §7. One-sentence summary (for the operator to type back)

> Pick option (c) — land Phase C design + mock skeleton in 0.1.1, defer Phase D runtime decision to a later release, and re-decide Q1 after the `embedded.zig` audit and Linux-host situation are concrete.

---

## §8. Appendix — inputs I considered

- `20261017-FWD-PATH.md` §4 — Phase 2 = Phase 1 mux shell; C1–C5 design tasks; Phase D blocked on Q1.
- `20261017-FINAL-AUDIT.md` §8 row Q1 — three options + design blocks C1–C5.
- `20261017-FINAL-AUDIT.md` §9 #1 — embedded-on-macOS multi-pane feasibility unverified.
- `20261017-mux.md` §5 — Phase 1 design sketch (binary name, sockets, routing table, command surface, lock ordering).
- `20261017-mux.md` §5 design risk #2 — lock-ordering contract is the single highest-risk design decision in Phase 1.
- `20261017-mux.md` §6 #8 — audit `embedded.zig` for mux compatibility is item C1, currently NOT STARTED.
- `20261017-mux.md` §8 #3 — `embedded.zig` multi-pane feasibility gap.
- `20261017-state.md` §3.2 — runtime table; agent v1 wired not started; `windowed` gate is the real fork boundary.
- `20261017-state.md` §5 #8 — Tailscale `kooshapari-desk` offline, no remote wake.
- `20261017-state.md` §7 — build host at 96–98% disk.
- `20261017-state.md` §8 #3 — Phase 0 "green" is shallower than it looks; GTK-side harness missing from CI.
- `docs/sessions/20261017-mux-design/05_PHASE_B_GTK_WIREUP.md` — Phase B wire-up spec (1,411 lines), in flight on `khostty-phase-b-gtk-spec-20261017`. Confirms that GTK runtime is the Phase B plan, distinct from Phase 1 mux shell.
- `src/apprt/embedded.zig` (2,576 lines, C-callconv AppKit glue; file header says "embedded within a parent host application"). Confirms that re-embedding is architecturally plausible but unproven.

**C1 audit status:** `01_EMBEDDED_AUDIT.md` does not exist on disk. Confirmed by `find . -name '01_EMBEDDED_AUDIT.md'` → 0 hits. Option (b) is therefore conditional on a 1d audit the fork has not yet performed.

---

**End of decision matrix.**