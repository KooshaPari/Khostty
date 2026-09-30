# Khostty developer-agent handoff

**READY FOR PARALLEL EXPERIMENTAL IMPLEMENTATION. NOT READY FOR GENERAL DEV HANDOFF.**
Updated 2026-09-30, pass 6. Product source: `a29aa9c6553d9f42aa68e2919116c0f6d53f329d`. Research/spec branch: `docs/mature-recovery-20260929`. Draft #7, registry draft #593. Only Khostty and Melosviz are product subjects.

## Executable evidence available

```sh
python docs/specs/mature-recovery-20260929/pass5/check_snapshots.py --out /tmp/khostty-static-fresh.json
```

The command verifies complete copied source-file Git blobs and inspects known runtime bodies. It was run locally. It diagnoses that selected Windows App init/register/run are Unimplemented; a passing diagnostic does NOT mean Windows works. No Zig compiler/native GUI was run here. Raw source copies are preserved by original blob identity.

The registry dossier's `tools/source_inventory.py` inventories an exact Git tree and compares the merge base without running product code. It was tested on a synthetic Git repository, including newline filenames, symlinks, changed/deleted paths and moving-ref rejection. It has NOT yet enumerated full Khostty in this environment. A complete tracked tree remains different from a resolved semantic denominator.

## Bounded work packages and write ownership

**K-E02 — native/control + Windows alternative comparison (READY NOW; K-E01 mounting prerequisite sufficiently closed by pass 6).** On macOS/control-capable environments, run the nonce/target/read/reconnect/stale-ID journey against Khostty and pinned Ghoztty `fd3838acfa834c29e99616cdc8500c0208a13a09`; Khostty may truthfully report UNMOUNTED/UNSUPPORTED. On Windows, do **not** begin by filling Khostty's scaffold. First qualify `shiweis/ghostty-windows@119b9270c8585fa3ae6969c353767fab5a32e438` (native CI run `33633427282`) and compare adapting its Win32 runtime delta versus Khostty's intended host and a thinner libghostty host. Any Khostty mailbox/Host wiring repair remains a bounded spike under `src/apprt/ipc/` plus necessary native hook. Preserve v1 display-feed semantics; child input is a separate operation/contract.

**K-E03 — embedding consumer + CI evidence qualification (READY NOW; may run in parallel with E02 with disjoint files).** Own one wrapper's experiment/test directory and recovery/CI evidence only, not terminal core or E02's IPC files. Exercise actual upstream library linking, creation/feed/resize/read/free and applicable callback/thread rules; compare against direct upstream integration. Require an explicit `ghostty_vt_linked`/native-test sentinel and exact native artifact identity because current Rust integration tests disappear when the library is absent. Build an expected-job matrix that treats advisory/skipped/swallowed failures as non-qualifying. Do not attribute the manifest generator to Khostty: its source/header are byte-identical to upstream merge base. Closure: candidate/configuration-bound native consumer evidence, wrapper delta disposition, and CI evidence policy.

K-E01's broader semantic/history cleanup continues, but its agent-IPC mount/caller prerequisite is sufficiently closed for K-E02/K-E03. K-E02 and K-E03 may run concurrently in disjoint worktrees, and either may run alongside Melosviz M-E01/M-ESEC. These are independent worktrees with separate evidence. Only the program owner reconciles shared registry summaries. No agent may merge, release, alter credentials, spend on a provider, expand product scope, or weaken the expected rubric to green.

## Handoff return receipt

Return product/source/spec/candidate revisions; command and environment; scope and actual write paths; immutable artifact hashes; positive/negative observations; unsupported/skipped/collector-failed outcomes; scope delta separately from engineering delta; and remaining uncertainty. Hash the tree before/after testing. Tests must not mutate the authoritative candidate in place.

## Still blocking general developer handoff

Primary product authority, full semantic source resolution and useful history; completed alternatives/licensing/health and architecture risk closure; full mature obligations/quality/stages/journeys; bidirectional mapping; all required oracles; and a genuinely fresh independent review. Earlier 'user objective recovered' wording is not independently confirmed by this pass's memory retrieval: it returned assistant summaries. Preserve the objective as an imported attribution until its primary message is recovered.

The package enables bounded experiments now. It does not authorize autonomous broad implementation or a product completion claim.


### CI evidence rule added in pass 6

Do not cite the current aggregate `ci / test` context as proof that wrapper/native tests executed. A handoff receipt must list expected jobs and a sentinel count/output for the exact native test suite. `continue-on-error`, swallowed command failures, skipped native-library cfgs and the disabled macOS build are evidence gaps, not acceptable greens.


## Pass 6 promotion receipt

K-E01's source-inspection prerequisite is sufficiently closed for K-E02/K-E03: all top-level trees enumerated; fork-owned versus inherited high-priority surfaces identified; the new JSON agent server shown adjacent to inherited IPC and unmounted at frozen source; remaining semantic/history uncertainty explicitly retained. This does **not** close K-E01 for all future archaeology and does not permit general feature work. K-E02 and K-E03 are now safe bounded experimental handoffs.

## Pass 6 K-E02 comparator contract

Ghoztty `fd3838acfa834c29e99616cdc8500c0208a13a09` is the primary same-family comparator on macOS. Do not use only its README. Its current source supports create/split/close plus read, send-keys, list, rename, rearrange and state-like actions; `send-keys` targets PTY input and `read` returns recent pane output. Its macOS socket is chmod 0600, uses a per-instance/pane-baked socket path, caps requests, and tracks named targets with weak references.

The bake-off must therefore test semantics Ghoztty does not already obviously provide:

1. **Causal completion:** when create/split returns success, independently verify the intended pane/window actually exists and the response identity names that exact effect. Ghoztty source dispatches UI creation asynchronously and can return `.ok` before main-queue completion.
2. **Wrong-instance resistance:** launch/identify two app instances/builds where practical; commands must not mutate the other instance.
3. **Child effect:** send a nonce command to the actual child PTY and verify an external receipt; parser-only display injection is a negative control.
4. **Read/state identity:** read output/state from the exact target, then close/recreate/restart and ensure stale identity cannot qualify the replacement.
5. **Controller replacement/reconnect:** terminate only the CLI/controller and reconnect without inventing product continuity.
6. **Event semantics:** if Khostty claims event-stream differentiation, exercise sequence gaps/drop reporting and causal pane-created/closed events. A source-defined broker that is not mounted earns no credit.
7. **Authorization:** compare effective same-user socket permissions and token policy under the actual threat model; extra authentication complexity is not automatically a benefit.
8. **Platform scope:** Windows evidence is a separate sub-journey; Ghoztty's macOS design explicitly declares Windows out of scope, while Khostty's Windows App lifecycle is currently Unimplemented.

Return a capability matrix with PASS/FAIL/UNSUPPORTED/BLOCKED per exact candidate/configuration. Do not collapse unsupported competitor features into an overall score or declare a winner; the goal is to identify which Khostty deltas survive.


## Live K-E03 verification draft

Draft #8 (`experiment/khostty-embedding-pass6`) is based against `recovery/frozen-a29aa9c-pass6`, not moving main. Its workflow forces a real `libghostty-vt.a` build, sets native-link discovery explicitly, requires named integration-test sentinels to appear in `cargo test -- --list`, then runs the linked terminal suite and full wrapper suite without advisory failure swallowing. Green qualifies only this linked consumer/configuration.

Current main has moved two commits beyond the source snapshot, but only in PyPI/release documentation/workflow paths. Those commits are post-snapshot implementation/operations candidates and are not silently folded into the analyzed product source.


## Pass 6 current assignment state

**K-E02 and K-E03 are ready for parallel developer-agent execution now.** K-E01's tracked-tree, high-priority ownership and agent-server mount prerequisites are sufficiently closed; remaining K-E01 semantic/history work continues but is no longer a prerequisite for these bounded experiments. K-E02 must use Ghoztty `fd3838acfa834c29e99616cdc8500c0208a13a09` as the primary same-family control baseline and may report Khostty's truthful baseline as UNMOUNTED/UNSUPPORTED. K-E03 must prove a real linked native wrapper consumer with a sentinel; a successful build with cfg-disabled integration tests is non-evidence.

General product implementation remains blocked.


### Windows comparator added 2026-09-30

Primary current Windows prior art is now `shiweis/ghostty-windows@119b9270c8585fa3ae6969c353767fab5a32e438`, not the older mattn prototype. It has a real Win32 App/Window/Surface implementation and a successful Windows GitHub Actions build+test run at the pinned head. Treat README feature-completeness as a claim, but treat source existence and CI result as concrete external evidence. Its current-upstream divergence (241 ahead / 362 behind) is part of the ownership-cost comparison. Khostty's Windows scaffold must not be implemented independently until this adapt/fork/thin-host comparison is returned.
