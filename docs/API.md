# API Reference

**Observed:** 2026-09-17 · Khostty has three public surfaces and one planned one.
Each has a different stability story; read the status line before building on it.

| Surface | Entry point | Stability | Status |
|---|---|---|---|
| C ABI | `include/ghostty/vt.h` | Explicitly unstable upstream ("work-in-progress") | DONE (G1/G2) |
| Rust | `khostty-vt/` crate | Pre-1.0; wrappers added incrementally | IN PROGRESS (G5) |
| JS/TS (WASM) | `wasm/js/` package | Pre-1.0 (`version: 0.0.0`) | IN PROGRESS (G7) |
| IPC | `src/apprt/ipc.zig` (3 actions) | Stable but narrow | DONE, narrow |
| IPC (agent protocol) | `src/apprt/ipc/` *(planned)* | **Draft — not implemented** | NOT STARTED (G4) |
| CLI | `khostty +<command>` | Follows upstream | DONE |

Two surfaces are **not** available and must not be coded against:

- The JSON agent IPC protocol in [AGENT.md](AGENT.md) is a **draft** from the
  Deep WBS. `src/apprt/ipc/` does not exist. The Windows transport stub returns
  `error.Unimplemented`.
- Per-pane operations (create/close/focus/write/query/search) are **not exposed**
  by any shipped API. Upstream splits are reachable only through the in-app
  action system.

---

## 1. C ABI — `libghostty-vt`

### Header

```c
#include <ghostty/vt.h>
```

The umbrella header includes 30 module headers. `GHOSTTY_API` expands to
`__declspec(dllexport/dllimport)` on Windows and
`__attribute__((visibility("default")))` elsewhere.

**203 `GHOSTTY_API` functions** are declared. The header's own warning, quoted
because it is the contract:

> This is an incomplete, work-in-progress API. It is not yet stable and is
> definitely going to change.

Pin a revision. Do not assume ABI compatibility across versions.

### Linking

| Artifact | Flag | File |
|---|---|---|
| Shared | default for lib targets | `libghostty-vt.0.1.0.dylib` / `.so` |
| Static | `-Demit-lib-vt` | `libghostty-vt.a` |
| Apple multi-platform | `-Demit-xcframework` | `.xcframework` |
| WebAssembly | `-Dtarget=wasm32-freestanding` | `ghostty-vt.wasm` |

See [BUILD.md](BUILD.md).

### Result codes

```c
typedef enum {
  GHOSTTY_SUCCESS       =  0,
  GHOSTTY_OUT_OF_MEMORY = -1,
  GHOSTTY_INVALID_VALUE = -2,
  GHOSTTY_OUT_OF_SPACE  = -3,   /* buffer too small; required capacity returned */
  GHOSTTY_NO_VALUE      = -4,   /* valid query, no value yet */
} GhosttyResult;
```

`GHOSTTY_OUT_OF_SPACE` is a *two-pass* signal, not a failure: the call reports the
required capacity so the caller can allocate and retry. The Rust `sys` module
wraps that pattern.

### Terminal lifecycle

```c
GhosttyResult ghostty_terminal_new(const GhosttyAllocator* allocator,
                                   GhosttyTerminal* terminal,
                                   uint16_t cols,
                                   uint16_t rows);

void ghostty_terminal_free(GhosttyTerminal terminal);
void ghostty_terminal_reset(GhosttyTerminal terminal);

GhosttyResult ghostty_terminal_resize(GhosttyTerminal terminal,
                                      uint16_t cols, uint16_t rows,
                                      uint32_t cell_width_px,
                                      uint32_t cell_height_px);

void ghostty_terminal_vt_write(GhosttyTerminal terminal,
                               const uint8_t* data, size_t len);

GhosttyResult ghostty_terminal_vt_write_until_ground(GhosttyTerminal terminal,
                                                     const uint8_t* data,
                                                     size_t len,
                                                     size_t* out_consumed);

GhosttyResult ghostty_terminal_set(GhosttyTerminal terminal,
                                   GhosttyTerminalOption option,
                                   const void* value);

GhosttyResult ghostty_terminal_get(GhosttyTerminal terminal,
                                   GhosttyTerminalData key,
                                   void* out);
```

Behaviour that matters when embedding:

- **`ghostty_terminal_vt_write` never fails.** Input is treated as untrusted;
  malformed sequences are logged internally and state is kept consistent. You do
  not need to validate bytes before feeding them.
- **`reset` == RIS.** Modes, scrollback, scrolling region, and screen contents are
  cleared. Dimensions survive.
- **`resize` reflows** the primary screen when wraparound mode is on; the
  alternate screen does not reflow. It also updates pixel dimensions (image
  protocols, size reports), clears synchronized-output mode, and emits an in-band
  size report if mode 2048 is enabled.
- **`vt_write_until_ground`** consumes exactly the prefix needed to reach a
  stateless point in the stream. That is the safe seam for injecting your own
  out-of-band sequences into a PTY stream. Returns `GHOSTTY_NO_VALUE` when the
  whole slice was consumed without reaching ground.

### Callbacks and options

`ghostty_terminal_set` takes a `GhosttyTerminalOption` (40 defined, values 0–39),
including:

| Option | Purpose |
|---|---|
| `GHOSTTY_TERMINAL_OPT_USERDATA` | Opaque pointer handed back to callbacks |
| `GHOSTTY_TERMINAL_OPT_WRITE_PTY` | Receives query responses (DSR, DA, …) that the terminal would normally write back to the PTY |
| `GHOSTTY_TERMINAL_OPT_BELL` | Bell notification |
| `GHOSTTY_TERMINAL_OPT_TITLE_CHANGED`, `…_PWD_CHANGED` | State-change notifications |
| `GHOSTTY_TERMINAL_OPT_TITLE`, `…_PWD` | Programmatic title / working directory |
| `GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND`, `…_BACKGROUND`, `…_CURSOR`, `…_COLOR_PALETTE` | Theme injection |
| `GHOSTTY_TERMINAL_OPT_SELECTION` | Selection state |
| `GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_BYTES`, `…_MAX_LINES` | Scrollback bounds |
| `GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_*` | Image storage limits and media policy |
| `GHOSTTY_TERMINAL_OPT_MODE_DEFAULT`, `…_MODE` | DEC private mode defaults |
| `GHOSTTY_TERMINAL_OPT_TERMINFO_NAME` | Reported terminfo name |
| `GHOSTTY_TERMINAL_OPT_CLIPBOARD_READ`, `…_CLIPBOARD_WRITE` | Clipboard bridge |
| `GHOSTTY_TERMINAL_OPT_DESKTOP_NOTIFICATION`, `…_PROGRESS_REPORT` | Host notifications |

Two documented constraints:

1. **Callbacks run synchronously during VT writes.** They must not call
   `ghostty_terminal_vt_write` or `ghostty_terminal_vt_write_until_ground` on the
   same terminal. No reentrancy.
2. **Non-pointer option values are passed by pointer.** Pass `GhosttyString*`,
   not `GhosttyString`. Pointer types (callbacks, userdata) are passed directly.

### Queries

`ghostty_terminal_get(terminal, key, out)` writes a caller-allocated out
parameter whose type depends on the key. 41 keys are defined (values 0–40,
including the `INVALID` sentinel). Examples:

```c
uint16_t cols = 0;
ghostty_terminal_get(term, GHOSTTY_TERMINAL_DATA_COLS, &cols);

uint32_t cursor_x = 0, cursor_y = 0;
ghostty_terminal_get(term, GHOSTTY_TERMINAL_DATA_CURSOR_X, &cursor_x);
ghostty_terminal_get(term, GHOSTTY_TERMINAL_DATA_CURSOR_Y, &cursor_y);
```

| Key group | Keys |
|---|---|
| Geometry | `COLS`, `ROWS`, `WIDTH_PX`, `HEIGHT_PX`, `TOTAL_ROWS`, `SCROLLBACK_ROWS` |
| Cursor | `CURSOR_X`, `CURSOR_Y`, `CURSOR_STYLE`, `CURSOR_VISIBLE`, `CURSOR_PENDING_WRAP` |
| Screen | `ACTIVE_SCREEN`, `SCROLLBAR`, `MOUSE_TRACKING`, `KITTY_KEYBOARD_FLAGS` |
| Identity | `TITLE`, `PWD` |
| Theme | `COLOR_FOREGROUND`, `COLOR_BACKGROUND`, `COLOR_CURSOR`, `COLOR_PALETTE`, plus `*_DEFAULT` variants |
| Kitty images | `KITTY_IMAGE_STORAGE_LIMIT`, `…_MEDIUM_FILE`, `…_MEDIUM_TEMP_FILE`, `…_MEDIUM_SHARED_MEM` |

`ghostty_terminal_get_multi` fetches several keys in one call. Because the
out-parameter type depends on the key, a language binding cannot guess it: the C
header documents each `Output type:` line, the WASM generator extracts that
mapping into `wasm/js/terminal-data.js`, and the Rust crate encodes it in
`src/terminal/types.rs`. Per-target widths come from the type manifest (§1.7).

### Grid references

```c
ghostty_terminal_grid_ref(terminal, ...);          /* point → stable ref */
ghostty_terminal_grid_ref_track(terminal, ...);    /* ref tracks scrolling */
ghostty_terminal_point_from_grid_ref(terminal, ...);
```

A grid ref survives scrolling and reports when it has lost its value. Use these
rather than raw row/column indices in anything long-lived.

### Other API groups

| Group | Header | What it gives you |
|---|---|---|
| Snapshot | `snapshot.h` | Encode terminal state; incremental decoder |
| Render state | `render.h` | Dirty-tracked render state, row/cell iteration |
| Formatter | `formatter.h` | Export as plain text, VT, or HTML |
| Search | `search.h` | Find in screen + scrollback, match iteration for highlight drawing |
| OSC parser | `osc.h` | Parse OSC independently of a terminal |
| SGR parser | `sgr.h` | Parse SGR attributes independently |
| Key encoding | `key/event.h`, `key/encoder.h` | Key event → escape sequence (Kitty keyboard protocol) |
| Mouse encoding | `mouse/event.h`, `mouse/encoder.h` | Mouse event → escape sequence (SGR mouse format) |
| Focus encoding | `focus.h` | Focus in/out sequences |
| Paste | `paste.h` | Paste safety check, unsafe-paste flow, encoding |
| Selection | `selection.h` | Synthetic gesture events → selection snapshots |
| Unicode | `unicode.h` | Codepoint and grapheme width |
| Color | `color.h` | RGB, X11 name parsing, palette generation, luminance, contrast |
| Modes | `modes.h` | Mode report encoding |
| Size report | `size_report.h` | In-band size report encoding |
| Color scheme | `color_scheme.h` | Colour scheme report encoding |
| Build info | `build_info.h` | Compile-time feature queries (SIMD, Kitty graphics, tmux) |
| Allocator | `allocator.h` | `alloc` / `free`, custom allocators |
| IO | `io.h` | Reusable synchronous reader/writer callbacks |
| Sys | `sys.h` | Host callbacks (`set`, `log_stderr`) |
| WASM | `wasm.h` | `alloc` / `free` / `alloc_opaque` / `take_opaque` |
| Types | `types.h` | `ghostty_type_json` ABI manifest |
| Grid refs | `grid_ref.h`, `grid_ref_tracked.h` | Stable cell and row handles |

### 1.7 ABI manifest

```c
ghostty_type_json(...);   /* types.h */
```

Returns a JSON description of the library's own C ABI **for the current target**:
pointer width, `size_t` width, byte order, maximum alignment, and every public
type's kind, size, alignment, field offsets, and enum values.

Binding authors must derive struct layout from this manifest. A hand-written
offset table silently corrupts memory on the next struct change; a manifest
lookup fails loudly.

### Worked example

`example/c-vt/` (OSC parsing), `example/c-vt-formatter/`, `example/c-vt-snapshot/`,
`example/c-vt-search/`, and 30+ siblings under `example/` are the authoritative
usage samples. `example/README.md` indexes them.

---

## 2. Rust — `khostty-vt`

```toml
[dependencies]
khostty-vt = { path = "khostty-vt" }
```

Crate metadata: version `0.1.0`, edition 2021, MSRV 1.75, MIT.

### Features

| Feature | Default | Effect |
|---|---|---|
| `link` | yes | Emit linker directives for a prebuilt `libghostty-vt`. Disable with `--no-default-features` to typecheck without the native library. |
| `bindgen` | no | Regenerate `$OUT_DIR/bindings.rs` from the C headers and compare against the hand-written `src/ffi.rs` (drift check). Requires libclang. |

### Build-time discovery

| Variable | Meaning |
|---|---|
| `GHOSTTY_VT_LIB_DIR` | Directory containing `libghostty-vt.{dylib,so,a}` |
| `GHOSTTY_VT_LIB` | Explicit full path to the library |
| `GHOSTTY_VT_INCLUDE_DIR` | Directory containing `ghostty/vt.h` |
| `GHOSTTY_VT_LINK_KIND` | Force `dylib` or `static` |

Defaults probe `../zig-out/lib`, `../build/lib`, `../dist/lib` relative to the
crate. If nothing is found, the build warns and links nothing: `cargo check`
still succeeds without a Zig toolchain. Integration tests are gated on the
`ghostty_vt_linked` cfg, so they compile to nothing rather than failing.

### Surface (observed 2026-09-17)

```rust
use khostty_vt::{Terminal, Color, Style, GhosttyError};

let mut term = Terminal::new(80, 24)?;
term.vt_write(b"hello\r\n");
assert_eq!(term.cursor_position()?, (7, 1));
```

Construction and mutation:

| Method | Purpose |
|---|---|
| `Terminal::new(cols, rows)` | Library default allocator |
| `Terminal::with_allocator(..)` | Explicit allocator |
| `Terminal::as_raw()` | Escape hatch to the raw handle |
| `vt_write(&mut self, bytes)` | Feed VT input |
| `vt_write_until_ground(..)` | Stop at a stateless stream point |
| `resize(cols, rows, cw_px, ch_px)` | Reflow-capable resize |
| `reset()` | RIS |
| `compress(..)` / `compression_activity(..)` | Scrollback compression |
| `scroll_viewport(..)` | Viewport scrolling |
| `set_write_pty<F>(..)` / `set_bell<F>(..)` | Callback installation |
| `bell_count()` | Count observed bells |

Queries: `cols`, `rows`, `size_px`, `total_rows`, `scrollback_rows`,
`cursor_x`, `cursor_y`, `cursor_position`, `cursor_pending_wrap`,
`cursor_visible`, `cursor_at_prompt`, `cursor_sgr_style`, `active_screen`,
`mouse_tracking`, `kitty_keyboard_flags`, `vt_ground`, `has_vt_processing_error`,
`viewport_active`, `title`, `pwd`, `foreground`, `background`, `cursor_color`,
`palette`, `default_palette`, `scrollbar`, `scrollback_max_bytes`,
`scrollback_max_lines`.

Supporting modules: `error` (`GhosttyError`, mapping every `GhosttyResult`),
`sys` (allocator, owned buffers, two-pass encode helper), `color`, `style`
(`Style`, `StyleColor`, `Underline`), `ffi` (raw bindings, all `unsafe` isolated
here).

### Status and gaps

IN PROGRESS (gate G5). As of 2026-09-17 the crate has raw bindings for 198
functions and a safe `Terminal` wrapper. The safe wrappers named in the WBS for
`snapshot`, `render`, `search`, `key`, and `mouse` are **not yet** present as
public modules. `cargo test` for the wrappers requires a built
`libghostty-vt`.

---

## 3. JavaScript / TypeScript — `@khostty/libghostty-vt-wasm`

The same parser compiled to `wasm32-freestanding`. There is no JavaScript
reimplementation of terminal semantics.

```js
import { Terminal } from "@khostty/libghostty-vt-wasm/api";

using term = await Terminal.open({ cols: 80, rows: 24 });
term.write("Hello\r\n\x1b[1;32mgreen\x1b[0m");
term.text();   // "Hello\ngreen"
term.html();   // HTML with inline styles
```

### Package exports

| Subpath | Module |
|---|---|
| `.` | `js/index.js` — loader plus minimal bindings |
| `./api` | `js/api.js` — `Terminal`, `Snapshot`, `Search`, `openTerminal` |
| `./abi` | `js/abi.js` — allocation, opaque handles, typed struct read/write |
| `./errors` | `js/errors.js` — `GhosttyResult` → `GhosttyError` |

### Loading

```js
Terminal.open({
  cols: 80, rows: 24,        // geometry (defaults 80 × 24)
  allocator: null,           // allocator address, or null for library default
  wasmPath: "...",           // Node: filesystem path
  wasmUrl: "...",            // fetch() URL (default ../khostty-vt.wasm)
  wasmBytes, wasmModule,     // pre-supplied bytes or compiled module
  imports,                   // overrides for the module's declared imports
});
```

The default artifact is the sibling `khostty-vt.wasm`. In a browser it must be
served over HTTP; `file://` fetch is refused. Node-only imports are loaded
lazily, so a bundler that does not shim Node builtins still works.

### `Terminal`

| Member | Kind | Notes |
|---|---|---|
| `write(data)` | method | VT input bytes |
| `resize(cols, rows)` | method | |
| `reset()` | method | |
| `text(opts?)` | method | Plain text |
| `unwrappedText(opts?)` | method | Soft-wrapped lines joined |
| `html(opts?)` | method | Inline-styled HTML |
| `vtText(opts?)` | method | Re-emitted escape sequences |
| `format(opts?)` | method | Lower-level formatter call |
| `snapshot()` | method | Returns a `Snapshot` |
| `search(needle)` | method | Returns a `Search` |
| `close()` | method | Idempotent; also `Symbol.dispose` |
| `cols`, `cursorX`, `cursorY`, `screen`, `cursorVisible`, `totalRows`, `scrollbackRows`, `title` | getters | |
| `handle` | getter | Raw handle, for low-level use |

`FormatOptions`: `emit` (`"PLAIN"` \| `"VT"` \| `"HTML"`), `unwrap` (default
false), `trim` (default true).

### `Snapshot`

`bytes`, `byteLength`, `metadata()` (byte count, source offset, history rows,
…), `restore()`.

### `Search`

`needle`, `status` (`"COMPLETE"` observed), `totalMatches`, `selectedIndex`,
`run()`, `next()`, `prev()`.

### Low-level escape hatch

```js
const vt = await loadGhosttyVt();
const handle = vt.terminalNew({ cols: 80, rows: 24 });
vt.exports.ghostty_terminal_vt_write(handle, ptr, len);
vt.abi.fn("ghostty_terminal_reset")(handle);
```

### Correctness guarantees

| Risk | Mitigation |
|---|---|
| Target-dependent struct layout | All layout read from `ghostty_type_json()` at runtime |
| Terminal data-key → type mapping drift | `tools/gen-terminal-data.mjs` extracts it from the header's `Output type:` lines |
| Linear memory growth invalidating views | `js/memory.js` reacquires views when buffer identity or length changes |
| Use-after-free on library-owned buffers | Copy before free in the shared helper |
| Consolidated header drift | Generated by the C preprocessor; `tools/verify-header.sh` fails if regeneration changes it or the function set differs |

### Limits

- **Kitty graphics is excluded** on freestanding targets (needs OS timestamps).
  The 16 `ghostty_kitty_graphics_*` functions are the only exports withheld from
  the consolidated header. Sequences are still parsed and safely ignored.
- **No OS integration:** no PTY, filesystem, timestamps, or clock.
- **No renderer.** `libghostty-vt` models state; draw the grid yourself or use
  `html()`.

Reference artifact: 813,670 bytes, sha256
`08ac8ed881ffdae68b9f96f9afa6c834e57ba7ea49280d220e882938508e5bf6`,
0 imports, 189 exports (187 `ghostty_*` + memory).

### Verification

```bash
cd wasm
npm run test:header   # consolidated header in sync and compiles
npm test              # 52 runtime + ABI tests against the built artifact
npm run typecheck     # tsc --strict over declarations and a type-level test
npm run exports       # dump the module's import/export sections
npm run check         # all of the above
```

---

## 4. IPC

### 4.1 Upstream action channel (shipped)

`src/apprt/ipc.zig` (252 lines). Typed C ABI, not text.

```zig
pub const Target = union(Key) {
    class: [:0]const u8,   // a named application instance
    detect,                // find the instance to target
};

pub const Action = union(enum) {
    new_window: NewWindow,              // optional config overrides
    new_tab: NewTab,                    // target surface_id + overrides
    toggle_quick_terminal: void,
};
```

Reached from the CLI as `+new-window`, `+new-tab`, `+toggle-quick-terminal`, and
from C through `include/ghostty.h` (`ghostty_ipc_target_*`,
`ghostty_ipc_action_*`). The enum order maps directly to the C enum; new actions
append to the end for ABI compatibility.

**Not available:** pane create/close/focus, state query, scrollback search, event
stream. There is no JSON wire format on this path.

### 4.2 Khostty agent protocol — DRAFT, NOT IMPLEMENTED

The Deep WBS specifies `src/apprt/ipc/` with `protocol.zig`, `server.zig`,
`handler.zig`, `pane.zig`, `state.zig`, `events.zig`, and `auth.zig`. **None of
these files exist as of 2026-09-17.** The only related code is
`src/apprt/windows/ipc.zig`, a named-pipe stub whose every operation returns
`error.Unimplemented`.

The drafted JSON shapes (`pane.create`, `pane.write`, `pane.state`, `pane.list`
and async events) are reproduced in [AGENT.md](AGENT.md) labelled as a draft.
They are a design proposal, not an interface. Do not build against them.

### 4.3 Windows named-pipe transport — SCAFFOLD

`src/apprt/windows/ipc.zig`:

| Item | Value |
|---|---|
| Pipe name | `\\.\pipe\khostty-{server_pid}` |
| Mode | `PIPE_READMODE_MESSAGE \| PIPE_WAIT` |
| Frame | `extern struct { action: u16, length: u32 }` followed by packed payload |
| Server API | `init`, `deinit`, `acceptConnection` |
| Client API | `connect`, `deinit`, `send`, `receive` |
| Behaviour | All return `error.Unimplemented` |

---

## 5. CLI

Invoked as `khostty +<command>`. Defined by `Action` in `src/cli/ghostty.zig`.

| Command | Purpose | Backing module |
|---|---|---|
| `+version` / `--version` | Version and exit | `cli/version.zig` |
| `+help` | CLI or configuration help | `cli/help.zig` |
| `+list-fonts` | Enumerate available fonts | `cli/list_fonts.zig` |
| `+list-keybinds` | Enumerate keybindings | `cli/list_keybinds.zig` |
| `+list-themes` | Enumerate themes | `cli/list_themes.zig` |
| `+list-colors` | Enumerate named RGB colours | `cli/list_colors.zig` |
| `+list-actions` | Enumerate keybind actions | `cli/list_actions.zig` |
| `+ssh` | Wrap `ssh` to configure terminal integration on remote hosts | `cli/ssh.zig` |
| `+ssh-cache` | Manage the SSH terminfo cache | `cli/ssh_cache.zig` |
| `+edit-config` | Open the config in the configured editor | `cli/edit_config.zig` |
| `+show-config` | Dump effective config to stdout | `cli/show_config.zig` |
| `+explain-config` | Explain one config option | `cli/explain_config.zig` |
| `+validate-config` | Validate a config file | `cli/validate_config.zig` |
| `+show-face` | Which font face serves a codepoint | `cli/show_face.zig` |
| `+crash-report` | List (and eventually view/send) crash reports | `cli/crash_report.zig` |
| `+new-window` | IPC: open a window in a running instance | `cli/new_window.zig` |
| `+new-tab` | IPC: open a tab in a running instance | `cli/new_tab.zig` |
| `+toggle-quick-terminal` | IPC: toggle the quick terminal | `cli/toggle_quick_terminal.zig` |
| `+boo` | Easter egg | `cli/boo.zig` |

Parsing notes (`src/cli/args.zig`): `+command` flags may be interleaved with
config overrides; `-e` terminates command scanning so `khostty -e khostty
+version` works as expected.

---

## See also

- [AGENT.md](AGENT.md) — agent integration workflows, including drafted IPC
- [ARCHITECTURE.md](ARCHITECTURE.md) — where each surface sits in the stack
- [BUILD.md](BUILD.md) — producing each artifact
- [PLATFORMS.md](PLATFORMS.md) — which surfaces exist on which platform
- [TESTING.md](TESTING.md) — verifying an integration
- `example/` — authoritative C, Zig, C++, Swift, Python, and WASM samples
