# Semantic findings — Khostty, pass 1

All source observations below bind to `a29aa9c6553d9f42aa68e2919116c0f6d53f329d`, inspected 2026-09-29. Source reconnaissance is not the final obligation-to-implementation map: the mature contract is not accepted yet.

## K-F01 — module completion is not mounted agent control (blocking)

`src/apprt/ipc/protocol.md` (blob `d04ccbbd3d222b0c12602ea58df2647a48be371e`, lines 1–40) explicitly lists AppHost as not yet in the build graph. `app_host.zig` (blob `282d0df2b969ce46b401201fd6b408e8009c4820`, lines 1–280) says the app-thread mailbox and runtime event hooks remain integration work. Its actual windowed branch qualifies GTK only; focus and search implementations return Unsupported.

Consequence: README G4 acceptance/test counts cannot establish the native create/focus/search/observe journey. A fork-inclusive indexed AppHost search found the implementation, protocol and deep WBS, not an application caller; this is bounded corroboration, not exhaustive proof of unreachability. Needed witness: actual build/import/caller graph plus running native app with non-fake Host, explicit supported capability matrix and adversarial fixture.

## K-F02 — VT output injection and child input are different obligations (blocking semantic boundary)

`app_host.zig` lines 289–298 calls `core.io.terminal_stream.nextSlice(data)`. Protocol v1 explicitly excludes PTY input injection and reserves child typing for v2. Therefore the observed implementation is consistent with this narrow declared behavior. It is **not** justified to call this a v1 write-direction bug. A README example resembling a shell command is not proof of executing it.

Needed mature decision: independently name display-feed and child-input capabilities. A child execution oracle must observe a nonce-bearing child-process effect, not merely rendered text or a successful byte count. Do not silently change v1 semantics while fixing a broader journey.

## K-F03 — documented pane options and runtime semantics disagree (blocking reconciliation)

Protocol pane.create documents cwd and focus=false effects and a focus mapping. The inspected `createWindowed` body uses parent/direction/title but does not use cwd/focus; direct focus is Unsupported. It identifies a new pane by before/after surface difference, not request-correlated creation identity. Concurrent human creation could invalidate attribution; that is a hypothesis requiring a runtime experiment, not a reproduced failure.

Needed: exact option support/rejection policy, causal creation handle, app-thread-safe completion and tests with two concurrent creators. Do not let ignored options report accepted behavior.

## K-F04 — server lifetime/resource unknowns (high-risk, unconfirmed)

`server.zig` blob `8f4fb7b7e5843db55a6294b2cfa6b43fced54b18`, lines 1–260: per-connection threads, frame-size allocation, detached workers, five-second connection drain, and socket replacement. The inspected extent does not establish an aggregate connection cap, ownership-safe socket replacement, or lifetime safety after a drain timeout.

Needed: complete body and caller teardown analysis, idle/malicious clients, shutdown/restart and concurrent socket-owner tests. This is not a security or memory-safety exploit confirmation.

## K-F05 — source search and stale registry can understate real work

Default wrapper searches returned empty for known Khostty source; fork-inclusive REST search returned actual frozen-revision matches. Repository metadata identifies parent/source as ghostty-org/ghostty; the README reference to 1jehuang/khostty is an alias/lineage lead, not proven parentage. Registry STATE sampled `79e27b63f96669b26f1346a1b9985c327311bd6e` on September 16 and expressly disclaims a full audit.

Needed: fork-aware history/tree inventory and separate historical/current assertions. No claim that work did not happen because a search or old snapshot did not see it.

## K-F06 — historical CI false green was repaired, current matrix still unqualified

The analyzed source commit repairs ecosystem detection that silently skipped nested Rust, Go and TypeScript jobs. This is evidence of a historical guard defect and a current source-level repair, not proof that the defect still exists. Required follow-up is a candidate-bound expected-jobs versus actual-jobs receipt; a green workflow containing only a subset of required jobs must not qualify the product.

## K-F07 — existence gate remains open

Official WezTerm, kitty and cmux documentation already describes programmatic pane/window control. A generic 'agent-controllable terminal' uniqueness hypothesis is falsified. Native cross-platform embedding, upstream semantics, integration cost or a specific workflow may still justify owned code, but these are unverified differentiation claims. See the independent PhenoRegistry SOTA dossier before freezing architecture.
