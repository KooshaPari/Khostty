# Agent Integration Guide

**Observed:** 2026-09-17 · How to drive, observe, and embed Khostty from an
automated agent. Read the "Available today" section first; most of what an agent
would want from *pane control* is still a design proposal, and building against
it will not work.

---

## 1. What an agent can do right now

| Capability | Status | How |
|---|---|---|
| Parse and observe terminal output | **Available** | `libghostty-vt` via C, Rust, or WASM |
| Read screen text, styles, cursor, title, pwd | **Available** | `ghostty_terminal_get`, formatter, or `Terminal.text()` |
| Search screen and scrollback | **Available** | `search.h` / `Terminal.search()` |
| Snapshot and restore terminal state | **Available** | `snapshot.h` / `Terminal.snapshot()` |
| Encode key / mouse / focus events | **Available** | `key/encoder.h`, `mouse/encoder.h`, `focus.h` |
| Run the parser in a browser or Node | **Available** | `@khostty/libghostty-vt-wasm` |
| Open a new window / tab in a running instance | **Available (narrow)** | `khostty +new-window`, `+new-tab`, `+toggle-quick-terminal` |
| Create, write to, focus, or query a **pane** | **NOT AVAILABLE** | Drafted only (G4) |
| Subscribe to terminal events over IPC | **NOT AVAILABLE** | Drafted only (G4) |
| Drive a Windows instance over IPC | **NOT AVAILABLE** | Named-pipe stub returns `error.Unimplemented` (G3) |

**The reliable agent path today is embedding, not IPC.** An agent that needs to
understand terminal output should run `libghostty-vt` in-process (Rust, Go,
Python, or JS) rather than trying to remote-control a GUI instance.

---

## 2. Recipe: observe a program's terminal output

This is the highest-value agent workflow that works today. Spawn a program under
a PTY, feed its bytes into a `Terminal`, and read structured state.

### Rust

```rust
use khostty_vt::Terminal;

let mut term = Terminal::new(120, 40)?;

// Feed whatever comes off the PTY. Malformed bytes are safe: the parser
// keeps state consistent and vt_write does not surface input errors.
term.vt_write(chunk);

// Structured observation for an agent decision:
let (x, y)              = term.cursor_position()?;   // 0-indexed
let title: Option<String> = term.title()?;          // Ok(None) = no title set yet
let pwd:   Option<String> = term.pwd()?;            // from OSC 7
let scrollback          = term.scrollback_rows()?;
let visible             = term.cursor_visible()?;
let at_prompt           = term.cursor_at_prompt()?;
let ground              = term.vt_ground()?;        // safe to inject sequences
let screen              = term.active_screen()?;    // Primary | Alternate
```

Requires a built `libghostty-vt` and `GHOSTTY_VT_LIB_DIR` or the default
`../zig-out/lib` layout. See [API.md](API.md#2-rust--khostty-vt).

> **Gap to know about:** the Rust crate has no safe wrapper for the **formatter**
> yet, so there is no `text()` / `html()` equivalent in Rust as of 2026-09-17. For
> screen text in Rust today, use the raw `ffi` bindings for
> `ghostty_formatter_*` (all `unsafe` is confined to `src/ffi.rs`), or use the
> WASM package, which does expose `text()` and `html()`.

### JavaScript / TypeScript

```js
import { Terminal } from "@khostty/libghostty-vt-wasm/api";

await using term = await Terminal.open({ cols: 120, rows: 40 });
term.write(chunk);

const snapshot = {
  cols: term.cols,
  cursor: [term.cursorX, term.cursorY],
  screen: term.screen,
  title: term.title,
  scrollbackRows: term.scrollbackRows,
  text: term.text(),
};

const search = term.search("error");
search.run();
const matches = search.totalMatches;
```

Good for agent UIs where the terminal must render in a browser and the agent runs
in the page. No native install. See [API.md](API.md#3-javascript--typescript--khosttylibghostty-vt-wasm).

### C

```c
#include <ghostty/vt.h>

GhosttyTerminal term = NULL;
if (ghostty_terminal_new(NULL, &term, 120, 40) != GHOSTTY_SUCCESS) { /* ... */ }

ghostty_terminal_vt_write(term, chunk, chunk_len);   /* never fails */

uint16_t cols = 0;
ghostty_terminal_get(term, GHOSTTY_TERMINAL_DATA_COLS, &cols);

GhosttyString title = {0};
if (ghostty_terminal_get(term, GHOSTTY_TERMINAL_DATA_TITLE, &title)
        == GHOSTTY_SUCCESS) {
  /* title.ptr / title.len — borrowed, valid until the next mutating call */
}

ghostty_terminal_free(term);
```

Borrowed pointers (`GhosttyString`, row/cell handles, search match buffers) stay
valid only until the next mutating call on the object that produced them. Copy
before you free or mutate. See [API.md](API.md#1-c-abi--libghostty-vt).

### Which artifact to link

Every language wrapper calls the same C entry points, so the conformance corpus
describes them all. Pick by runtime, not by capability:

| Runtime | Use |
|---|---|
| Rust service or agent | `khostty-vt` crate |
| Node or browser | `@khostty/libghostty-vt-wasm` |
| Go, Python, anything with cgo/ctypes | `libghostty-vt.a` / `.so` directly (`example/c-vt-*`) |

---

## 3. Recipe: drive a running instance (shipped, narrow)

Upstream IPC exposes exactly three actions. There is no pane access.

```bash
khostty +new-window          # target the detected instance
khostty +new-tab
khostty +toggle-quick-terminal
```

Targeting is by `class` (a named application instance) or `detect`. Config
overrides can be attached to `new_window` and `new_tab`:

```zig
// src/apprt/ipc.zig
NewWindow { arguments: ?[][:0]const u8 },   // per-surface config overrides
NewTab    { surface_id: u64, arguments: ?[][:0]const u8 },
```

This is a typed C ABI, not a text protocol. An agent that needs nothing more than
"open a window and run a command there" can use it and stop reading.

---

## 4. Drafted agent IPC protocol — NOT IMPLEMENTED

> **WARNING.** Everything in this section is a design proposal recorded in the
> Deep WBS (G4, section "IPC Protocol (Draft)"). `src/apprt/ipc/` does not exist
> as of 2026-09-17. The only related code is a Windows named-pipe stub whose
> every operation returns `error.Unimplemented`. **Do not build against this.**
> It is reproduced here so the design can be reviewed and so nobody invents a
> third competing shape.

### Message shapes

```json
// Agent → Khostty: create a pane
{"cmd":"pane.create","opts":{"split":"vertical","cwd":"/tmp"}}

// Khostty → Agent
{"ok":true,"data":{"pane_id":"p-3","pid":12345}}

// Agent → Khostty: write VT data into a pane
{"cmd":"pane.write","pane_id":"p-3","data":"ls -la\n"}

// Agent → Khostty: query pane state
{"cmd":"pane.state","pane_id":"p-3"}

// Khostty → Agent
{"ok":true,"data":{
  "cursor":{"row":12,"col":45},
  "title":"bash",
  "size":{"cols":120,"rows":40}
}}

// Agent → Khostty: list panes
{"cmd":"pane.list"}

// Khostty → Agent
{"ok":true,"data":[
  {"id":"p-3","title":"bash","pid":12345},
  {"id":"p-7","title":"vim","pid":12389}
]}

// Khostty → Agent: asynchronous event
{"event":"title_change","pane_id":"p-3","data":{"title":"~/projects/khostty"}}
```

Envelope conventions implied by the draft: responses carry `ok` plus `data`;
events carry `event` with no `ok`; commands carry `cmd`; pane-scoped messages
carry `pane_id`.

### Planned module layout

```
src/apprt/ipc/
  protocol.zig   — JSON message types, versioning
  server.zig     — Unix domain socket (+ Windows named pipe) accept loop
  handler.zig    — command dispatch onto the action system
  pane.zig       — create / close / focus / list / write / query / search
  state.zig      — machine-readable state snapshot (JSON)
  events.zig     — async event stream (title, exit, resize, bell)
  auth.zig       — token-based authentication
```

### Planned mappings onto the existing core

The draft is deliberately a thin layer: each command wraps an existing capability
rather than adding parser logic.

| Command | Wraps |
|---|---|
| `pane.create` | `Action.new_split` |
| pane focus / navigation | `Action.goto_split` |
| `pane.write` | `ghostty_terminal_vt_write` |
| `pane.state` | `ghostty_terminal_get` (+ formatter for text) |
| pane search | `ghostty_search_*` |
| `pane.list` | pane registry built over the surface tree |

### Authentication requirement

The WBS acceptance criteria require a token for all commands. The rationale is
direct: an unauthenticated socket that can write arbitrary VT into a live shell is
remote code execution by design. See [SECURITY.md](SECURITY.md#3-ipc-authorization-requirement-drafted).

### G4 acceptance criteria (the definition of done)

Reproduced from the WBS so this document does not overclaim:

- Agent can create, close, and focus panes via JSON commands
- Agent can write VT sequences to any pane
- Agent can read cursor position, title, size, and scrollback
- Agent can search scrollback text
- Concurrent pane operations do not deadlock
- Auth token required for all commands
- Protocol documented with examples

None of these are met today.

---

## 5. Transport notes for the Windows path

`src/apprt/windows/ipc.zig` sketches the Windows equivalent of a Unix domain
socket:

| Item | Value |
|---|---|
| Pipe name | `\\.\pipe\khostty-{server_pid}` |
| Mode flags | `PIPE_READMODE_MESSAGE \| PIPE_WAIT` |
| Frame header | `extern struct { action: u16, length: u32 }` |
| Payload | Packed immediately after the header |
| Status | SCAFFOLD — `init`, `connect`, `acceptConnection`, `send`, `receive` all return `error.Unimplemented` |

The frame header reuses the upstream action tag (`apprt/ipc.zig`) rather than
introducing a second numbering. If G4 lands, the JSON protocol and this frame
layout need reconciling — the stub predates the draft.

---

## 6. Risks an agent integrator should know

| Risk | Why it matters | Current mitigation |
|---|---|---|
| Draft mistaken for shipped | An agent built on `pane.create` fails at runtime with nothing to call | Marked DRAFT here and in [API.md](API.md) |
| C API is unstable | Upstream says breaking changes are expected | Pin a revision; regenerate wrappers |
| ABI layout drift | Hardcoded offsets corrupt memory silently | Read `ghostty_type_json()`; Rust and WASM both assert against it |
| Borrowed buffers | Use-after-free looks like plausible data, not a crash | Copy-before-free helper; Rust RAII wrappers |
| WASM memory growth | Stale `ArrayBuffer` views read/write garbage | Views reacquired on buffer identity/length change |
| Unauthenticated IPC | Writing VT into a live shell is arbitrary code execution | Token auth is a G4 acceptance criterion, not yet built |
| Kitty graphics absent in WASM | Agents driving image protocols in a browser get nothing | Sequences parsed and safely ignored; use native for images |

---

## See also

- [API.md](API.md) — full reference for all surfaces
- [SECURITY.md](SECURITY.md) — threat model, including the IPC auth requirement
- [PLATFORMS.md](PLATFORMS.md) — per-platform availability
- [TESTING.md](TESTING.md) — how to verify an integration
- [GLOSSARY.md](GLOSSARY.md) — pane, surface, snapshot, gate
- Deep WBS §G4: [`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](sessions/20260916-fork-assessment/02_DEEP_WBS.md)
