# Khostty candidate architecture — pass 6

Status: **preferred architecture for falsification/experiments, not accepted mature contract.** Frozen source under recovery: `a29aa9c6553d9f42aa68e2919116c0f6d53f329d`.

> **Authority correction — 2026-09-30.** Khostty's existence as a substantial Ghostty fork is current user intent and is no longer an architecture experiment. This document now uses alternatives to decide *subsystem ownership and bootstrap strategy*, not whether the product/fork should exist. Earlier wording below that treated “keep the fork” as conditional is superseded.

## Product hypothesis

Khostty is a **substantial Ghostty fork and supported terminal/runtime substrate** for Windows/platform work, shell integration, rich programmatic control, embedding/automation and HeliosLab/agent use. It should track and reuse upstream Ghostty semantics aggressively where Khostty has no accepted reason to diverge, while owning the fork deltas needed for its product outcomes.

Feature novelty is not the thesis. The relevant optimization problem is where to **USE / INTEGRATE / FORK / ADAPT / COMPOSE / LEARN FROM / REJECT / BUILD** at each subsystem boundary while preserving one coherent Khostty product, support horizon, cross-surface consistency and manageable upstream merge cost.

## Layering

```text
                   Khostty supported distribution
                              │
       ┌──────────────────────┼────────────────────────┐
       │                      │                        │
 supported native hosts   automation/control      embedding packages
       │                      │                        │
 macOS/Linux upstream     thin capability API      C upstream ABI
 Windows adapted Win32    over real AppRT/PTY      Rust/Go/Python/JS
       └──────────────┬───────┴───────────────┬────────┘
                      │                       │
              current upstream Ghostty/libghostty
                      │
          independent conformance/evidence gates
```

### Upstream core

Track upstream Ghostty closely. Parser/screen/render-state/input encoding and ABI primitives are upstream-owned unless exact diff evidence says otherwise. Khostty changes to core require an accepted capability that cannot live behind an extension point plus a rebase/exit plan.

### Windows host

Do not continue the frozen Khostty scaffold as a blank-sheet implementation. First adapt/evaluate `shiweis/ghostty-windows@119b9270c8585fa3ae6969c353767fab5a32e438` (or its isolated Win32 delta rebased to the chosen current upstream) because it already implements and tests the major native-host primitives Khostty lacks.

Owned Khostty work should concentrate on gaps that remain after that import/rebase experiment: current-upstream compatibility, security/accessibility, packaging/update support, exact accepted agent/control hooks, and independently verified native journeys.

### Agent/control layer

Start from Ghoztty-class semantics for launch/split/close/named targets/PTY input/readback/instance identity. Add only accepted missing capabilities such as structured state/search/events or explicit authorization where a real workflow needs them.

Do not preserve the frozen v1 Khostty agent protocol merely because it exists. If its protocol shape is retained, v1 parser-display feed remains distinct from child input. Prefer a compatibility adapter over silently changing meaning.

Control identity should be `{instance_epoch, pane/session_id}` or an equivalently collision-resistant scoped identity. A raw surface integer cannot establish stale-target safety across app replacement.

### Embedding packages

Treat direct upstream libghostty C/Zig API as baseline. Khostty language packages must be thin and generated/verified where possible. Their value proposition is safe ownership/lifetime/error mapping, packaging and compatibility—not ownership of inherited ABI metadata.

Each language package may version independently from the desktop distribution, but must record compatible upstream ABI/source ranges and fail loudly on unsupported layouts/functions.

### Verification

Conformance, wrapper ABI tests and native journey graders are outside product implementation authority. They bind exact upstream + Khostty delta + platform/configuration. No historical artifact/test count transfers automatically across an upstream rebase.

## Repository / subsystem strategy candidates

The repository remains Khostty, a substantial Ghostty fork. The experiment order below chooses the implementation shape of individual capability families:

1. **Upstream-aligned core + explicit Khostty patch families:** keep terminal semantics close to current upstream and enumerate the Khostty-owned deltas that require source integration.
2. **Adapted external implementations inside/alongside the fork:** for Windows host, control and similar capabilities, port or compose proven prior implementations when that is lower-risk than reimplementing them.
3. **Custom Khostty implementation:** build where accepted Khostty journeys cannot be met cleanly by upstream APIs or adaptable prior art.

Do not decide subsystem ownership by LOC already written. Measure rebase conflict set, native/runtime evidence, build/test burden, unsupported upstream interfaces, security/lifecycle constraints and deployment complexity.

## Stable boundaries

- terminal semantics: upstream authority;
- Khostty platform/control behavior: Khostty accepted contract;
- worker/dev-agent state: outside terminal product state;
- native terminal instance/session state: product runtime state;
- verification receipts: independent evidence authority;
- release/support matrix: exact platform/configuration/version, never inherited from another fork's README.

## High-risk experiments before architecture acceptance

**A. Win32 import/rebase spike:** transplant/adapt a minimal viable subset of the pinned mature Win32 delta onto the chosen current upstream/Khostty experimental branch. Execute real Windows launch, child input/output, resize/render, clipboard, IME/basic split, shutdown/restart. Record conflict/patch footprint. Do not implement missing features from scratch during this spike.

**B. Control bake-off:** same nonce-bearing child journey on Ghoztty and candidate Khostty integration. Include targeting, child input, readback, wrong-instance/stale-target, controller replacement and authorization. Structured-state/events only count as differentiation if an accepted workflow actually needs them.

**C. Embedding bake-off:** direct C/libghostty consumer versus Khostty Rust (then Go/Python if justified): create/feed/resize/render/search/snapshot/callback/free; test ownership/thread failure cases and integration effort.

**D. Upstream-rebase rehearsal:** rebase candidate delta across at least one meaningful upstream interval; quantify conflicts and semantic regressions instead of assuming maintainability.

## Architecture acceptance criterion

Khostty remains the accepted product/fork. Architecture acceptance requires each material custom subsystem or patch family to justify its ownership against the strongest practical upstream/prior implementation using native journey evidence, lifecycle/security constraints, integration cost and upstream merge burden. A subsystem may be reduced, replaced, adapted or composed without reopening the product-existence decision.
