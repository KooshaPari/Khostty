# Khostty candidate mature contract and ontology

Program KR-20260929. Source a29aa9c6553d9f42aa68e2919116c0f6d53f329d. Status: PROPOSAL, NOT ACCEPTED; evidence and authority gaps are in FINDINGS.md. This is an initial semantic model, not a complete requirements catalog.

## Horizon before stages

The repository suggests an owned terminal runtime preserving upstream semantics, exposed through native hosts and embedding interfaces, with explicit machine control. It does not yet establish whether the accepted product is primarily a library, desktop terminal, or both. Preserve these as independent projections over a possible shared core; do not silently choose full-fork maintenance or build a new agent platform inside a terminal.

Candidate mature outcome: a human, authorized automation client or embedding consumer can create/use/inspect/close terminal state through a documented supported configuration, distinguish display input from child-process input, and receive truthful scoped capability and failure results. Platform and ABI obligations must be recovered rather than invented. A mature supported configuration is more specific than an OS name: host/runtime, artifact, architecture, terminal engine revision, protocol/ABI version and relevant settings matter.

## Product-derived projections (not one uniform tree)

| Projection | Entities / relations | Important non-equivalence |
|---|---|---|
| Terminal semantics | Terminal state, parser, display, input modes, screen/scrollback, configuration | Rendering command text is not running a command |
| Native experience | Instance, window, tab, split topology, focus, child session | A DLL or CLI build is not a working GUI |
| Embedding | Library artifact, ABI, owning consumer, allocation/thread lifetime, callbacks | A type or header is not an exercised consumer |
| Machine control | Principal, capability, request, target pane, response, event subscription | Request acknowledged is not effect observed |
| Lifecycle | Instance epoch, pane identity, child identity, closing/exited/unknown state | Reused numeric handle is not the same pane after restart |
| Verification / provenance | Accepted criterion, candidate configuration, observation, verifier and raw artifact | Confidence in an inferred trace edge is not authority |
| Delivery / operations | Build, package, installation, upgrade/rollback, support policy | Publishing an archive is not clean-host qualification |

Pillars/capabilities/features may refine this graph asymmetrically. Generic security, accessibility and reliability constraints should attach as shared overlays to relevant subjects, not be cloned into rows for every command. Do not place optional UI/embedding projections on the critical path of an unrelated stage without accepted product intent.

## Identity and state decisions to resolve

Pane identity should be scoped to its terminal instance/epoch; a logical workspace identity may persist, but its live process/handle must not be fabricated after termination. Creation needs causally attributable completion, not the first unrelated new surface. Unsupported operations should be discoverable and fail explicitly. Unknown exit status must remain unknown. Event loss needs explicit detection and a resynchronization strategy.

These are candidate obligations motivated by K-F01–K-F04 and the user's evidence doctrine. They need accepted rationale and concrete scope before entering a normative requirement set. Whether terminal sessions survive application restart is a product choice; this document does not promise it. At minimum recovery truth must distinguish surviving session, reconstructed configuration and terminated child.

## Actor-to-outcome journeys and stage projections

- **K-J-OPERATE:** human installs a supported native artifact, starts a child, interacts with terminal semantics, creates/navigates panes, observes exit, closes and reopens with the documented state policy.
- **K-J-AUTOMATE:** authorized client discovers capabilities, targets a real pane, performs a declared operation, verifies the intended effect, detects errors/loss and reconnects without affecting an unintended pane.
- **K-J-EMBED:** consumer installs a versioned library/binding, creates and feeds terminal state, consumes outputs/callbacks and frees it safely under documented threading/ownership.
- **K-J-SERVICE:** operator upgrades or rolls back, diagnoses a failure and identifies exactly which artifact/configuration was qualified.

These are candidate journey identities, not a checklist proven implemented. Earliest usable projection (CVP) should close one approved audience journey on one supported configuration using the same identity and outcome model intended for maturity. MVP adds the required human/machine or embedding companion path, not merely more commands. Beta widens qualified platforms/consumers and recovery cases. GA requires the accepted install/support/security/accessibility/release obligations. Mature adds only recovered obligations and qualified configurations; it is not an arbitrary feature-count target.

Selection between native-first and embedding-first is blocked on product-intent/existence evidence. FakeHost-only protocol success is a primitive, not an earlier usable product stage.

## Transition debt

- Existing v1 pane.write semantics must remain explicitly display-feed; child input needs a distinct operation/version contract rather than a silent behavioral flip.
- Current surface-diff creation and raw pane IDs may require a compatibility adapter around a causal/epoch-aware model. Evaluate migration, not an unplanned rewrite.
- Windows scaffold cannot inherit GTK qualification. Keep native transport/UI/PTY obligations separately blocked until witnessed.
- Keep upstream compatibility and custom fork delta independently traceable so upstream updates do not silently invalidate acceptance.

## Requirement representation when the denominator closes

Each distinct accepted obligation receives a stable ID, statement, rationale, authoritative source/decision, parent capability, dependencies, product role, stage/config applicability, journeys, positive and counterexample acceptance, applicable overlay references, implementation/work surfaces, verification strategy, required traces and growth disposition. Implementation states distinguish specified, present, mounted/reachable, persisted, tested and evidenced; stale/conflicting are separate states. None may be inferred from filenames or counts. Scope changes revise the baseline explicitly and do not improve engineering progress retroactively.
