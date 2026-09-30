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


### K-E03 exact native-link witness

Before any wrapper result is accepted, capture the build-script line `khostty-vt: linking <path> (<kind>)`, hash that exact library, and run a required sentinel test compiled under `ghostty_vt_linked`. The current build script intentionally returns successfully when no library is found, and `tests/terminal.rs` is entirely guarded by `#![cfg(ghostty_vt_linked)]`; therefore zero executed native integration tests is an expected developer convenience state, not evidence. Report test count and at least one runtime operation (create terminal, VT write, resize/query, callback, drop) from the exact linked candidate. Compare wrapper-only value—RAII/error mapping/package ergonomics—against direct inherited C API use; do not re-credit inherited terminal semantics as wrapper differentiation.


## Pass 6 delta — do not redo completed inventory

Tracked-tree enumeration is structurally complete: 2,138 exact non-fuzz blob rows plus a separately bounded 4,014-blob fuzz family (4,002 corpus seeds). High-priority merge-base ownership is also resolved: top-level 43 identical / 13 added / 6 modified / 0 removed; Windows 11/11 added; selected terminal C ABI 36/36 inherited. Public `apprt.ipc` is the inherited legacy module relocated into a directory; the ten new JSON agent files are adjacent and no native application caller for `AppHost` / `Server.bind` / runtime event publishing was found.

**Next executable Khostty work:** do not spend a turn re-enumerating Git. On a native-capable checkout, first reproduce the unmounted baseline (agent endpoint absent/unsupported), then implement the smallest reversible lifecycle spike that constructs the real host/pane manager, binds the new server under explicit local policy, proves a nonce read/control roundtrip against a real child, proves stale/wrong-target non-effects, and shuts down cleanly. Keep child-input semantics separate from terminal display-feed injection. In parallel only if files are disjoint, run one real wrapper consumer against direct upstream integration. Return exact binary/source/environment identity and raw receipts. This remains experimental; no merge/release.


## Pass 6 K-E02 security scope

Do not compare local IPC security by feature labels such as “token” versus “socket permissions.” Khostty's shared token authenticates possession within the user session; it does not inherently distinguish mutually untrusted same-user processes. K-E02 must state the intended adversary, record actual runtime/socket modes, token lifecycle, and test any claimed per-client/per-pane isolation. If same-account agent isolation is required, treat peer/process identity or delegated capability policy as a separate design problem rather than overclaiming the shared token.


## Pass 7 delta — wrapper evaluation target

K-E03 should not compare terminal semantics as though the wrappers implement a new VT. Rust, Go, Python and WASM wrapper code is fork-owned, but inspected surfaces call the inherited `libghostty-vt` C API. Their candidate value is safer/idiomatic ownership, lifetime/error/ABI validation, packaging and consumer ergonomics. Rust explicitly provides RAII and confines unsafe FFI; Go wraps opaque handles with Close/finalizers; Python uses cffi plus runtime manifest verification; WASM uses the inherited type manifest to drive memory/layout helpers.

**K-E03 experiment:** for one language first (Rust preferred because its ownership contract is strongest), build the same consumer directly against upstream C/libghostty and through the wrapper. Exercise create → VT feed → resize → read/render → snapshot/restore → search → free, plus wrong-version/ABI and use-after-close/error controls. Compare application unsafe/FFI LOC, lifetime failure modes, generated-vs-handwritten binding drift, packaging friction and maintenance delta. Do not award points for inherited parser correctness. If the wrapper materially reduces unsafe/lifetime burden without owning a forked terminal, consider extracting/upstreaming it rather than using it to justify the whole fork.


## Pass 8 K-E03 evidence contract

A wrapper experiment cannot qualify on `cargo check`, docs, or pure-language tests. Rust `build.rs` intentionally warns and continues when no prebuilt libghostty-vt is found. Require:

- exact Khostty/upstream library source SHA, built artifact SHA-256, target/config and path;
- build output proving `ghostty_vt_linked`/linker path was active;
- actual consumer process exit + screen/snapshot/search observations;
- use-after-close/error control and ABI/binding drift control;
- the same consumer written directly against upstream C/libghostty as comparator;
- a clean out-of-tree consumer directory so checkout-relative linking is not mistaken for distributability;
- measured application unsafe/FFI LOC, wrapper-specific LOC/dependencies, install steps and failure modes.

Go/Python/WASM remain later projections unless Rust reveals a product-level obligation they uniquely test. Do not multiply four languages into four independent reasons for the terminal fork to exist.


## Pass 9 K-E02 threading gate — do not mount Server directly

Frozen AppHost explicitly states that server connection handlers run on separate threads while terminal/app state is owned by the app IO thread; the host mutex only serializes IPC callers and does not make concurrent app-thread access safe. Surface.queueIo is the existing IO-thread message path but is private to Surface.zig.

Therefore K-E02 must be split:
1. **K-E02a app-thread bridge:** add the smallest runtime-owned message/mailbox API needed for agent operations, with request correlation/completion and cancellation/shutdown semantics. Do not expose raw terminal pointers across threads. Parser/display feed and PTY child input remain separate operations.
2. **K-E02b server lifecycle:** only after E02a tests, construct AppHost/manager/broker/server from a real windowed runtime lifecycle, bind/start under explicit local policy, and deinit before app-owned state is freed.
3. **K-E02c native oracle:** real pane identity, nonce effect appropriate to the operation, concurrent unrelated pane creation, wrong/stale target, controller replacement, event loss/resync, and shutdown with an idle client.

A direct Server.bind(... AppHost.host()) from GTK init that leaves connection threads touching app state is an automatic FAIL even if protocol tests pass. Windows remains out of this slice because its App lifecycle is unimplemented at the frozen source.


## Pass 9 authoritative product constraint

Current user intent confirms Khostty is intentionally a substantial Ghostty fork and programmable terminal precursor/infrastructure for HeliosLab. **Do not optimize K-E02 toward deleting the control plane or replacing Khostty with a thin external adapter.** Optimize the fork by minimizing unnecessary divergence while realizing the accepted capabilities: Windows, deeper Zsh/PowerShell/platform behavior, and a cmux-class socket/API control plane that removes AppleScript/UI automation for supported terminal operations.

For K-E02, use external terminals as design priors. A mature resource graph should be able to represent at least instance/epoch → workspace → window/tab → pane → terminal/child, with stable targeting, capability discovery, explicit errors, events, controller replacement and stale-target rejection. Exact naming/API compatibility is not required. The experiment should mount the existing agent server through the real application lifecycle in a way that can grow toward that graph rather than hard-code one-off pane commands.
