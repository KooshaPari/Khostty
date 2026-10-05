# Khostty mature contract ontology and journeys — authority-anchored 2026-09-30

Authority: current explicit user clarification in `AUTHORITATIVE-INTENT-20260930.md`. This supersedes recovery framing that treated a thin upstream adapter as the default architecture. Khostty is intentionally a purposeful Ghostty fork; individual implementation choices remain subject to research and verification.

## Product identity

Khostty is a **Ghostty-derived programmable terminal/runtime** intended to make substantial platform, shell and control-plane improvements and serve as terminal infrastructure/precursor for HeliosLab and agent operation.

The product should preserve the terminal quality/semantics inherited from Ghostty while adding capabilities including:
- Windows support;
- deeper Zsh/PowerShell/platform integration;
- stable programmable control of windows/workspaces/tabs/panes/terminals/processes through APIs/sockets;
- events/introspection needed by users, scripts and agents;
- removal of AppleScript/UI-automation dependence for supported terminal operations.

The target control experience is conceptually in the class of cmux/other programmable multiplexed terminals, not necessarily API-compatible with them.

## Core ontology

```
Khostty Runtime
  ├─ terminal emulation/render/process semantics (largely inherited Ghostty)
  ├─ platform host
  │    ├─ macOS
  │    ├─ Linux
  │    └─ Windows
  ├─ shell integration
  │    ├─ Zsh
  │    ├─ PowerShell
  │    └─ other accepted shells
  ├─ control graph
  │    ├─ Instance / epoch
  │    ├─ Workspace
  │    ├─ Window
  │    ├─ Tab
  │    ├─ Pane
  │    └─ Terminal / child process
  ├─ programmable interface
  │    ├─ socket/session/principal
  │    ├─ capability discovery
  │    ├─ commands
  │    ├─ queries/introspection
  │    ├─ event subscriptions
  │    └─ explicit errors/loss/recovery
  ├─ human UI
  ├─ HeliosLab / agent consumers
  └─ optional retained embedding/wrapper projections
```

A pane ID without instance/epoch/lifecycle semantics is insufficient for robust automation. Display-feed bytes and child-process input remain distinct operations.

## Product projections

| Projection | Principal obligation |
|---|---|
| Ghostty fidelity | Preserve accepted upstream terminal/render/input/config behavior unless a Khostty decision explicitly changes it |
| Windows/platform | Native usable host with process/PTY/render/input/window lifecycle, not just a DLL/CLI scaffold |
| Shell behavior | First-class supported Zsh/PowerShell integration and observable shell/process semantics |
| Workspace/pane model | Stable inspectable topology and lifecycle identities suitable for human and machine control |
| Socket/API | Create/query/focus/split/close/input/read/control resources without UI automation |
| Events | Subscribe to truthful lifecycle/output/focus/title/process/agent-relevant changes with loss/resync semantics |
| Policy/security | Local/remote principal and capability boundaries appropriate to the control surface |
| Agent/HeliosLab | Allow agents to operate terminal workspaces robustly and scriptably as infrastructure |
| Human terminal | Remain a strong interactive terminal rather than becoming an agent-only daemon |
| Packaging/operations | Install/update/diagnose supported platforms and preserve evidence of qualified builds |

## Normative mature journeys

**K-J-HUMAN:** install Khostty on a supported platform, launch shell/processes, use tabs/panes/windows, preserve expected Ghostty-quality terminal behavior and supported shell integration.

**K-J-WINDOWS:** install on Windows, launch a real native window/PTY/process, use PowerShell and other accepted shells, split/manage panes and close/recover cleanly. A DLL or `+version` run is not this journey.

**K-J-CONTROL:** authenticated/authorized client discovers topology/capabilities, creates a workspace/window/tab/pane, launches a known child with cwd/environment, sends child input, reads terminal state, focuses/resizes/moves/closes resources and receives causally bound results without AppleScript/UI automation.

**K-J-EVENTS:** subscribe to resource/process/output/focus/title changes, detect event loss, resynchronize, reconnect after controller replacement and reject stale/wrong-instance targets.

**K-J-HELIOS:** HeliosLab/agent consumer creates and supervises multiple terminal workspaces/panes, maps them to agent/work identities, observes when attention/action is needed, reads/writes appropriate terminal/process state and survives controller replacement without losing terminal truth.

**K-J-SHELL:** supported Zsh/PowerShell session exposes accepted prompt/cwd/process/command-boundary semantics needed by human and programmable workflows.

**K-J-EMBED:** retained wrapper/embedding consumer uses the inherited terminal core safely where that projection remains useful. Wrapper ergonomics do not define the whole product.

## Alternatives / bootstrap gate under corrected intent

Comparisons to cmux, WezTerm, Ghoztty and upstream Ghostty remain mandatory, but the question is now:

> Which proven resource models, protocol semantics, event/lifecycle patterns and implementations should Khostty integrate/adapt/learn from so its purposeful fork is better and maintainable?

—not “does the existence of another programmable terminal mean Khostty should stop being one?”

Current cmux documentation is particularly relevant because it exposes a public resource grammar around workspace/screen/pane/terminal, idempotency and socket control. WezTerm demonstrates mature pane IDs, workspace/domain topology, child input and screen introspection. These are design priors and comparison baselines.

## Stage projections

**CVP:** usable Ghostty-derived terminal on the first supported platform plus a truthful narrow programmable spine: enumerate topology, create/split one pane, launch/send child input/read output, close, and survive controller replacement. It must use the mature resource/lifecycle identity model.

**MVP:** adds the required Windows and shell integration slice plus broader pane/window/workspace operations/events sufficient for a real HeliosLab agent workflow.

**Beta:** widens platform/shell/API/event/security/recovery coverage and qualified HeliosLab integrations.

**GA:** supported cross-platform human terminal + stable documented programmable API for accepted configurations, with release/install/upgrade/security/accessibility evidence.

**Mature:** deep programmable terminal/workspace infrastructure with the accepted Windows/shell/control/HeliosLab contract and minimized unnecessary upstream divergence.

## Current implementation consequences

The new JSON agent-control subsystem being unmounted is a **core missing realization**, not evidence it should be deleted. K-E02 should bootstrap from proven cmux/WezTerm/Ghoztty patterns where useful, but its goal is to mount and mature Khostty's intended control plane.

Fork ownership still matters: inherited Ghostty code is not Khostty differentiation, and upstreamable/common improvements should avoid unnecessary divergence. Maintainability is an optimization constraint on the purposeful fork.


## Authoritative horizon correction — 2026-09-30

Current user intent resolves the product as a deliberate Ghostty fork and programmable terminal substrate for Helios/HeliosLab. The mature contract must therefore include, as accepted capability families rather than speculative breadth:

- cross-platform native runtime with Windows as a real supported target;
- shell-aware behavior with explicit supported-shell matrix, including Zsh and PowerShell needs;
- deep programmable topology/state control over windows/workspaces/tabs/panes/surfaces as the chosen Khostty ontology evolves;
- first-class child input, terminal observation/search, focus/targeting, lifecycle and event subscriptions;
- socket/API capability discovery and access policy;
- stable enough interfaces for Helios/agents to build on without AppleScript/UI automation.

Upstream Ghostty currently documents automatic shell integration for bash/elvish/fish/nushell/zsh, but not PowerShell. PowerShell therefore enters the gap ledger as a concrete accepted research/build family, while Zsh work should begin by identifying Khostty-specific unmet behavior beyond upstream rather than duplicating it.

cmux provides a useful API baseline for explicit workspace/surface identity, JSON socket request IDs, capabilities, targeted send/focus and access modes. Khostty need not clone cmux's ontology, but equivalent product obligations cannot be dismissed as optional if Helios requires them.

The terminal remains a substrate, not Helios itself: durable agent task scheduling and product-development truth remain outside Khostty.
