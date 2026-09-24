# Khostty GUI + Multiplexer Roadmap (post-0.1.0)

**Status:** proposed, not scheduled. Recorded from operator direction on 2026-09-20,
research refreshed 2026-09-24. This is the r6 work item: GUI refinement and
mouse/GUI expansion, incorporating cmux / zellij / honeymux / herdr-style features
where they fit Khostty's architecture.

## Why

Operator assessment of the status quo:

- Khostty already has split panes, which **replaces the personal need for a
  separate mux** — but the GUI feels "good but bare."
- tmux is **too mouse-unfriendly** and not keyboard-intuitive for this operator's
  workflow. Whatever Khostty grows must be drivable both ways: mouse *and*
  discoverable keyboard paths.
- herdr's use cases (persistent agent panes with visible state) are "great"; the
  goal is to adopt the patterns, not to wrap an external multiplexer.
- Ghostty upstream is a strong base terminal but leaves agent-orchestration
  UX to third parties.

## Competitive feature survey (2026-09-24)

| Tool | What it does well | Sources |
|---|---|---|
| **herdr** (herdr.dev) | Agent-aware multiplexer: real terminal panes per agent, sidebar that reports **blocked / working / done / idle** per pane without configuration; workspaces, tabs, panes; **mouse splitting**; detach/reattach; survives lid-close; SSH attach | herdr.dev, terminaltrove.com/herdr, github.com/SuperCodeAgents/herdr-terminal |
| **Honeymux** (hmx.dev) | TUI wrapper over tmux: **hook-based agent monitoring**, Agents dialog tree (grouped by locality/team, color-coded provider), pane tabs, per-pane OS-native scrollback/search, layout profiles, Kitty keyboard protocol, remote-backed pane stitching, mobile UI | docs.hmx.dev, github.com/honeymux/honeymux |
| **cmux** (cmux.com) | Native macOS terminal **built on Ghostty** (libghostty in Swift/AppKit): vertical tab sidebar with git branch / PR status / workdir, **notification rings** when agents need attention, split panes, programmable CLI | github.com/manaflow-ai/cmux, cmux.com |
| **zellij** | Keyboard-first workspace UX: floating panes, layouts, plugins, collaboration. Mouse handling exists (`mouse_mode`, event routing) but pane-level mouse UX is partial — long-standing fragmented request (#175) and middle-click interception bug (#5074) | zellij.dev, github.com/zellij-org/zellij issues 175/5074 |
| **tmux** (baseline) | Battle-tested persistence; rejected as the daily driver here: mouse-unfriendly, keybinding opacity | operator direction |
| **upstream Ghostty** | multi-window, tabs, splits, scrollback search, native scrollbars (1.3), mouse reporting to applications | ghostty.org/docs/features |

Khostty's structural advantage: it already ships an **agent IPC surface** (JSON
commands/events over a Unix socket: `new_window`, `new_tab`,
`toggle_quick_terminal`, pane/state queries — WBS G4, 458/458 tests). Everything
below builds on that surface instead of scraping other processes.

## Proposed milestones (outcome-based, no durations)

### M1 — Mouse parity for the existing GUI

- Click-to-focus and click-to-select for splits and tabs.
- Drag the split divider to resize (ghostty upstream has SplitTree on GTK;
  macOS AppKit path needs the equivalent interaction).
- Right-click context menu: new tab / new split / close.
- Scrollbar + wheel scroll that behaves without modifier gymnastics.
- *Acceptance:* every GUI operation reachable by mouse alone, and every mouse
  action has a documented keyboard equivalent (the tmux grievance is the spec).

### M2 — Agent state visibility (herdr pattern, IPC-native)

- Per-pane state badges (blocked / working / done / idle) sourced from the
  existing IPC event stream, not from terminal-output heuristics.
- Sidebar or tab decoration showing state at a glance; notification ring
  (cmux pattern) when an agent finishes or blocks.
- *Acceptance:* launch two IPC-driven sessions, induce a block and a completion,
  observe both states update in the GUI without polling the terminal content.

### M3 — Pane tabs + per-pane scrollback/search (honeymux pattern)

- Pane tabs in the sidebar rather than only inline splits.
- Per-pane scrollback history and search independent of the active pane.
- *Acceptance:* search across a background pane's scrollback while a foreground
  process keeps running.

### M4 — Layouts, profiles, keyboard protocol

- Saved layout profiles (restore a workspace arrangement by name via IPC).
- Kitty keyboard protocol pass-through where the app supports it (honeymux
  advertises this; upstream Ghostty has partial support — verify before building).
- *Acceptance:* save a 3-pane layout, tear it down, restore by name, byte-identical
  arrangement.

### M5 — Mouse UX audit against zellij's pitfalls

- Forward middle-click paste instead of intercepting it (zellij #5074 is the
  negative control).
- Explicit test: mouse events reach TUI apps in `mouse_mode` and do not steal
  pane-management gestures. Decide and document the gesture split (e.g. modifiers
  for pane management vs. raw forwarding).

## Non-goals

- Not wrapping tmux/zellij/honeymux/herdr as a subprocess — adopt patterns only;
  Khostty's split panes + IPC are the substrate.
- Not forking cmux's Swift shell — Khostty's AppKit runtime is its own; cmux is a
  feature reference (and itself proof the Ghostty-embedding path works).
- No Windows GUI expansion until G3's windowing scaffold leaves
  `error.Unimplemented` (see [PLATFORMS.md](PLATFORMS.md) §5).
- No schedule estimates — outcomes only, per program rules.

## Open questions

1. State signal source: does the IPC event stream already carry enough to derive
   blocked/working/done, or does the protocol need a `status` event? (G4 protocol
   doc is the place to check first.)
2. Upstream mergeability: which of M1's interactions can be contributed upstream
   vs. kept fork-side? Split interaction code is a likely upstream candidate;
   agent-state UI is fork-side.
3. Prioritization vs. Windows GUI (G3 windowing) — operator call on which gap
   closes first.

## References

- herdr: https://herdr.dev/ · https://terminaltrove.com/herdr/ ·
  https://github.com/SuperCodeAgents/herdr-terminal
- Honeymux: https://hmx.dev/ · https://docs.hmx.dev/ ·
  https://github.com/honeymux/honeymux
- cmux: https://cmux.com/ · https://github.com/manaflow-ai/cmux
- zellij: https://zellij.dev/ · issues #175, #5074
- Ghostty features: https://ghostty.org/docs/features
- Local context: `Phenotype/repos/muxlog.md` (Sunshine/Moonlight, per-window app
  tabs, RDP/VNC lanes)
