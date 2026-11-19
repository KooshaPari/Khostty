# Windows Strategy — decision record

**Decided:** 2026-11-19 · **Decider:** operator hand-off, lane `khostty retirement`
**Question:** given Noctty (native Win32 app around the Ghostty core) and
winterm-ghostty (patch series that swaps Windows Terminal's Cascadia engine for
libghostty per profile), what is the "superset optimal" for Khostty?

**Answer:** neither is adopted as an architecture. Khostty's own native apprt *is*
Noctty's architecture, so the superset is G3 completion, not a second product.
Khostty takes four capability requirements from Noctty, discards winterm-ghostty
outright, and keeps stock Windows Terminal as an unchanged OS-integration
fallback that costs this fork nothing.

---

## 1. What Khostty already is (repo-grounded)

| Claim | Evidence |
|---|---|
| Native runtime around the Ghostty core, per platform, forked apprt | `src/apprt/runtime.zig`; `src/apprt.zig` maps `.windows => windows` |
| A real Windows apprt scaffold, not a stub directory | `src/apprt/windows/` — **9 files, 1936 lines**: `App.zig`, `Window.zig`, `surface.zig`, `interface.zig`, `input.zig`, `mouse.zig`, `keyboard.zig`, `ipc.zig`, `mod.zig` |
| Doc-vs-tree drift found while writing this record | `docs/PLATFORMS.md` §5 lists `renderer.zig` and `win32api.zig`; **neither exists** (`ls` → No such file or directory), and no file in `src/apprt/windows/` references them. The §5 table is stale |
| Windows binary + DLL + installer actually built, run, installed | `docs/PLATFORMS.md` §5: exe 43.5 MB + `ghostty-vt.dll` 7.5 MB (2026-09-18), native `+version` and DLL ABI on Windows NT 10.0.28120 (2026-09-19), Inno Setup install/uninstall verified |
| **No GUI window** | `App.zig` `init`/`registerWindowClass`/`run` return `error.Unimplemented`; `surface.zig` makes **no native calls** (states it in its own doc comment) |
| Ghostty config parity by construction | it is a Ghostty fork; no translation layer exists to drift |
| OSC 7501 program status already at the VT layer | `include/ghostty/vt/terminal.h:103,1243` — `GHOSTTY_TERMINAL_OPT_PROGRAM_STATUS`, `state=blocked:kind=permission:...` |
| Kitty graphics work exists for Windows | `src/terminal/kitty/windows.zig` (presence only; **runtime UNVERIFIED**) |
| Agent IPC is fork-specific and already exercised | `src/main_agent_ipc.zig`; named-pipe transport in `src/apprt/windows/ipc.zig`; 3 actions verified on macOS per `PLATFORMS.md` |
| **No GPU fallback renderer** | `src/renderer/backend.zig` offers only `.opengl` / `.metal`; case-insensitive search of `src` for d3d11, direct3d, directx or warp returns **0 hits** |
| Base is a dev snapshot, ahead of the newest release tag | `build.zig.zon:3` `.version = "1.3.2-dev"`; upstream tags are **v1.3.0 and v1.3.1 only** (no v1.3.2 tag exists); base commit `d4c88d8` (2026-09-15) |

## 2. Decisions

### 2.1 winterm-ghostty — **DISCARD**

Not a missing capability; an incompatible one, and adopting it would *lose* work
this fork has already paid for.

1. **Mutually exclusive with G3.** Our value is a first-class Windows runtime in
   the fork (`Runtime.default` returns `.none` for Windows upstream). winterm's
   value is Ghostty's engine inside someone else's XAML shell. Both cannot be the
   product.
2. **It deletes verified work.** Cross-compile, native execution, DLL ABI and the
   Inno Setup install/uninstall are all done (2026-09-18/19). A patch series
   against `microsoft/terminal` abandons all of it.
3. **It inverts the one thing the fork sells.** Its configuration is Windows
   Terminal JSON with `"engine": "ghostty"` per profile, i.e. no `config.ghostty`
   parity — the property Khostty gets for free by being a Ghostty fork.
4. **It adds a two-upstream rebase surface.** A patch series must be maintained
   against `microsoft/terminal` *and* Ghostty, while `docs/FORK-DISCIPLINE.md`
   exists precisely to keep our absorbed-upstream surface small.
5. **Its own claims are unverified here** (70+ patches, ~70 GB build artifacts,
   phase 6 of 9, no license file). Third-party, so **UNKNOWN** — and irrelevant
   either way: the decision does not depend on them.

### 2.2 Noctty — **ADOPT as a capability reference, SUPERSEDE as a product**

It shares our architecture, which makes it a useful checklist and a bad
dependency. No code or binary of it is vendored: its licence is **UNKNOWN** to
this repo, and vendoring would put a third-party terminal inside a fork whose
whole point is that it *is* the terminal.

Four requirements taken from it, each grounded in a gap measured above:

| Adopted requirement | Gap it closes here |
|---|---|
| A **D3D11/WARP-class fallback renderer** for GPU-less/RDP/VM sessions | `src/renderer/backend.zig` has only OpenGL/Metal; 0 hits for any D3D/WARP path. The desk runs WSL and RDP-adjacent sessions, so this is a real fleet requirement, not a nicety |
| **Shell auto-detection** (WSL, PowerShell, Git Bash) | Not implemented; `surface.zig` states input/close remain caller-owned |
| **Session restore** | Not implemented; `Window.zig` is a 24-line HWND wrapper |
| **Surfacing OSC 7501 in the UI** | VT/C-API side exists (`terminal.h`); the Windows apprt never reads it |

Superseded (we are already broader, so nothing to adopt): its agent-status
notifications are a subset of our agent IPC protocol; its feature set has no
answer to `docs/ROADMAP.md` M1–M5 (agent-state UI, panes, layouts, profiles);
and its packaging story is one winget/Scoop/Chocolatey channel against an
installer this fork already verifies.

### 2.3 The superset — **Khostty (G3) primary + stock Windows Terminal as OS utility**

This is the only reading of "superset optimal" that does not fork the product in
two. G3 already names the exit criteria, and two of six are met:

- Met: cross-compile succeeds; binary runs natively (CLI + DLL ABI).
- Open: keyboard and mouse encode via `ghostty_key_encoder_*` /
  `ghostty_mouse_encoder_*`; DirectWrite render with font fallback; clipboard
  bracketed paste; named-pipe command acceptance.

Stock `wt.exe` stays as the OS-integration fallback (Quake drop-down, elevated
prompts, Explorer "Open in Terminal"). It requires no fork, no patch, and no
configuration parity — recommend and reuse, never rebuild.

### 2.4 Upstream sync — **stay on 1.3.2-dev, re-base when a `v1.3.2` tag exists**

The base is `1.3.2-dev @ d4c88d8` (2026-09-15). Upstream has tagged only v1.3.0
and v1.3.1, so the fork is **ahead of the newest release** and on a dev
snapshot. No evidence in this repo says any v1.3.1 release delta matters to us,
so re-basing to v1.3.1 now would be churn without a reason. Trigger instead:

> Re-base when `ghostty-org/ghostty` publishes a `v1.3.2` (or later) tag **and**
> the fork has a Windows GUI window, so the re-base is validated against a
> working apprt rather than a scaffold.

Any external claim of being "synced with Ghostty 1.3.2" describes a dev
snapshot, because no such release exists. Treat such claims as **UNKNOWN**.

## 3. What is UNKNOWN (do not inherit from the scraped thread)

- Noctty's version string, installer channels, renderer behaviour, shell
  detection and session restore: all third-party claims, unverified here.
- winterm-ghostty's patch count, disk cost, completion phase and absence of a
  licence: same.
- Whether either project tracks a released tag or a dev commit.
- Whether Khostty's existing `src/terminal/kitty/windows.zig` produces working
  Kitty graphics on Windows at runtime.

## 4. Consequences

1. `docs/ROADMAP.md` non-goal stands: no Windows GUI expansion until G3's
   windowing scaffold leaves `error.Unimplemented` — and this record makes that the *only*
   path, not a deferred one.
2. G3's open criteria are the work queue, in this order: window + message pump,
   DirectWrite render with font fallback, input encoders, bracketed-paste
   clipboard, named-pipe command acceptance. The renderer fallback requirement
   (§2.2) enters G3 as a new criterion, since OpenGL-only cannot serve the fleet.
3. Two known defects stay on the record and are not fixed by this decision: the
   pipe name constant has a single leading backslash (not the Win32 pipe
   namespace) and the pipe has no ACL design (`PLATFORMS.md` §5). The §5 file
   table also needs correcting to the 9 files that exist, per §1.
