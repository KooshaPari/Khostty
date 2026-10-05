# Khostty vertical slice and independent oracle design

Status: CANDIDATE DESIGN, not implemented or accepted. Source baseline a29aa9c6553d9f42aa68e2919116c0f6d53f329d. Related: K-F01–K-F06, K-J-AUTOMATE. Shared control doctrine is indexed in PhenoRegistry draft #593; product-specific obligations remain here.

## Proposed native slice

On one explicitly qualified native build, a real authenticated client discovers capabilities and creates a causally identified pane. A test child process, launched from a known executable and working directory, accepts a nonce-bearing input and writes an independent receipt into a verifier-owned temporary location. The client reads the expected terminal state/event; an independent observer compares the child receipt, pane/epoch identity and raw protocol trace. The automation client is killed/replaced and reconnects; terminal/product state follows its documented policy. The pane is closed, and subsequent stale-target actions are rejected.

This slice requires an actual mounted Host, app-thread dispatch, native PTY and observable human interface where applicable. FakeHost, rendered `ls` text, declared dependencies or a byte-count response are insufficient. The current v1 display-feed operation is tested separately: its nonce may appear on screen but must not produce a child receipt. It cannot satisfy the child-input criterion. If native-first intent is rejected, use the embedding journey instead; do not call that a GUI qualification.

## Concrete adversarial design

| Case | Fixture / intervention | Accepted observation / false-green defense |
|---|---|---|
| Positive child operation | Known child echoes fresh nonce and writes independently observed receipt | Matching candidate, instance epoch, pane, child PID/start identity and nonce; both intended effects present |
| Display-feed counterexample | Inject the identical command text through parser-only operation | Display output may occur; child-execution criterion remains unmet |
| Wrong scope | Another pane prints same nonce or numeric ID is reused after restart | Observation is not transferable across pane/epoch/child identity |
| Unauthorized | Missing/wrong token, disallowed operation, sibling client | Rejection and no child/screen side effect; inability to observe is not success |
| Invalid request | Oversized frame, malformed ID/options/version | Explicit error and bounded resources; no coerced target or silently ignored required option |
| Concurrent creation | Human creates another split while client requests one | Response identifies the causally requested pane or reports uncertainty/failure |
| Race / dependency loss | Child exits or GUI closes between lookup and execution | Accurate terminated/unavailable state, not a fabricated successful result |
| Lost events | Overflow subscription queue or reconnect mid-event | Explicit loss/resync boundary; missing event is not evidence nothing happened |
| Restart / worker replacement | Replace agent process independently from app and child | Durable development effort persists; product state reports real survival/termination rather than inventing continuity |
| Shutdown pressure | Idle clients and blocked writers during teardown | Bounded clean shutdown without detached-worker access to freed state; requires native instrumentation |
| Regression / collector failure | Break mailbox wiring, replace Host with fake, suppress receipt collection | Native criteria become FAIL/BLOCKED; protocol-only green cannot compensate |

## Grader boundary and evidence identity

The worker may inspect the rubric but may not authorize its changes. Acceptance policy and expected-case set must be pinned from a separately accepted baseline outside the implementation candidate's authority. Trusted verification reads raw artifacts, not worker-composed summaries. Changing the rubric, deleting a negative control or reducing supported scope requires a separately recorded authorized decision and scope delta.

Evidence envelope: product; capability/journey; contract revision; criterion; candidate binary/source/package digest; supported configuration; environment/OS/host/tool versions; target instance epoch/pane/child identity; verifier and policy version; evaluation/run ID; timestamp; raw artifact digest/location; collection status; observation and authority/provenance. Incomplete identity, collector error, skipped expected check, stale/wrong candidate, empty result set or conflicting evidence cannot produce acceptance.

No-result and not-applicable are different. Not-applicable requires an accepted configuration rule, not worker discretion. A security/identity/native-journey failure cannot be averaged away by many parser tests. Report functional, traceability, evidence, journey, regression, performance, reliability, security, accessibility/usability, uncertainty and transition-debt dimensions only where defined. Position/delta may be shown against the same baseline; velocity or oscillation needs comparable dated observations. No asymptote or trend exists from this single pass.

## Three independent lifetimes

Worker attempt: model/tools/process/worktree/lease/actions, replaceable. Durable development effort: accepted change intent, spec revisions, work packages/dependencies/reviews/receipts/grader history. Product state: accepted product identity/configuration, builds/releases, actual terminal/child state and product evidence, independent of the agent. Existing repository/CI/evidence infrastructure should host development records; this does not require putting a development platform inside the terminal.

Work completion is not product acceptance. An application restart is not the same event as worker replacement. No worker may mint missing product continuity. Human review is required for currently unresolved subjective scope; it is not a substitute for deterministic native-effect checks.
