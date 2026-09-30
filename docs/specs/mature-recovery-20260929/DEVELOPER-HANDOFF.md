# Khostty developer-agent handoff

**READY FOR PARALLEL EXPERIMENTAL IMPLEMENTATION. NOT READY FOR GENERAL DEV HANDOFF.**
Updated 2026-09-29, pass 5. Product source: `a29aa9c6553d9f42aa68e2919116c0f6d53f329d`. Research/spec branch: `docs/mature-recovery-20260929`. Draft #7, registry draft #593. Only Khostty and Melosviz are product subjects.

## Executable evidence available

```sh
python docs/specs/mature-recovery-20260929/pass5/check_snapshots.py --out /tmp/khostty-static-fresh.json
```

The command verifies complete copied source-file Git blobs and inspects known runtime bodies. It was run locally. It diagnoses that selected Windows App init/register/run are Unimplemented; a passing diagnostic does NOT mean Windows works. No Zig compiler/native GUI was run here. Raw source copies are preserved by original blob identity.

The registry dossier's `tools/source_inventory.py` inventories an exact Git tree and compares the merge base without running product code. It was tested on a synthetic Git repository, including newline filenames, symlinks, changed/deleted paths and moving-ref rejection. It has NOT yet enumerated full Khostty in this environment. A complete tracked tree remains different from a resolved semantic denominator.

## Bounded work packages and write ownership

**K-E01-EMBED — remaining embedding/CI semantic closure (continue now, parallel-safe with K-E02).** Tracked-tree enumeration, top-level ownership and the agent-IPC mount trace are already closed. Focus only on wrapper/native-consumer and evidence machinery: Rust/Go/Python/WASM linking, PTY/FFI callback/thread lifetime, build/CI expected jobs, and exact native artifact identity. Current CI is not qualifying evidence: advisory jobs swallow failures, macOS build is disabled, `ci / test` runs no tests, and Rust native integration tests disappear when `ghostty_vt_linked` is absent. Return a finite wrapper delta + real-consumer evidence plan rather than redoing the full inventory.

**K-E02 — one native/control comparison (READY NOW; K-E01 mounting prerequisite sufficiently closed by pass 6, but return inventory drift with the receipt).** Use a platform actually available to the worker. Run a known child with a nonce and independent receipt, target a specific pane, inspect output, replace only the controller, and verify stale-target/no-unintended-effect behavior. Compare Khostty against the strongest applicable existing stack. Ghoztty is pinned at `fd3838acfa834c29e99616cdc8500c0208a13a09`; README claims and root MIT license alone are not qualification. An explicit Unsupported/failure may be the truthful Khostty baseline. Any mailbox/Host wiring repair is a bounded spike under `src/apprt/ipc/` and its necessary native hook, not permission to build a broad agent platform. Preserve v1 display-feed semantics; child input is a separate operation/contract.

**K-E03 — one embedding consumer (READY NOW; may run in parallel with E02 with disjoint files).** Own one wrapper's experiment/test directory, not terminal core or E02's IPC files. Exercise actual upstream library linking, creation/feed/resize/read/free and applicable callback/thread rules. Compare against direct upstream integration. Do not attribute the manifest generator to Khostty: its source/header are byte-identical to upstream merge base. Closure: candidate/configuration-bound native library evidence and the exact wrapper delta worth retaining.

K-E01's broader semantic/history cleanup continues, but its agent-IPC mount/caller prerequisite is sufficiently closed for K-E02/K-E03. K-E02 and K-E03 may run concurrently in disjoint worktrees, and either may run alongside Melosviz M-E01/M-ESEC. These are independent worktrees with separate evidence. Only the program owner reconciles shared registry summaries. No agent may merge, release, alter credentials, spend on a provider, expand product scope, or weaken the expected rubric to green.

## Handoff return receipt

Return product/source/spec/candidate revisions; command and environment; scope and actual write paths; immutable artifact hashes; positive/negative observations; unsupported/skipped/collector-failed outcomes; scope delta separately from engineering delta; and remaining uncertainty. Hash the tree before/after testing. Tests must not mutate the authoritative candidate in place.

## Still blocking general developer handoff

Primary product authority, full semantic source resolution and useful history; completed alternatives/licensing/health and architecture risk closure; full mature obligations/quality/stages/journeys; bidirectional mapping; all required oracles; and a genuinely fresh independent review. Earlier 'user objective recovered' wording is not independently confirmed by this pass's memory retrieval: it returned assistant summaries. Preserve the objective as an imported attribution until its primary message is recovered.

The package enables bounded experiments now. It does not authorize autonomous broad implementation or a product completion claim.


### CI evidence rule added in pass 6

Do not cite the current aggregate `ci / test` context as proof that wrapper/native tests executed. A handoff receipt must list expected jobs and a sentinel count/output for the exact native test suite. `continue-on-error`, swallowed command failures, skipped native-library cfgs and the disabled macOS build are evidence gaps, not acceptable greens.
