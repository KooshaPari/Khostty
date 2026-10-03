# Authoritative product intent clarification — 2026-09-30

Authority: **USER INTENT — current explicit clarification in the active recovery session.** This supersedes recovery interpretations that reduced Khostty to a possibly unnecessary thin Ghostty adapter. It does not make every existing fork delta correct.

## Khostty

Khostty is intentionally a **Ghostty fork with a broad set of product changes**, spanning from platform/runtime support through deeper shell behavior to a substantially more programmable terminal control plane.

Intended change families explicitly include:
- Windows support;
- deeper Zsh and PowerShell support/behavior;
- a much deeper and more advanced API;
- socket/API-based manipulation and management of panes and terminal state;
- reducing or eliminating dependence on AppleScript and other UI automation for agent/operator control.

The programmable-control target is conceptually closer to **cmux-class terminal/workspace control**: users and software should be able to manipulate panes and relevant terminal/workspace state through stable APIs/sockets rather than pretending to be a human operating GUI controls.

Khostty is intended as infrastructure/precursor for **HeliosLab**: a terminal/runtime surface that can be interfaced with, scripted and developed against so agents can be used comprehensively rather than being constrained to fragile UI automation.

## Consequences for mature-first recovery

1. **A substantial fork is an accepted architectural premise**, subject to optimization and evidence. The existence gate must not repeatedly reduce the question to “could upstream Ghostty + a tiny adapter replace Khostty?”.
2. Upstream/thin-adapter/Ghoztty/WezTerm/cmux comparisons remain valuable **bootstrap and design alternatives for subsystems**. They identify what to integrate/learn from and where Khostty should avoid unnecessary divergence; they do not by themselves falsify Khostty's product identity.
3. Windows and shell/platform behavior are first-class product capabilities, not incidental fork debt.
4. The deep programmable API/control plane is first-class product scope. Current source evidence that the new JSON server is unmounted is therefore a **core implementation gap**, not evidence that the subsystem should necessarily be removed.
5. The mature ontology must include terminal/session/process semantics; windows/tabs/panes/workspaces and stable identities; shell/platform integration; API/socket control and events; authorization/policy; human terminal experience; agent/HeliosLab integration; embedding/bindings where retained; lifecycle/recovery; packaging/support.
6. The API should aim to eliminate UI automation for supported operations. UI automation may remain an explicit fallback for unsupported external surfaces, but it is not the desired Khostty control mechanism.
7. Fork ownership analysis still matters: inherited Ghostty code should not be claimed as Khostty differentiation, and unnecessary divergence should be minimized/upstreamed where appropriate. The optimization target is a maintainable purposeful fork, not the smallest possible patch count.

## Still not decided by this clarification

Exact cmux feature parity; exact API protocol/version; precise workspace model; Windows implementation architecture; exact Zsh/PowerShell feature obligations; whether wrappers/WASM remain product-facing; upstreaming strategy; security model; HeliosLab binding details. These require archaeology/SOTA/design and experiments.
