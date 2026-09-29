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

Pass 6 enumerated every top-level tree with untruncated Git-tree responses. Two exact inventory parts contain 2,138 non-fuzz blob rows. The unchanged `test/` tree is structurally identical to the merge base and contains a `fuzz-libghostty` family with 4,014 blobs, 4,002 of which are corpus seeds. Those seeds are one inherited verification family unless a particular seed carries a distinct obligation.

Top-level Git-object comparison against merge base gives 43 identical entries, 13 added and 6 modified, with no top-level removals. Entire large trees proven identical include `macos/`, `test/`, `include/`, `example/`, `flatpak/`, `images/`, `nix/`, `pkg/`, `po/`, `snap/`, and `vendor/`.

This sharply narrows the fork-owned architecture review to Windows, the ten-file agent stack and required hooks, wrappers/WASM/conformance/bench, plus modified build/CI/distribution surfaces. See `inventory/FORK-OWNERSHIP.{md,json}`.


## K-F11 — fork-aware caller graph corroborates that the new agent IPC is not mounted by application startup

A fork-aware GitHub code-search pass at the frozen repository searched the concrete integration symbols rather than filenames alone. `AppHost` appears only in `src/apprt/ipc/app_host.zig`, `protocol.md`, and the historical WBS. `Server.bind` appears only in the protocol example, server implementation and WBS. `pane.Manager.init`, broker initialization and `setEventBroker` similarly remain inside IPC implementation/tests/docs. No application startup/runtime caller was returned.

This does not prove mathematical absence from generated/reflection mechanisms, but combined with protocol §7's explicit statement that the server is not started from the app, it meets the reasonable falsification standard for the **current frozen source mounting question**: the new agent protocol is implemented as modules but not mounted into the running application.

Consequence: K-E02 may treat “Khostty new agent IPC unavailable/Unsupported at baseline” as an expected truthful baseline rather than spending another archaeology pass trying to discover a hidden mount. Any experimental wiring must be a scoped, separately evidenced change and may not rewrite v1 display-feed semantics into child input.
