# Semantic findings — Khostty, pass 2

All source observations bind to `a29aa9c6553d9f42aa68e2919116c0f6d53f329d`; recovery work observed 2026-09-29. Repository gate labels are historical/imported assertions unless the exact acceptance witness is independently qualified.

## K-F01 — G4 DONE is contradicted by the normative protocol's native integration state (blocking)

The deep WBS marks **G4 Agent/IPC Surface DONE**. The same frozen tree's normative `src/apprt/ipc/protocol.md` §7 says the app-thread hop is not wired, the server is not yet started from the app, real-runtime `pane.focus` and `pane.search` return `host_unsupported`, shutdown does not force-close live connections, and pane creation relies on a bounded surface-list diff.

This is not evidence that the IPC modules are fake: protocol/parser/auth/manager/server work may be real and tested. It is evidence that **module completion != mounted native agent journey**. G4 cannot qualify K-J-AUTOMATE until a non-fake app-started Host and supported-capability matrix are witnessed. FakeHost lifecycle tests are supporting evidence only.

## K-F02 — VT display feed and child input are distinct obligations

`app_host.zig` routes current `pane.write` to `terminal_stream.nextSlice`. Protocol v1 explicitly says it writes VT bytes into the parser and does **not** type into the child process. This is internally consistent narrow behavior, not a v1 direction bug.

Mature scope must name display-feed and child-input separately. A child-operation oracle requires a nonce-bearing child-process effect. Rendering command-looking text or returning a byte count cannot satisfy it. If child input is required, add/version a distinct contract rather than silently changing v1 semantics.

## K-F03 — documented pane-create semantics exceed current real-host implementation

Protocol `pane.create` documents cwd/focus behavior and focus targeting. The inspected real-host create body uses parent/direction/title but does not establish cwd/focus=false semantics; direct focus is Unsupported. Creation attribution is a before/after surface diff because upstream `new_split` returns no handle. A concurrent unrelated surface creation is therefore a concrete adversarial design case, though not reproduced in this pass.

Required closure: explicit supported/unsupported option policy, causal creation identity, app-thread-safe completion and concurrent creator fixture. Ignored required options may not be reported as accepted behavior.

## K-F04 — Windows/native evidence is narrower than the WBS gate language

The deep WBS records a real Windows executable `+version` run and live `ghostty-vt.dll` ABI operations, which is stronger evidence than the earlier registry snapshot. The same evidence explicitly says no GUI window was launched in that Windows run. Elsewhere the WBS records a headless GTK Xvfb GUI launch and macOS interactive launch.

These are valuable, different witnesses: Windows executable selection/ABI, Linux headless GUI, macOS GUI. They are **not interchangeable**. A cross-platform native journey must bind evidence to platform/runtime/configuration rather than inherit a gate-wide green.

## K-F05 — source search and stale registry can understate real work

Default wrapper search missed known fork files; fork-aware retrieval and direct file reads found them. GitHub metadata identifies `ghostty-org/ghostty` as parent/source. The README's `1jehuang/khostty` clone reference remains a lineage lead, not proven parentage. The September 16 registry STATE is historical and expressly bounded.

The recovered September 16 user instruction is narrower and useful: identify the **actual owned terminal delta** and test native correctness and its intended integration. It does not establish that every WBS-added surface is accepted mature scope. Earlier user context includes Ghostty usage and a May headless-agent/TUI-projection idea, but no product-specific Khostty fork rationale was recovered.

## K-F06 — historical CI false greens were repaired; current commit status is still not a completion witness

The frozen source commit repairs ecosystem detection that silently skipped nested Rust, Go and TypeScript jobs; earlier commits repaired a duplicate job key. The connected combined-status query for the frozen SHA returned no legacy commit statuses. That absence is not a CI failure and not a green: checks may live in another API surface.

Closure requires an expected-job manifest against the exact candidate and actual check-run/artifact receipts. A workflow with missing expected jobs, skipped collectors or wrong candidate cannot qualify.

## K-F07 — existence gate: automation itself is commodity; Khostty must prove a narrower owned delta

Current official documentation shows:
- WezTerm `split-pane` returns the new pane ID, accepts cwd/program and can target a pane; `send-text` feeds pane input and `get-text` reads screen/scrollback.
- kitty remote control can launch/focus windows, send text/keys and get text with scoped matching/authorization.
- cmux exposes CLI + Unix-socket control, capabilities, explicit surface IDs, split-with-command, focus and input; its TUI also advertises a durable workspace/pane/tab tree across macOS/Linux/Windows.

Therefore generic local JSON/CLI pane automation, child input and text inspection are **already commodity/contested**. Khostty's current v1 real-host gaps are in areas competitors already cover. Candidate differentiation must instead be demonstrated in an accepted owned-terminal/embedding/native-integration workflow, upstream semantic fidelity, or materially lower integration/maintenance burden. No superiority claim is accepted.

## K-F08 — product authority remains deliberately open, but is no longer 'nothing recovered'

Conversation archaeology recovered the September 16 user objective: identify Khostty's actual owned terminal delta and test native correctness and intended integration. It also recovered broader May intent for a headless agent plane that controls CLI/TUI processes and projects them into a user-facing interface. These constrain research but do not prove that Khostty itself must own that entire plane.

Accordingly, the mature contract must not expand from WBS task inventory. First isolate the fork delta versus upstream Ghostty and realistic WezTerm/kitty/cmux alternatives; then accept only the obligations that serve the intended integration. This remains a blocking authority/existence question, not permission to start a third repo.


## K-F09 — same-family prior art further falsifies Ghostty+agent-IPC differentiation

A 2026 web research pass located `dzearing/ghoztty`, a Ghostty fork whose stated purpose is CLI-driven window management for AI coding agents. Its documented commands create/focus named windows, split relative to a target with cwd/command, close targets, and use Unix-socket IPC. This is unusually close prior art: the relevant alternative is no longer merely “another terminal with remote control,” but another Ghostty-derived implementation aimed at coding-agent pane orchestration.

This does not prove Ghoztty meets Khostty's accepted needs or should be adopted. It changes the bootstrap burden. Before retaining custom Khostty agent IPC, compare exact required journeys, upstream divergence, platform coverage, identity/idempotency, child input, inspection/events, authorization, embedding and maintenance. If Khostty's accepted delta can be supplied by upstream Ghostty + Ghoztty-like thin changes, a broad parallel IPC architecture is not justified by uniqueness.

Research source: https://github.com/dzearing/ghoztty (retrieved 2026-09-29). Treat README claims as external prior-art assertions until source/revision/license and runtime behavior are qualified.


## K-F10 — fork delta is measurable and creates upstream-drift debt

A GitHub compare of Khostty main against current `ghostty-org/ghostty:main` reports status `diverged`: Khostty is 207 commits ahead and 145 behind, with merge base `d4c88d8069912b653d707191388ca98e24751f12`. The file delta spans conformance/bench infrastructure, Windows runtime, agent IPC, polyglot wrappers, packaging/CI/docs and other fork work.

This falsifies the simplifying model “Khostty is just an IPC patch.” It also makes upstream drift a first-class transition-debt dimension. The correct existence decision is per subsystem: valuable conformance/ABI/wrapper work may be separable from agent IPC; Windows hosting may justify a host/fork delta even if IPC does not. See `FORK-DELTA-DECISION-LEDGER.md`.

Current upstream is a moving comparison target, so 207/145 is a dated research observation, not a permanent metric or the historical baseline for all changes.


## K-F11 — public IPC import is inherited Ghostty IPC, not the new agent server (blocking reachability clarified)

At the frozen source, `src/apprt.zig` exports `apprt.ipc` from `src/apprt/ipc/mod.zig`. The merge base instead exported `src/apprt/ipc.zig`. Those two modules have the same 253-line body after normalizing only the two relative-import paths changed by moving the file one directory deeper. In other words, the public `apprt.ipc` import is the inherited three-action Ghostty IPC relocated into a directory.

The ten new agent-control files adjacent to it — including `app_host.zig`, `auth.zig`, `events.zig`, `handler.zig`, `pane.zig`, `protocol.zig`, `server.zig`, and support files — are fork-owned, but `mod.zig` does not become their application bootstrap merely by sharing a directory.

This resolves an important naming trap in earlier architecture docs: **“IPC is imported” does not mean “the new JSON agent server is mounted.”**

## K-F12 — native agent-server call graph remains disconnected at the application boundary

The frozen normative protocol already states that the app-thread hop is not wired and the server is not started from the app. Pass 6 adds structural corroboration:
- `AppHost` references are confined to its own implementation, protocol/WBS documentation, and subsystem context in current indexed source;
- `Server.bind` is found in the server implementation and worked examples/docs, not an application startup path;
- `publishTitleChange` has no caller outside `app_host.zig` in current indexed source;
- `auth.setup` is represented as an example/protocol setup, not an app boot hook;
- `src/apprt.zig` imports only inherited `ipc/mod.zig`, not `server.zig` or `app_host.zig`.

The code-search corroboration is from the repository's current indexed default branch rather than an immutable-ref search, so it is supporting evidence, not the sole absence proof. The stronger frozen-snapshot facts are the exact module bodies and protocol §7 admission.

Result: K-J-AUTOMATE is not merely “untested”; the product's new agent server is **not currently part of the normal application startup graph** at the analyzed snapshot.

## K-F13 — fork ownership denominator is now substantially resolved without turning inherited bulk into requirements

Pass 6 enumerated every top-level tree with untruncated Git-tree responses. Two exact inventory parts contain 2,117 raw A+B rows with 62 overlaps, yielding 2,055 unique non-fuzz paths. The unchanged `test/` tree is structurally identical to the merge base and contains a `fuzz-libghostty` family with 4,014 blobs, 4,002 of which are corpus seeds. Those seeds are one inherited verification family unless a particular seed carries a distinct obligation.

Top-level Git-object comparison against merge base gives 43 identical entries, 13 added and 6 modified, with no top-level removals. Entire large trees proven identical include `macos/`, `test/`, `include/`, `example/`, `flatpak/`, `images/`, `nix/`, `pkg/`, `po/`, `snap/`, and `vendor/`.

This sharply narrows the fork-owned architecture review to Windows, the ten-file agent stack and required hooks, wrappers/WASM/conformance/bench, plus modified build/CI/distribution surfaces. See `inventory/FORK-OWNERSHIP.{md,json}`.


### Additional evidence for K-F12 — fork-aware caller graph corroboration

A fork-aware GitHub code-search pass at the frozen repository searched the concrete integration symbols rather than filenames alone. `AppHost` appears only in `src/apprt/ipc/app_host.zig`, `protocol.md`, and the historical WBS. `Server.bind` appears only in the protocol example, server implementation and WBS. `pane.Manager.init`, broker initialization and `setEventBroker` similarly remain inside IPC implementation/tests/docs. No application startup/runtime caller was returned.

This does not prove mathematical absence from generated/reflection mechanisms, but combined with protocol §7's explicit statement that the server is not started from the app, it meets the reasonable falsification standard for the **current frozen source mounting question**: the new agent protocol is implemented as modules but not mounted into the running application.

Consequence: K-E02 may treat “Khostty new agent IPC unavailable/Unsupported at baseline” as an expected truthful baseline rather than spending another archaeology pass trying to discover a hidden mount. Any experimental wiring must be a scoped, separately evidenced change and may not rewrite v1 display-feed semantics into child input.

## K-F16 — same-family prior art already closes child-input, read/inspection, targeting and persistence primitives

Pinned Ghoztty source `fd3838acfa834c29e99616cdc8500c0208a13a09` was inspected beyond README claims.

Source-level observations:
- `src/cli/send_keys.zig` explicitly writes text/keys to a named pane's **PTY as user input**, including bracketed-paste versus key segmentation and unknown-flag rejection.
- `src/cli/read.zig` requests the last N lines of a named pane and emits plain text from the server response.
- `src/apprt/ipc.zig` bakes both `GHOZTTY_IPC_SOCKET` and `GHOZTTY_PANE_ID` into pane environments, so commands can address the owning app and caller pane rather than relying only on current focus; explicit target flags override the implicit caller.
- macOS `IPCServer.swift` owns a target registry with weak-reference liveness, prunes stale entries, dispatches list/read/send-keys/lifecycle/rearrangement actions, binds an AF_UNIX socket, marks its fd close-on-exec and `chmod(..., 0o600)`.
- `docs/design/session-persistence.md` describes and reports E2E work for an agent-owned PTY/session layer that survives app update/crash, reattaches by session ID and distinguishes process survival from reboot relaunch. Its own document still marks some criteria unmeasured/unbuilt, so those claims remain source assertions rather than our reproduced measurements.

Architecture consequence: Khostty cannot justify its custom agent IPC by the previously proposed needs “real child input,” “read terminal text,” “avoid wrong focus/instance,” or “survive controller replacement” in the abstract. Same-family prior art already implements substantial versions of each. Khostty's currently distinct IPC concepts—structured synchronous state/search, event subscription/drop semantics, explicit application token auth and intended cross-platform transport—must each prove an accepted unmet need and integration advantage. A token does not by itself justify a separate broad IPC stack because the alternative can compose an additional authorization layer.

The K-E02 bake-off therefore treats Ghoztty as the primary same-family control baseline rather than a secondary comparison. Khostty baseline is allowed to report the truthful current state “new agent IPC not mounted.” The experiment must compare product effects and maintenance cost, not command-name parity.

## K-F17 — Windows hosting is now commodity/contested implementation, not unique differentiation

Current upstream Ghostty `f9e82709360d97b2246718f774c544de0f16787b` still has only `none` and `gtk` application runtimes and no `src/apprt/windows` directory, so Windows remains an upstream product gap.

However, pinned external fork `shiweis/ghostty-windows@119b9270c8585fa3ae6969c353767fab5a32e438` materially contests Khostty's Windows thesis:
- actual `src/apprt/win32/App.zig`, `Window.zig`, and `Surface.zig` contain Win32 lifecycle, WGL rendering, ConPTY/core-surface integration, tabs/splits, input/IME/search and window-management code rather than scaffold stubs;
- its repository is an MIT-licensed direct fork of `ghostty-org/ghostty`, created 2026-03-18 and pushed through 2026-09-02;
- its own compare against current upstream is 241 commits ahead / 345 behind with merge base `20abdb50a6216c450d6d4d010c41c7edf5ab15b2`, so it demonstrates both substantial implementation and substantial drift burden;
- its `Windows CI` workflow at blob `d01be34404fce382fe71cd568aa8151193bc2db9` runs on `windows-latest`, executes `zig build test -Dapp-runtime=win32 -Dtarget=x86_64-windows-gnu`, then builds the app; the pinned head `119b927…` has a completed SUCCESS run (`33633427282`) on 2026-09-02. This is stronger than README-only evidence, though it is still the external project's own test suite rather than our independent runtime bake-off.

The related upstream Ghostty PR #12167 was closed unmerged. Maintainer comments identify review size, unresolved Windows toolkit direction, and especially lack of a long-term Windows maintainer as major blockers; they do not establish that the implementation approach is technically invalid. The original PR also had early user-reported AltGr and kitty-graphics problems, followed by subsequent fork development. Therefore upstream non-merge is a maintenance/convergence warning, not a reason to ignore the implementation.

Architecture consequence: **building Khostty's Windows runtime from scratch is no longer the default.** K-E02 must compare at least (a) Khostty scaffold/current intended architecture, (b) adapting the pinned Win32 fork or its isolated runtime delta onto a current upstream base, and (c) a thin libghostty Windows host where applicable. Compare exact native journey behavior, upstream merge burden, patch surface, security/accessibility/IME/graphics completeness and ownership cost.

Khostty's Windows-specific product differentiation is therefore falsified at the feature-existence level. A Khostty Windows implementation can still be justified if it proves materially better integration/maintainability or serves accepted requirements the mature Win32 fork does not, but novelty cannot justify it.


### Additional evidence for K-F11 — exported IPC remains upstream while agent server is adjacent

Pass 6 resolves the ownership/mount ambiguity more sharply. At merge base `d4c88d8069912b653d707191388ca98e24751f12`, upstream has `src/apprt/ipc.zig`. Frozen Khostty exposes `src/apprt/ipc/mod.zig` through `pub const ipc = @import("apprt/ipc/mod.zig")`.

After normalizing only the two relative import paths required by moving that file one directory deeper, current `ipc/mod.zig` is textually identical to the merge-base `ipc.zig`: same 253 lines and zero normalized differences. It still defines the inherited three actions `new_window`, `new_tab`, `toggle_quick_terminal`.

The fork adds ten separate JSON-agent files beside that inherited module: `app_host.zig`, `auth.zig`, `events.zig`, `fake_host.zig`, `handler.zig`, `pane.zig`, `protocol.md`, `protocol.zig`, `server.zig`, and `state.zig`. `src/apprt.zig` does not export/start those server/host objects; it only redirects the inherited IPC import and adds/selects the Windows runtime.

Fork-aware code search at the current repository state finds `AppHost` only in its implementation, protocol and WBS; `Server.bind` only in server/protocol/WBS; and no application caller of the new server stack. This corroborates, rather than replaces, the frozen protocol's explicit statement that the app-thread hop/server startup is not wired.

Consequence: Khostty currently has an inherited mounted IPC surface and a separate unmounted agent-protocol subsystem. Tests of the latter cannot qualify a running-terminal agent journey. K-E02 may repair this only as a bounded experiment after preserving the baseline failure.

### Additional evidence for K-F13 — tracked-tree enumeration closure

Every top-level tree at the frozen source has now been enumerated with untruncated Git-tree responses. Product-local inventories persist 2,117 raw A+B rows with 62 overlapping paths, yielding 2,055 unique non-fuzz paths. The test tree is additionally resolved structurally: `fuzz-libghostty` contains 4,014 blobs, of which 4,002 are corpus seeds; the Windows test subtree has three blobs.

The 4,002 seed files are not 4,002 product obligations. Treat them as a verification corpus source family unless a particular seed encodes a distinct accepted obligation. This closes the tracked-file enumeration sub-gate, not the semantic source denominator.

Initial exact-row projection shows large inherited/common families (runtime core, upstream terminal core, upstream macOS runtime, examples/public API) alongside much smaller fork-candidate families (117 wrapper blobs, 33 WASM, 11 agent IPC, 11 Windows runtime, conformance/benchmark/CI/packaging). Ownership and user value must be resolved by semantic family, not raw file count.

### Additional evidence for K-F13 — fork ownership is narrower than topology

At the top-level Git-object boundary against the merge base, 43 current entries are identical, 13 are added and 6 modified, with no top-level removal. Entire large trees proven identical include `macos/`, `test/`, `include/`, `example/`, `flatpak/`, `images/`, `nix/`, `pkg/`, `po/`, `snap/`, and `vendor/`.

The meaningful fork candidates are consequently narrower: Windows host/runtime, the ten new agent-server files plus necessary hooks, wrapper packages, WASM distribution, conformance/bench infrastructure and fork-specific build/CI/distribution changes. The earlier 207-ahead/145-behind count is a topology/maintenance observation, not a count of differentiated capabilities.

## K-F14 — current CI can manufacture green aggregate gates from advisory failures (blocking evidence trust)

The fork-owned `.github/workflows/ci.yml` detects nested languages correctly now, but most substantive jobs are configured `continue-on-error: true`, and Rust/Python/Go/TypeScript commands frequently append `|| echo "::warning::..."`, converting tool/test failure into a successful step. The macOS build job is explicitly disabled with `if: ${{ false }}`.

The aggregate `ci / lint` gate treats downstream job result `success` or `skipped` as acceptable. `ci / test` depends only on `lint` and performs no tests; it prints `All test stages passed (gated via ci / lint)`. Therefore a required branch context named `ci / test` can be green without any independent test stage, while failed advisory tests can be swallowed upstream.

This is not merely a historical skipped-language bug. It is current workflow semantics at the frozen source. A product acceptance grader must maintain an expected-job matrix and distinguish advisory telemetry from required qualification. Skipped macOS/native work and swallowed test failures are non-green for configurations that require them.

## K-F15 — Rust wrapper integration tests can disappear when the native library is absent

`khostty-vt/build.rs` deliberately allows the crate to typecheck when no prebuilt `libghostty-vt` is found and only sets `ghostty_vt_linked` after locating a real library. `khostty-vt/tests/terminal.rs` begins with `#![cfg(ghostty_vt_linked)]`, so its native integration tests compile to nothing when the library is absent.

That behavior is reasonable for developer ergonomics but unsafe as acceptance evidence unless the expected configuration requires `ghostty_vt_linked` and records the exact native library artifact. A plain successful `cargo test` is therefore not sufficient proof that Rust↔native integration ran. K-E03 must require a linked native candidate and a positive sentinel proving at least one integration test executed.


### Additional evidence for K-F11 — exact inherited IPC normalization

Exact source comparison against merge base `d4c88d8069912b653d707191388ca98e24751f12` resolves a key ambiguity. Frozen Khostty `src/apprt/ipc/mod.zig` and upstream-baseline `src/apprt/ipc.zig` each have 253 lines and become **exactly identical after normalizing only the two relative import paths introduced by moving the file into a directory**. The public `src/apprt.zig` export points to this relocated inherited module.

The fork-owned JSON agent-control stack lives in ten adjacent files: `app_host.zig`, `auth.zig`, `events.zig`, `fake_host.zig`, `handler.zig`, `pane.zig`, `protocol.{md,zig}`, `server.zig`, and `state.zig`. The fact that `apprt.ipc` exists therefore does not mount or export that server.

Fork-aware code search corroborates the reachability boundary: `AppHost` appears only in its implementation, protocol, and WBS; `Server.bind` only in server/protocol/WBS; `publishTitleChange` only in `app_host.zig`. No application lifecycle caller was found for these hooks. Search is corroborating evidence rather than a proof of absence; the normative protocol already states app startup/app-thread integration is not wired.

Consequence: G4/module tests and inherited `performIpc` call sites are evidence for different systems. Do not use the working inherited three-action IPC to qualify the new agent API. K-J-AUTOMATE remains unmounted at the frozen source.

### Additional evidence for K-F13 — finite tracked-tree ownership

Pass 6 recursively enumerated every top-level Git tree at the frozen revision with untruncated results. Two persisted inventory parts contain 2,117 raw A+B rows with 62 overlapping paths, yielding 2,055 unique non-fuzz paths. The separate inherited `test/fuzz-libghostty` subtree contains 4,014 blobs, including 4,002 corpus seeds. Treating each seed as a distinct obligation would manufacture scope.

Top-level Git-object comparison against the merge base yields 43 identical entries, 13 added, 6 modified, and none removed at that boundary. Large trees proven identical include `macos/`, `test/`, `include/`, `example/`, `flatpak/`, `images/`, `nix/`, `pkg/`, `po/`, `snap/`, and `vendor/`. Candidate fork-owned families are consequently much narrower: Windows runtime, new agent-server files/native hooks, wrappers/WASM distribution, conformance/bench, and fork build/CI/package changes.

This closes tracked-tree enumeration and substantially narrows the ownership denominator; semantic source/history/authority/external denominators remain open.


### Additional evidence for K-F16 — Ghoztty causal-completion gap

Pinned Ghoztty source `fd3838acfa834c29e99616cdc8500c0208a13a09` contains a substantially broader control surface than the README's three-command summary. `IPCServer.dispatchAction` handles new-window, split, close, rename, rearrange, list, read, send-keys, set-state, set-banner, reload and new-remote-window. `+read` reads recent pane output; `+send-keys` explicitly writes text/keys to the target pane's PTY and supports bracketed-paste-aware delivery. Therefore Khostty cannot claim richer read/input vocabulary as differentiation without a behavioral comparison.

Ghoztty's macOS implementation also has concrete safety/identity measures: per-user/build Unix socket with optional pane-baked absolute instance socket; chmod 0600; FD_CLOEXEC; <1 MiB request frame limit; weak target references with stale pruning; caller-pane identity seeded into the child environment to reduce focus races.

However, its own design and implementation expose a materially different acceptance model. New-window/split UI mutations are dispatched asynchronously to the main queue and the IPC handler returns `.ok`/sends the response before that mutation is necessarily complete. The design explicitly calls window/split creation fire-and-forget. Thus a successful response establishes request acceptance, not causally observed pane/window creation.

Potential surviving Khostty differentiation is consequently narrower and testable:
- Windows/cross-platform native host/control where Ghoztty's design declares Windows out of scope;
- independently authenticated policy where required beyond same-user 0600 UDS;
- event subscriptions and richer machine state/search, if actually mounted and useful;
- **causally confirmed effects / stable result identity**, rather than asynchronous request acceptance.

These are candidate gaps, not wins. K-E02 must reproduce the same child-effect/identity/reconnect journey and record whether the stronger semantics justify Khostty's extra protocol/maintenance surface.


## K-F17 — Windows hosting is commodity/contested implementation, not unique differentiation

Current upstream Ghostty still has no accepted Win32 application runtime, but substantial external implementations now directly contest Khostty's Windows thesis.

Most important current comparator: `shiweis/ghostty-windows@119b9270c8585fa3ae6969c353767fab5a32e438`, pushed 2026-09-02. Its source contains a real `src/apprt/win32/App.zig` (blob `c0bbba29632fbf5f34c9d2310406d9159fd52c55`) with Win32 class registration, message-loop/app lifecycle, windows/tabs/splits, WGL rendering surfaces, ConPTY/core integration, input/IME/search/clipboard/notifications and other application actions. Root license is MIT. Its README claims feature-complete apprt coverage and daily usability; those broad quality claims remain external assertions until independently reproduced.

Unlike the older April prototype, this fork has current native CI. Workflow `.github/workflows/windows-ci.yml` (blob `d01be34404fce382fe71cd568aa8151193bc2db9`) runs on `windows-latest`, executes `zig build test -Dapp-runtime=win32 -Dtarget=x86_64-windows-gnu`, then builds the app. Pinned head `119b927…` has completed SUCCESS run `33633427282` on 2026-09-02; both Build & Test and zig fmt jobs succeeded. This is stronger than README-only evidence, though still the external project's own suite rather than our independent native journey.

Its current-upstream compare is diverged: 241 commits ahead / 362 behind with merge base `20abdb50a6216c450d6d4d010c41c7edf5ab15b2` and 96 changed files in the GitHub compare. This is material implementation and material maintenance debt.

Historical upstream PR #12167 from mattn is also instructive but no longer the strongest implementation baseline. It was closed automatically because the author was not vouched; maintainer comments separately raised review size, unresolved Windows toolkit direction and especially lack of a long-term Windows maintainer. User testing then exposed AltGr and kitty-graphics issues in the early port. These facts are maintenance/convergence warnings, not evidence that Win32 hosting is technically invalid.

**Architecture consequence:** building Khostty's Windows runtime from scratch is no longer the default. K-E02 must compare at least (a) Khostty's scaffold/intended host, (b) adapting the pinned current Win32 fork or isolating its runtime delta onto a current upstream base, and (c) a thinner libghostty-based Windows host where applicable. Compare exact native journey behavior, upstream merge burden, patch surface, security/accessibility/IME/graphics completeness and ownership cost.

Khostty's Windows-specific differentiation is therefore falsified at the feature-existence level. It can still justify its own implementation only by demonstrating materially better integration/maintainability or accepted requirements the existing Win32 fork does not meet.


## K-F11 — new JSON agent-control subsystem is adjacent to, not mounted as, public `apprt.ipc` (blocking)

Pass 6 resolves the earlier mounting ambiguity substantially.

At merge base `d4c88d8069912b653d707191388ca98e24751f12`, Ghostty had a single `src/apprt/ipc.zig` blob `d5d860a73c2087e559b09924346a4b84214cafe2`. Frozen Khostty replaces the path with `src/apprt/ipc/mod.zig` blob `cf4cad94335a511f5fa3db14364c0cae03b9f47d`. Both have 253 lines; after normalizing only the two relative import paths required by moving the file one directory deeper, their executable/text content is identical. `src/apprt.zig` exports `pub const ipc = @import("apprt/ipc/mod.zig")`.

Therefore the public `apprt.ipc` export is the inherited Ghostty IPC module, not the new JSON agent server.

The same directory also contains ten genuinely new fork files: `app_host.zig`, `auth.zig`, `events.zig`, `fake_host.zig`, `handler.zig`, `pane.zig`, `protocol.md`, `protocol.zig`, `server.zig`, and `state.zig`. Code-search reachability corroborates isolation: `AppHost`, `Server.bind`, `publishTitleChange`, `pane.Manager`, and the event-broker APIs resolve only inside this subsystem and its documentation/recovery docs; no native app lifecycle caller was found. The frozen protocol documentation itself states startup wiring is not complete.

This is stronger than “server code exists.” It means the agent-control architecture currently has implementation primitives and tests/docs but no demonstrated mounted application journey. Compile/import reachability of the legacy IPC module cannot qualify the new server.

Closure requires one native lifecycle to construct the real host/pane manager, bind the server under explicit policy, publish real runtime events, and tear down safely. A test-only FakeHost or direct server unit test does not close the journey.

## K-F12 — fork ownership denominator is far smaller than repository size

Exact top-level Git-object comparison against the merge base yields 43 identical entries, 13 added, 6 modified, 0 removed. Entire large trees including `macos/`, `test/`, `include/`, `example/`, `flatpak/`, `images/`, `nix/`, `pkg/`, `po/`, `snap/`, and `vendor/` are byte/tree-identical at this boundary.

High-priority recursive comparison further shows all 36 inspected `src/terminal/c/` public-ABI blobs identical, while all 11 Windows runtime blobs are added. The product's existence/differentiation gate must therefore evaluate the small fork-owned surfaces—Windows host, agent server integration, wrappers/WASM/conformance/build integration—not the inherited terminal as though it were Khostty-authored value.

This does not make inherited behavior irrelevant to product acceptance; it changes ownership, maintenance and alternative-stack reasoning.


## K-F18 — IPC token is a user-session control, not per-process identity

The agent IPC auth is fail-closed for non-ping requests and uses a generated token file with mode 0600. That is useful request authentication.

Its scope must still be described accurately: a token file intentionally readable by the current OS user does not distinguish mutually untrusted processes running as that same user. The inspected Unix server also does not explicitly set the socket mode after listen; supported-platform filesystem modes should be measured rather than inferred from defaults.

K-E02 must therefore state the intended threat model and record runtime-directory/socket modes, token lifecycle, and whether per-client/per-pane policy is required. If mature scope needs isolation among agents under one account, the design needs an additional identity/policy mechanism; possession of the shared user token alone is insufficient.

Do not award differentiation merely because Khostty uses a bearer token while another terminal uses an owner-only local socket. Compare the accepted trust boundary and observed behavior.
