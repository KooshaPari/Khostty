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
