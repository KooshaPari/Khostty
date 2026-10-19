# Phase 1 Mux Shell — Risk Analysis (Operator Brief)

**Repo:** `/Users/kooshapari/CodeProjects/Phenotype/repos/khostty`
**Date:** 2026-10-17
**Author:** VP-Eng (jcode orchestrator, tier-0 M3) — Phase-1 risk analyst
**Status:** draft for operator read (5 min)
**Scope boundary:** Phase 1 design + mock skeleton (Phase C1–C5), per `06_Q1_DECISION_MATRIX.md §5` recommending **option (c)** (mock-only prototype, defer real runtime). The risk landscape for full Phase D implementation is captured but the recommended Phase C scope downgrades implementation-impact severity.

**Binding (operator 2026-10-15):** FORK-ONLY. No `gh pr/issue/discussion create` or `gh api POST/PATCH/DELETE` against `ghostty-org/ghostty`. Reading, copying, `zig build` against upstream: fine. Push to `KooshaPari/*`: fine.

**Companion documents:**

- `00_SESSION_OVERVIEW.md` — session scope
- `04_MUX_ARCHITECTURE.md` — Phase 1 architecture (C4) — **NOT YET ON DISK at write time** (see §10 dependency note)
- `05_PHASE_B_GTK_WIREUP.md` — Phase B (G4 finish) wire-up spec
- `06_Q1_DECISION_MATRIX.md` — operator pick (c): mock-only prototype
- [`../../audits-archive/2026-10-17-final/FWD-PATH.md`](../../audits-archive/2026-10-17-final/FWD-PATH.md) §4 (Phase 1 design + impl tasks) + §10 (risk register)
- [`../../audits-archive/2026-10-17-final/mux.md`](../../audits-archive/2026-10-17-final/mux.md) §5 (design sketch) + §5 design risks
- [`../../audits-archive/2026-10-17-final/state.md`](../../audits-archive/2026-10-17-final/state.md) §6, §8 (gaps relevant to Phase 1)
- Source of truth for the existing IPC contracts: `src/apprt/ipc/pane.zig` (lock-ordering doc, lines 17-24), `src/apprt/ipc/server.zig` (lifecycle, lines 153-213), `src/apprt/ipc/app_host.zig` (threading, lines 34-50).

---

## 1. TL;DR — Top 3 Risks (Ranked)

| Rank   | Risk                                                                                                                                                                                                                                                                                                                                                                                     | Severity (Phase C)                                                   | "If this fires, here's what we do"                                                                                                                                                                                                                   |
| ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **R1** | **Lock-ordering contract breach.** Phase 1 introduces a new lock layer above the existing `Manager → Broker` ordering (`pane.zig:17-24`) without a documented composition. If the mock skeleton's tests are written against the wrong ordering, every future Phase D implementation inherits a deadlock that only fires under load.                                                      | **High** (load-bearing even in mock scope)                           | **Stop, write a 1-pager** in `04_MUX_ARCHITECTURE.md` §"Lock Ordering" specifying the additional `MuxRouter → Manager → Broker` ordering and a "no reentrancy" rule mirroring `pane.zig:17-24`. Land it before any routing-table unit test compiles. |
| **R2** | **Socket-ownership ambiguity.** `khostty-mux.sock` is a parallel socket to per-instance `khostty.sock`. Race between two `khostty-mux` processes binding the same path is undefined. Stale-socket stale-file pattern in `server.zig:154-156` (`replace_existing=true` default + `deinit` `deleteFile`) works for 1:1 mux↔host but is not specified for N:1 (many hosts behind one mux). | **Medium** (mock scope: routing-table test only; full Phase D: high) | **Document the contract in C4:** exactly one mux process owns `khostty-mux.sock`; instance sockets are N:1 with the mux as the only client. Add a `mux.list` test that proves double-bind refuses.                                                   |
| **R3** | **C4 (architecture doc) does not yet exist.** The Phase 1 architecture was due before mock skeleton (FWD-PATH §4 C4), and the lock-ordering decision (§2 below) is the single highest-risk design decision per `mux.md §5 risk #2`. C4 absence blocks the Phase C5 mock skeleton's compile-time invariants.                                                                              | **Medium**                                                           | **This doc publishes alongside** a 1-pager to `04_MUX_ARCHITECTURE.md`; the analyst session writes both. If 04 does not land within 24h, escalate to operator — without it, Phase C5's lock-ordering tests cannot be authored.                       |

**Other risks (Phase C-scope, ranked):** Routing-table contention under load (§4), cross-instance keyboard routing latency/ordering (§5), detach/reattach durability across `khostty-mux` restart (§6), upstream rebase surviving through Phase 1 (§7), test-coverage gaps (§8), operator-decision blocking items (§9). None of these block Phase C; all become critical at Phase D.

---

## 2. Lock Ordering — The Highest-Risk Design Decision

### State today

`src/apprt/ipc/pane.zig:17-24` documents a strict, non-reentrant contract:

> Locking: one manager mutex serializes registry access _and_ host calls […] Consequences, both documented rather than accidental:
>
> - a host call must never call back into the same `Manager` (no reentrancy);
> - `Manager` -> `events.Broker` is the only lock ordering used, and nothing under the broker lock calls back into the manager.

The Manager mutex (`pane.zig:335`) and the Broker mutex (`events.zig:264`) are the only two locks in the IPC plane today. Every public `Manager` method (create/close/focus/write/snapshot/resize/equalize/zoom/search/list) takes the manager lock around its body, and `events.Broker.publish` (the only fan-out from the manager path) takes the broker lock without reentering the manager. The protocol is **load-bearing** for correctness: a researcher added an in-the-loop fan-out in the Phase 0 review and it would have deadlocked instantly.

The `AppHost` adds a third mutex (`app_host.zig:98`) — but this is **outside** the IPC fan-out path. `app_host.zig:36-38` is explicit: "this only serializes _IPC_ callers; it does not make concurrent access from the app thread safe." The mailbox hop (`CoreSurface.queueIo`, `app_host.zig:42-43`) is the uncompleted contract that bridges IPC threads and the app thread without a third lock in the IPC plane.

### What Phase 1 changes

Phase 1 adds **two new lock-bearing components** (per mux §5 + FWD-PATH §4):

1. **Routing table** in the new `khostty-mux` binary, keyed by `(instance_id, pane_id)` → `client`. This needs a lock to serialize concurrent `mux.list`/`mux.focus`/`mux.attach`/`mux.detach`/`mux.layout.save` against per-connection event fan-in.
2. **Cross-instance fan-out mutex** for handing a `mux.focus` event from one host's broker to another host's client connection. Today no IPC code holds two manager locks at once; Phase 1 will, by definition, hold **(mux router, instance-A manager, instance-A broker)** and **(instance-B manager, instance-B broker)** in different orders depending on which instance owns the focused pane.

### How the new layer composes (proposed, requires C4 sign-off)

Extend the contract to:

```
MuxRouter → Manager → events.Broker   (per instance, never reversed)
```

**Invariant:** a thread holding the `MuxRouter` lock may NOT call `Manager.*` methods, because doing so would create two paths into `Manager` (one from another mux thread, one from a per-instance IPC thread) and reintroduce reentrancy. Instead, the mux routes messages into the per-instance `khostty.sock` connection as opaque frames; the per-instance manager deals with them on its own thread. The mux does **not** issue `pane.create`/`pane.focus` against an instance's Manager directly — it forwards the wire-level command and waits for the response.

**Effect:** the mux remains free of any lock call into Manager; Manager's "no reentrancy" guarantee survives; Broker's per-event lock order survives; the only new lock is `MuxRouter`, which sits _above_ both and never participates in the existing order.

### If C4 does not address this

The mock skeleton's routing-table tests will encode _some_ ordering — and future Phase D implementers will copy that ordering into the real binary. If the encoded ordering is wrong, the bug is invisible in tests because fake host doesn't take any of the three locks; it manifests only when Phase D lands against real GTK/AppKit runtimes, where the runtime's own mutex (e.g., GTK's `gdk_threads_enter`) participates in the ordering chain.

**Action gate:** `04_MUX_ARCHITECTURE.md` MUST contain a "Lock Ordering" section naming the extended `MuxRouter → Manager → Broker` ordering and citing `pane.zig:17-24` as the precedent. If the analyst cannot satisfy this gate, treat Phase C5 as blocked.

---

## 3. Socket Lifecycle — `khostty-mux.sock` Ownership

### Current state (per-instance socket)

`server.zig:153-213` is the canonical implementation:

- `replace_existing: bool = true` (server.zig:42-43) — a stale socket left by a crashed instance is replaced on `bind`.
- `deinit` removes the socket file (server.zig:212). This is correct for a 1:1 mux↔host shape: stale sockets are common and "almost always" left by a crashed instance.
- `stop` (server.zig:177-188) wakes a blocked `accept` by connecting to itself, then waits up to 5s for in-flight connections (server.zig:201-207).
- `max_connections` and `rate limiting` are **NOT yet implemented** (FWD-PATH §3 B3) — they will land as part of Phase B (5-line, 1h task).

### Phase 1 introduces a new socket

`khostty-mux.sock` at `$XDG_RUNTIME_DIR/khostty/mux.sock` (path TBD by C4). Properties:

| Property               | Expected                                          | Source for the value            | Risk                                                |
| ---------------------- | ------------------------------------------------- | ------------------------------- | --------------------------------------------------- |
| Owner process          | Exactly one `khostty-mux` per host                | Design brief, mux §5            | High — race between two muxes binding the same path |
| Re-bind on stale file  | Yes (mirror `replace_existing`)                   | server.zig precedent            | Low — copy pattern                                  |
| Reap on clean shutdown | Yes (mirror `deinit`)                             | server.zig:212                  | Low                                                 |
| Reap on crash          | Optional — second mux should be able to take over | operator decision               | **Medium** — design unclear                         |
| Auth model             | Reuse `auth.zig` token                            | mux §5 (reuses protocol + auth) | Low — already implemented                           |
| Per-instance clients   | N                                                 | Design brief                    | Low — same as today's per-instance server           |

### Race conditions to enumerate

1. **Two muxes binding the same `khostty-mux.sock` simultaneously.** `Server.bind` would `deleteFile` then `listen`. With `replace_existing=true`, the second binds over the first; the first's accept thread dies. **Outcome:** which mux "wins" is non-deterministic; clients in flight get `error.ConnectionResetByPeer` (Linux) or clean FIN (macOS) per the documented behavior in `server.zig:799-832`. This is acceptable if the design is "last mux wins, old connections drop", but **must be documented**.

2. **Mux dies while clients are connected.** `server.zig:191-213` already handles "client still connected at server deinit" by waiting 5s, then logging a warning (server.zig:202-205). For mux, a connected agent may have in-flight `mux.focus` to a per-instance connection; the per-instance manager must be told the mux is gone so it can stop forwarding. **MVP:** the per-instance `Server.deinit` is local; the mux's `deinit` is independent. The IPC protocol has no "client gone, drop pending ops" message today.

3. **Per-instance process restart while mux is alive.** Today every per-instance is independent; the mux knows each by `instance_id`. If a per-instance restarts, its `khostty.sock` is unbound for ~100ms. The mux's routing table holds stale `(instance_id, pane_id) → old connection` entries. **MVP:** mux must surface a per-instance `instance_gone` event to subscribed agents OR retry transparently. Neither is specified by `mux.md §5`.

4. **Stale socket file from a crashed mux.** Same as today's per-instance: `replace_existing=true` handles it. **No new risk.**

### If C4 does not address this

The mock skeleton's `mux.list` test will use a single-test `khostty-mux.sock` and not exercise race conditions. Phase D implementers will copy the mock skeleton's lifecycle verbatim — including any lazy handling of these races.

---

## 4. Routing Table Scaling — `(instance_id, pane_id) → client`

### Hypothesized structure

A `std.AutoHashMap(struct { instance_id: u64, pane_id: PaneId }, *ClientConn)` lookup table inside the mux, guarded by the `MuxRouter` lock (per §2). Insert on `mux.focus`, lookup on every event fan-out from a per-instance broker, delete on `mux.detach`.

### Contention profile

The mux's hot path is **event fan-out** (per pane: `titleChange`/`childExit`/`resize`/`bell`/`focusChange` from `protocol.md §6.2`). At a steady-state load of one focus event per pane per second (typical terminal activity), with N panes per instance and M instances, the table sees O(N·M) updates/sec. Each update is a hash lookup + an event write to the matched client connection.

At 100 panes × 10 instances × 2 events/sec/pane = **2,000 lookups/sec.** A single `std.Io.Mutex` covers this with margin (sub-microsecond per lookup, zero contention at the rate). At 10,000 panes × 100 instances × 10/sec → 10⁷/sec, which is the regime where sharded `MuxRouter` mutexes become worthwhile. The mock skeleton's tests cannot observe this; only Phase D production loads will.

### When does the table need to be partitioned?

Partition when **any** of:

| Signal                        | Threshold                                   |
| ----------------------------- | ------------------------------------------- |
| Lookup latency p99            | > 500 µs (single-threaded budget)           |
| `MuxRouter` lock queue depth  | > 32 waiting threads (rule of thumb)        |
| Live `(instance, pane)` pairs | > 65,536 (one mux binary's natural ceiling) |
| Operator's user count         | > 50 simultaneous agents                    |

Partitioning design (deferred to Phase 2 if even needed): shard by `instance_id % K` for K = core count, each shard owns a sub-table and a sub-mutex. Keep the broker fan-out routing through the same shard (broker→shard by instance_id) so the lock domains don't multiply.

### What the mock skeleton should test

- Insert / lookup / delete round-trips 1M times under single-threaded load (correctness).
- Concurrent insert+lookup from 8 threads × 100K operations (correctness under contention).
- Memory bound: 1M entries does not OOM the test (allocator growth capped).
- Event fan-out to N clients for one pane: 100 µs per event at p99.

C4 should commit to a specific structure (hash map vs sorted array vs trie) and quote the expected lookup complexity. The mock skeleton cannot reverse this decision later because the wire format and tests encode it.

---

## 5. Cross-Instance Keyboard Routing — `mux.focus`

### What `mux.focus` does

Given `(instance_A, pane_X)`, deliver keystrokes typed by an agent connected to `khostty-mux.sock` to the `App`/`CoreSurface` that owns `pane_X` inside instance_A, **without** going through instance_A's `khostty.sock` IPC path. (The IPC path is parser-level only — see `pane.zig:404-409` and `app_host.zig:17`: `pane.write` is VT-injection, not pty-injection.) The mux needs a separate "keyboard input" channel into the App's input pipeline.

### Why this is harder than it looks

1. **Upstream `App` has no "feed keystrokes by surface id" API.** `app_host.zig:54-58` documents that the four event publish hooks (titleChange/childExit/resize/bell) belong next to upstream callbacks. Keystroke feed is upstream-internal — forking it would mean a fork-only seam in the App input path (`App.zig` or `Surface.zig`'s input handling). That is upstream-code-modifying surgery, which is out of fork-only scope per the binding rule.
2. **`pane.focus` is already `error.Unsupported` upstream** (`app_host.zig:15`, lines 177-178). Even at the per-instance level, focusing a pane by id is not implemented. `mux.focus` cannot reuse it; it has to find another way.
3. **PTY injection is a Phase 2 item** (mux §5 non-goal, FWD-PATH §7 "Phase 2 not designed yet"). Without pty injection, the only injection surface is the parser — and `pane.write` does that today, but the parser doesn't accept bare keystrokes (it accepts VT bytes).

### What Phase 1 (option c) actually delivers

Phase 1 cannot route real keyboard. The mock skeleton's `mux.focus` returns a wire response of `{"ok":true,"detail":"mock-stub"}` and a unit test confirms the routing table is updated. Real keyboard routing is deferred to Phase 2 (durable sessions + `pane.execute`).

### What Phase 1 must disclose to agents

- `mux.focus` returns `ok:true` and a synthetic event, NOT actual keyboard delivery.
- The "if-this-fires" recovery for an agent that expected real focus: re-read the protocol doc and treat `mux.focus` as a documentation-only signal for Phase 1.

### Latency / ordering concerns (only relevant when Phase 2 lands)

When real focus lands, the latency budget is tight: a `mux.focus` round-trip must be <16ms (one frame at 60Hz). Order is strict: two `mux.focus` calls in quick succession must serialize into the receiving App's input pipeline without reordering. The fan-out mutex from §2 does not help here — it's at the mux, not at the App.

---

## 6. Detach / Reattach Durability — `mux.detach` and `mux.attach`

### What `mux.detach` does (in design)

An agent's `mux.detach(instance, pane)` tells the mux: "I'm going away for a while. Stop delivering events for this pane. Keep the pane alive in the runtime."

### What `mux.attach` does

The same or different agent reconnects, calls `mux.attach(instance, pane)`, and resumes event delivery — including any events that occurred during the detached period (the "subscription replay" problem).

### What needs to be persisted (per design brief, mux §5)

| State                                    | Persisted?                                                                   | Where                                             | Risk                                                                                                                                          |
| ---------------------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `(instance_id, pane_id) → client_handle` | No — runtime-resident; lost on mux restart                                   | Mux RAM                                           | **High if mux restarts**: routing table rebuild requires re-`mux.attach` from every agent                                                     |
| `mux.layout` (saved layout tree)         | **Yes** (Phase 1 design brief says `mux.layout.save` / `mux.layout.restore`) | A file in `XDG_DATA_HOME/khostty/mux/` (path TBD) | Low — same write-once/read-once as a config file                                                                                              |
| Event backlog for detached panes         | **No** today; design brief does not specify replay                           | —                                                 | Medium — agents that re-attach may miss events                                                                                                |
| Per-instance per-pane "should be alive"  | **No**                                                                       | —                                                 | **High** — if a per-instance restarts and its mux knows about its panes, but the mux restarts, the mux forgets the panes were ever registered |

### Risk focus: mux process restart

If `khostty-mux` crashes or is killed, today the routing table is gone. The per-instance `khostty` processes survive (they own the panes), but the mux no longer knows which agent should receive events for which pane. On restart:

1. The mux re-binds `khostty-mux.sock`. ✓
2. The mux does NOT reconnect to per-instance sockets automatically. **Open question.**
3. Agents that were attached must reconnect and re-`mux.attach` to resume. **Specified behavior, but operators should expect this.**

For Phase C scope (mock skeleton), the durability risk is "design-time" only — the test asserts that mux restart causes `detach`-like drop of client state. The implementation risk lives in Phase D.

### What the mock skeleton should test

- `mux.detach` removes the entry from the routing table; subsequent events from the pane are NOT pushed.
- `mux.attach` re-inserts the entry; subsequent events ARE pushed.
- Mux restart (close-and-rebind) clears the routing table; clients get `error.EndOfStream`; the next client `mux.list` shows zero attached pairs.

---

## 7. Upstream Rebase — How Phase 1 Survives `ghostty-org/ghostty`

### Today's drift

Per `state.md §2`: fork is 366+ commits behind upstream at 2026-10-15. Upstream moves ~62 commits / 8h. The IPC surface is additive (new files in `src/apprt/ipc/`, no mutations of upstream signatures), so rebases are cheap — IF the additions stay additive.

### What Phase 1 introduces that is upstream-touching

- **New binary** `khostty-mux` (parallel to `khostty`). Add to `build.zig` as a new executable target. **No upstream conflict** — additive.
- **`build.zig.zon` change** — new module declaration for the mux binary if it imports anything `pkg/`-side (vs only `src/apprt/ipc/`). **Low conflict probability.**
- **`src/apprt/ipc/`-only imports for the mux** — the mux binary imports `protocol.zig`, `auth.zig`, `events.zig`, `handler.zig`. **No upstream conflict**, but the binary may need to import `app_host.zig` which imports `App.zig` (upstream). If the mux does NOT need `app_host.zig` (only the per-instance processes do), it stays fork-local.
- **New `src/apprt/ipc/mux_shell.zig` and siblings** — fork-local, additive, no conflict.
- **Possible seam in `App.zig` / `Surface.zig` for `mux.focus`** (Phase 2 only) — upstream-code mod, not Phase 1 / Phase C.

### Fork-discipline test

Carry-forward #24 (`state.md §8 #10`): `tools/check-fork-discipline.zig` should verify that any fork-owned change does not modify upstream-owned files. Phase 1 work is confined to `src/apprt/ipc/mux_shell.zig`, `src/main_mux.zig`, `build.zig` (additive target), and `docs/`. **No fork-discipline violation expected.**

### Most likely regression surfaces

| Surface                                 | Risk                                                                                                                                                                                                              | Mitigation                                                          |
| --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `pane.zig` lock-ordering doc            | **Low** — Phase 1 doesn't touch `pane.zig`, but the contract extension in §2 needs to be documented in C4 with a pointer to `pane.zig:17-24`. Upstream edits to the doc must be detected and the pointer updated. | Add a `pane.zig` "Mux layer addition" comment that survives rebase. |
| `server.zig` `replace_existing` default | **Low** — Phase 1 mirrors it, no shared code.                                                                                                                                                                     | —                                                                   |
| `build.zig` for the new executable      | Medium — additive but the spec is verbose. Use the existing `test-agent-ipc` step as a template.                                                                                                                  | Document the pattern in C4.                                         |
| `app_host.zig` threading note           | Low — Phase 1 mock doesn't use `app_host.zig`.                                                                                                                                                                    | —                                                                   |
| `protocol.md §6.2` event surface        | Low — Phase 1 reuses existing events. New `mux.*` events are documented in C4, not in `protocol.md`.                                                                                                              | —                                                                   |

### EGL / OpenGL surface

Out of scope for Phase 1 — the mux doesn't render. The EGL BOTH-arms harness (per `state.md §8 #8`) does not need to re-run for Phase C.

---

## 8. Test Coverage Gaps — Minimum Surface to Call Phase 1 Done

Phase C is "design + mock skeleton". The minimum test surface to call Phase C done:

### Required (mock skeleton)

| Test                                                           | What it proves                                                       | File                                                |
| -------------------------------------------------------------- | -------------------------------------------------------------------- | --------------------------------------------------- |
| `routing: insert/lookup/delete round-trip`                     | Data structure is correct                                            | `src/apprt/ipc/mux_shell.zig`                       |
| `routing: concurrent insert + lookup from 8 threads`           | No torn reads, no lost writes                                        | `src/apprt/ipc/mux_shell.zig`                       |
| `routing: memory bound at 1M entries`                          | No allocator runaway                                                 | `src/apprt/ipc/mux_shell.zig`                       |
| `mux.list returns all instances + their panes`                 | Wire-format parity with `protocol.md`                                | `src/apprt/ipc/mux_shell.zig`                       |
| `mux.focus updates routing table (mock delivery)`              | Routing-table update path works; mock returns synthetic event        | `src/apprt/ipc/mux_shell.zig`                       |
| `mux.attach + mux.detach round-trip`                           | Detach removes entry; attach re-inserts                              | `src/apprt/ipc/mux_shell.zig`                       |
| `mux.layout.save + mux.layout.restore across processes`        | Layout file format is forward-compatible                             | `src/apprt/ipc/mux_shell.zig`                       |
| `mux restart clears routing table`                             | Detach implicit on restart                                           | `src/apprt/ipc/mux_shell.zig`                       |
| `lock ordering: MuxRouter never holds Manager`                 | Compile-time property checked via test, mirroring `pane.zig:565-588` | `src/apprt/ipc/mux_shell.zig`                       |
| `auth: same token works on mux socket and per-instance socket` | Reuse `auth.zig` end-to-end                                          | `src/apprt/ipc/mux_shell.zig`                       |
| `fork-discipline: mux_shell.zig does not import App.zig`       | Mock skeleton stays mock                                             | `tools/check-fork-discipline.zig` (regression test) |

**Total:** ~10-12 tests, ~300-500 LOC of test code. Phase C scope.

### Deferred to Phase D (real implementation; out of Phase C)

| Test                                                         | When                                 |
| ------------------------------------------------------------ | ------------------------------------ |
| Two muxes racing to bind `khostty-mux.sock` — second wins    | Phase D                              |
| Mux dies mid-`mux.focus` — partial fan-out recovery          | Phase D                              |
| Per-instance restart — mux routing-table stale entry reaping | Phase D                              |
| `mux.focus` with real keyboard delivery (Phase 2)            | Phase 2                              |
| Event replay across `mux.attach` after detach                | Phase 2 (requires persistence layer) |
| `max_connections` + rate limit on mux socket (B3)            | Phase B                              |

### Coverage target

Per docs-3 ATLAS program (`docs-5/qa/METRICS.md §85%-coverage-floors`): Phase C should hit 80%+ coverage on `mux_shell.zig`. Phase D should hit 85%+ as part of the broader program gate.

---

## 9. Open Questions for the Operator

These are the items only the operator can resolve. None blocks Phase C landing (per the (c) recommendation), but each shapes Phase D when it lands.

1. **Q1 — runbook choice: option (c) confirmed?** `06_Q1_DECISION_MATRIX.md §5` recommends (c). If the operator picks (a) or (b), this risk profile changes materially — R1-R3 stay, but R5 (cross-instance keyboard routing) becomes the priority instead of a Phase 2 item.
2. **Q1.b — when, if ever, does Phase D start?** If "never", then `khostty-mux` binary is an optional artifact, not in the MVP. Document the answer in C4.
3. **Q1.c — Linux-host posture for Phase 2 work?** If Tailscale `kooshapari-desk` comes back online, GTK Phase D becomes viable. Status unknown; per binding rule, no probes.
4. **Disk pressure** (`state.md §7`): 96-98% disk on the build host today. Phase C work is doc-heavy + ~500 LOC of Zig, no big binaries. **Disk is not at risk for Phase C.** For Phase D it would be.
5. **`mux.focus` failure disclosure policy.** When an agent calls `mux.focus` and Phase 1 returns `ok:true` but no real focus happens, should the wire format be `{"ok":true,"detail":"not_implemented_yet"}` or `{"ok":false,"code":"not_implemented"}`? The latter is more honest. **Operator preference.**
6. **`mux.layout.save` file format ownership.** JSON? Cbor? Binary? Owned by fork (with `version: u32` header)? Out of scope for Phase C; **operator vote** when Phase D starts.
7. **Mux process supervision.** Who supervises `khostty-mux`? launchd? systemd? The khostty binary's own supervisor? **Open.**
8. **Auth model on mux socket.** Reuse per-instance token? Per-mux token? Cluster of trusted users? `auth.zig:188-198` documents the per-instance path; mux layering needs explicit decision.

---

## 10. Dependency Notes (Audit Trail)

### C4 architecture doc — not on disk at write time

Per the analyst prompt, this risk doc was to read `docs/sessions/20261017-mux-design/04_MUX_ARCHITECTURE.md` if it exists. At write time it does not. The fallback was to source from `mux.md §5` (Phase 1 design sketch) + FWD-PATH §4 (C1–C5 design tasks) + `06_Q1_DECISION_MATRIX.md` (Phase 1 architecture scope = Phase C). This doc therefore carries the design risk forward: every lock-ordering, socket-lifecycle, and routing-table observation that should be in C4 is captured here in lieu.

**Recommendation:** the C4 owner (Phase C author lane) should adopt this doc's §2-§6 sections verbatim or rewrite them with explicit per-section knowledge citations. The "if C4 does not address this" language in §2 and §3 is the gate.

### Cross-references verified

- `src/apprt/ipc/pane.zig:17-24` (lock ordering doc, no-reentrancy rule) — read.
- `src/apprt/ipc/pane.zig:335` (Manager mutex), `:378-393` (broker publish call sites), `:394-468` (every public method takes the manager lock around its body) — read.
- `src/apprt/ipc/server.zig:153-213` (full bind/start/stop/deinit lifecycle), `:42-43` (replace_existing default), `:202-205` (5s drain + warn), `:212` (deleteFile in deinit) — read.
- `src/apprt/ipc/server.zig:799-832` (macOS-vs-Linux close-detection exhaustive switch) — read.
- `src/apprt/ipc/server.zig:215-229` (drainConnections 5s wait) — read.
- `src/apprt/ipc/app_host.zig:34-50` (threading note: AppHost mutex serializes IPC callers only; mailbox hop is the uncompleted contract) — read.
- `src/apprt/ipc/events.zig:264` (broker mutex), `:278-389` (every entry takes the mutex + io per the file header) — read.
- `docs/audits-archive/2026-10-17-final/mux.md` §5 design sketch + design risks — read.
- `docs/audits-archive/2026-10-17-final/FWD-PATH.md` §4 (Phase 1 design + impl), §10 (risk register) — read.
- `docs/sessions/20261017-mux-design/06_Q1_DECISION_MATRIX.md` (operator pick (c)) — read.
- `docs/sessions/20261017-mux-design/05_PHASE_B_GTK_WIREUP.md` (Phase B spec, 1,411 lines; exists but not re-read end-to-end for this doc; cross-reference only) — header confirmed.

### Out of read scope (deliberate)

- `src/apprt/embedded.zig` (89,852 bytes / 2,576 lines, AppKit glue) — not relevant for Phase C scope; covered by C1 audit and `06_Q1_DECISION_MATRIX.md §4` for Phase D.
- `src/Surface.zig` (mailbox primitive `CoreSurface.queueIo`) — FWD-PATH §3 B2 + C2 audit item; out of Phase C scope.
- `src/apprt/gtk/App.zig` lifecycle — FWD-PATH §3 B1; out of Phase C scope.

---

**End of Phase 1 risk analysis.**
