# Khostty product usability and finish plan

Observation: 2026-10-16 Pacific. Source: `4c9e4c57a1138087053ba740083bb2d665348b6d`. This additive assessment preserves canonical platform/protocol contracts and existing repair lanes. It does not certify a new release or change product scope.

**Direct answer: a Windows installer exists and has historical install/uninstall plus CLI/DLL receipts; current installed Windows GUI terminal usability is not established.** Main still has unimplemented Windows application lifecycle and renderer methods. Draft PR33 contains substantive native implementation and successful component checks, but explicitly claims no GUI launch. Current macOS/Linux installation and complete agent/embedding journeys are separate proof obligations.

| Document                              | Purpose                                                                             |
| ------------------------------------- | ----------------------------------------------------------------------------------- |
| [State and journey](STATE.md)         | Actual install/run evidence, Windows versus other platforms, user-facing blockers   |
| [Goal matrix](GOALS.md)               | Inherited capabilities, fork-specific deltas, stubs, test-only and integration gaps |
| [Finish plan](FINISH-PLAN.md)         | Finite horizons, dependencies, effort ranges and conditional calendar scenario      |
| [Evidence and decisions](EVIDENCE.md) | Exact source/release/PR anchors and unresolved ownership/retirement questions       |

## Finite value and finish definitions

The fork's value is preserving Ghostty's terminal experience while adding a useful native Windows runtime, safe agent control and packaged polyglot embedding. Rewriting the terminal parser or creating a divergent desktop experience is not the goal. Keep upstream engine reuse and thin platform/binding adapters; justify retained fork divergence with consumers and native behavior.

| Horizon                      | Proposed acceptance slice                                                                                                                                                                                  | Remaining effort               |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------ |
| Core value proposition (CVP) | An isolated Windows build installs, opens a real usable terminal, runs shell workloads correctly, handles core input/render/resize/close and coexists with upstream; existing Mac/Linux behavior preserved | 19-43 engineer-days            |
| Minimum usable product (MVP) | CVP plus genuine required conformance/binding proof, release/rollback and accepted local agent-control consumer path                                                                                       | 24-55 engineer-days cumulative |
| Full mapped maturity         | MVP plus retained accessibility,international input,DPI/font/performance and native parity refinements with comparative evidence                                                                           | 30-67 engineer-days cumulative |

These are low-confidence engineering estimates, not a fabricated completion percentage. One engineer-day is about eight focused hours including review and acceptance. Existing candidate reuse is assumed. The [plan](FINISH-PLAN.md) gives package ranges and explicit calendar assumptions; it does not promise a delivery date or waive a required behavior.

## Proof boundary

This documentation task ran no product builds/tests, installations, service controls or captures. Historical receipts are dated and artifact-bound where possible. Open PR checks are candidate evidence; they do not make current main or the installed desktop usable. No upstream publishing is authorized or performed. This branch targets only `KooshaPari/Khostty` under the explicit documentation-publication assignment.
