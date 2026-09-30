# Authoritative product intent — 2026-09-30

Authority: **CURRENT USER INTENT**, stated directly in the active recovery conversation. This supersedes prior recovery notes that left Khostty's core product identity unresolved. It does not make every current fork delta correct or required.

## Khostty

Khostty is a **deliberate Ghostty fork intended to become a deeply programmable, cross-platform terminal substrate for agentic work and Helios/HeliosLab**.

Its scope includes a spectrum of Ghostty changes rather than a single IPC patch:
- practical Windows support;
- deeper shell/platform behavior including Zsh and PowerShell needs;
- a substantially richer terminal/window/tab/pane control API;
- socket/API-based manipulation and observation of terminal topology/state;
- eliminating reliance on AppleScript or generic UI automation for operations that should be first-class terminal capabilities;
- enough stable programmable surface that Helios/HeliosLab and agents can script, control and build on the terminal in totality.

The intended control-plane outcome is closer to a deep programmable terminal/workspace API such as cmux-class functionality than a handful of convenience commands. The fork is allowed to make Ghostty-specific changes where that outcome requires them.

## Architectural consequences

1. **Fork existence is accepted product intent.** The alternatives gate now decides *how much must remain fork-owned and how to implement each subsystem*, not whether Khostty should shrink to zero merely because another terminal exposes IPC.
2. Upstream Ghostty semantics should still be preserved/reused wherever possible. A deliberate fork is not permission to rewrite commodity terminal core.
3. The agent control plane is a first-class product capability: topology creation/destruction, targeting, focus, child I/O, terminal observation/search, events, lifecycle/recovery, capability discovery and safe concurrency need explicit contracts.
4. UI automation/AppleScript can be compatibility escape hatches, not the canonical control path for supported operations.
5. Windows is a product capability, not incidental packaging. Native host/process/PTY/window lifecycle must actually close.
6. Shell integration must explicitly consider the supported shell/runtime matrix, including PowerShell and Zsh behavior where relevant, rather than treating terminal rendering alone as shell support.
7. Agent-facing APIs must preserve human usability and terminal semantics; automation cannot silently hijack unrelated panes or fabricate state.
8. Helios/HeliosLab is an intended consumer. Khostty should expose stable primitives and events rather than embed an entire agent scheduler/orchestration platform inside the terminal.
9. Existing alternatives (Ghostty upstream, cmux, Ghoztty, WezTerm, kitty, etc.) remain valuable bootstrap/prior-art references. Their existence falsifies uniqueness claims but does not falsify the accepted Khostty product.

## Differentiation question after this clarification

The correct question is no longer “why does a Ghostty fork exist if agent IPC is commodity?” It is:

> Which changes to Ghostty are required to provide the cross-platform, shell-aware, deeply programmable terminal substrate needed by Helios/agents, which can be borrowed/upstreamed/composed, and which fork-owned deltas survive measured alternatives?

The fork-delta ledger remains useful under this corrected gate.

## Stage implication

A protocol module or wrapper alone is not Khostty CVP. The earliest useful projection closes a real terminal journey through the fork: native terminal runtime + real child/shell + programmable pane/control API + observation + lifecycle truth on at least one explicitly supported configuration, using the same control/identity spine intended for Windows and later Helios integration.
