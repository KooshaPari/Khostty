# API Reference

**Observed:** 2026-09-17 · Read the status line before building on any surface.

| Surface | Entry point | Stability | Status |
|---|---|---|---|
| C ABI | `include/ghostty/vt.h` | Explicitly unstable upstream ("work-in-progress") | DONE (G1/G2) |
| Rust | `khostty-vt/` crate | Pre-1.0; wrappers added incrementally | IN PROGRESS (G5) |
| JS/TS (WASM) | `wasm/js/` package | Pre-1.0 (`version: 0.0.0`) | IN PROGRESS (G7) |
| IPC | `src/apprt/ipc.zig` (3 actions) | Stable but narrow | DONE, narrow |
| IPC (agent protocol) | `src/apprt/ipc/` | **No server yet — not reachable** | IN PROGRESS (G4) |
| CLI | `khostty +<command>` | Follows upstream | DONE |

**Not available, do not code against:** the JSON agent IPC protocol (v1) has an
implemented wire layer and a spec at
[`src/apprt/ipc/protocol.md`](../src/apprt/ipc/protocol.md), but **no `server.zig`
and no runtime wiring**, so nothing is listening (§4.2).

---

## 1. C ABI — `libghostty-vt`

### Header

```c
#include <ghostty/vt.h>
```

The umbrella header includes 30 module headers and declares **203 `GHOSTTY_API`
functions**. `GHOSTTY_API` expands to `__declspec(dllexport/dllimport)` on Windows
and `__attribute__((visibility("default")))` elsewhere.

The header's own warning, quoted because it is the contract: *"This is an
incomplete, work-in-progress API. It is not yet stable and is definitely going to
change."* Pin a revision; do not assume ABI compatibility across versions.

### Linking

| Artifact | Flag | File |
|---|---|---|
| Shared | default for lib targets | `libghostty-vt.0.1.0.dylib` / `.so` |
| Static | `-Demit-lib-vt` | `libghostty-vt.a` |
| Apple multi-platform | `-Demit-xcframework` | `.xcframework` |
| WebAssembly | `-Dtarget=wasm32-freestanding` | `ghostty-vt.wasm` |

Full commands: [BUILD.md](BUILD.md).

### Result codes

| Code | Value | Meaning |
|---|---:|---|
| `GHOSTTY_SUCCESS` | 0 | Success |
| `GHOSTTY_OUT_OF_MEMORY` | −1 | Allocation failure |
| `GHOSTTY_INVALID_VALUE` | −2 | Invalid argument |
| `GHOSTTY_OUT_OF_SPACE` | −3 | Buffer too small; required capacity returned |
| `GHOSTTY_NO_VALUE` | −4 | Valid query, no value yet |

`GHOSTTY_OUT_OF_SPACE` is a *two-pass* signal, not a failure: the call reports the
required capacity so the caller can allocate and retry. The Rust `sys` module wraps
that pattern.

### Terminal lifecycle

```c
GhosttyResult ghostty_terminal_new(const GhosttyAllocator* allocator,
                                   GhosttyTerminal* terminal,
                                   uint16_t cols, uint16_t rows);
void          ghostty_terminal_free(GhosttyTerminal terminal);
void          ghostty_terminal_reset(GhosttyTerminal terminal);
GhosttyResult ghostty_terminal_resize(term, cols, rows, cell_w_px, cell_h_px);
void          ghostty_terminal_vt_write(term, const uint8_t* data, size_t len);
GhosttyResult ghostty_terminal_vt_write_until_ground(term, data, len, size_t* out_consumed);
GhosttyResult ghostty_terminal_set(term, GhosttyTerminalOption option, const void* value);
GhosttyResult ghostty_terminal_get(term, GhosttyTerminalData key, void* out);
```

Behaviour that matters when embedding:

- **`vt_write` never fails.** Input is untrusted; malformed sequences are logged
  and state is kept consistent. No pre-validation needed.
- **`reset` == RIS.** Modes, scrollback, scrolling region, and screen contents are
  cleared; dimensions survive.
- **`resize` reflows** the primary screen when wraparound is on (the alternate
  screen does not reflow). It also updates pixel dimensions, clears
  synchronized-output mode, and emits an in-band size report if mode 2048 is on.
- **`vt_write_until_ground`** consumes exactly the prefix needed to reach a
  stateless point — the safe seam for injecting your own out-of-band sequences
  into a PTY stream. Returns `GHOSTTY_NO_VALUE` if the whole slice was consumed
  without reaching ground.

### Callbacks and options

`ghostty_terminal_set` takes a `GhosttyTerminalOption` (40 defined, values 0–39),
including:

| Option group | Purpose |
|---|---|
| `…_USERDATA` | Opaque pointer handed back to callbacks |
| `…_WRITE_PTY` | Receives query responses (DSR, DA, …) the terminal would normally write back to the PTY |
| `…_BELL` | Bell notification |
| `…_TITLE`, `…_PWD`, `…_TITLE_CHANGED`, `…_PWD_CHANGED` | Programmatic title / working directory and their change notifications |
| `…_COLOR_FOREGROUND`, `…_BACKGROUND`, `…_CURSOR`, `…_COLOR_PALETTE` | Theme injection |
| `…_SELECTION` | Selection state |
| `…_SCROLLBACK_MAX_BYTES`, `…_MAX_LINES` | Scrollback bounds |
| `…_KITTY_IMAGE_*` | Image storage limits and media policy |
| `…_MODE_DEFAULT`, `…_MODE` | DEC private mode defaults |
| `…_TERMINFO_NAME` | Reported terminfo name |
| `…_CLIPBOARD_READ`, `…_CLIPBOARD_WRITE` | Clipboard bridge |
| `…_DESKTOP_NOTIFICATION`, `…_PROGRESS_REPORT` | Host notifications |

All 40 option names are prefixed `GHOSTTY_TERMINAL_OPT_`.

Two constraints: **callbacks run synchronously during VT writes**, so they must not
call `vt_write`/`vt_write_until_ground` on the same terminal (no reentrancy); and
**non-pointer option values are passed by pointer** (`GhosttyString*`, not
`GhosttyString`), while callbacks and userdata are passed directly.

### Queries

`ghostty_terminal_get(terminal, key, out)` writes a caller-allocated out parameter
whose type depends on the key. 41 keys are defined (0–40, including the `INVALID`
sentinel). Examples:

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
out-parameter type depends on the key, a binding cannot guess it: the header
documents each `Output type:` line, the WASM generator extracts that mapping into
`wasm/js/terminal-data.js`, and the Rust crate encodes it in
`src/terminal/types.rs`. Per-target widths come from the type manifest.

### Grid references

`ghostty_terminal_grid_ref` (point → stable ref), `ghostty_terminal_grid_ref_track`
(ref tracks scrolling), and `ghostty_terminal_point_from_grid_ref`. A grid ref
survives scrolling and reports when it has lost its value, so use these rather than
raw row/column indices in anything long-lived.

### Other API groups

| Group | Header(s) | What it gives you |
|---|---|---|
| Snapshot / render state | `snapshot.h`, `render.h` | Encode terminal state with an incremental decoder; dirty-tracked render state with row/cell iteration |
| Output | `formatter.h` | Export as plain text, VT, or HTML |
| Search | `search.h` | Find in screen + scrollback; match iteration for highlight drawing |
| Standalone parsers | `osc.h`, `sgr.h` | Parse OSC and SGR independently of a terminal |
| Input encoding | `key/event.h` + `key/encoder.h`, `mouse/event.h` + `mouse/encoder.h`, `focus.h` | Key (Kitty protocol), mouse (SGR format), and focus in/out → escape sequences |
| Paste / selection | `paste.h`, `selection.h` | Safety check, unsafe-paste confirmation flow, bracketed encoding; synthetic gesture events → selection snapshots |
| Grid refs | `grid_ref.h`, `grid_ref_tracked.h` | Stable cell and row handles that survive scrolling |
| Text metrics / colour | `unicode.h`, `color.h` | Codepoint and grapheme width; RGB, X11 name parsing, palette generation, luminance, contrast |
| Reports | `modes.h`, `size_report.h`, `color_scheme.h` | Mode, in-band size, and colour-scheme report encoding |
| Build info | `build_info.h` | Compile-time feature queries (SIMD, Kitty graphics, tmux) |
| Host plumbing | `allocator.h`, `io.h`, `sys.h`, `wasm.h` | `alloc`/`free`, reader/writer callbacks, host `set`/`log_stderr`, WASM handle helpers |
| ABI manifest | `types.h` | `ghostty_type_json` |

### ABI manifest

`ghostty_type_json(...)` (`types.h`) returns a JSON description of the library's own
C ABI **for the current target**: pointer width, `size_t` width, byte order,
maximum alignment, and every public type's kind, size, alignment, field offsets, and
enum values.

Binding authors must derive struct layout from this manifest. A hand-written
offset table silently corrupts memory on the next struct change; a manifest
lookup fails loudly.

### Worked example

The 35 projects under `example/` (indexed by `example/README.md`) are the
authoritative usage samples: `c-vt` (OSC parsing), `c-vt-formatter`,
`c-vt-snapshot`, `c-vt-search`, and siblings.

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
| `link` | yes | Emit linker directives for a prebuilt `libghostty-vt`. `--no-default-features` typechecks without the native library. |
| `bindgen` | no | Regenerate `$OUT_DIR/bindings.rs` and diff it against `src/ffi.rs` (drift check). Requires libclang. |

### Build-time discovery

| Variable | Meaning |
|---|---|
| `GHOSTTY_VT_LIB_DIR` | Directory containing `libghostty-vt.{dylib,so,a}` |
| `GHOSTTY_VT_LIB` | Explicit full path to the library |
| `GHOSTTY_VT_INCLUDE_DIR` | Directory containing `ghostty/vt.h` |
| `GHOSTTY_VT_LINK_KIND` | Force `dylib` or `static` |

Defaults probe `../zig-out/lib`, `../build/lib`, `../dist/lib`. If nothing is
found the build warns and links nothing, so `cargo check` still succeeds without a
Zig toolchain. Integration tests are gated on the `ghostty_vt_linked` cfg and
compile to nothing rather than failing.

### Surface (observed 2026-09-17)

```rust
use khostty_vt::{Terminal, Color, Style, GhosttyError};

let mut term = Terminal::new(80, 24)?;
term.vt_write(b"hello\r\n");
assert_eq!(term.cursor_position()?, (7, 1));
```

| Area | Methods |
|---|---|
| Construct | `new(cols, rows)`, `with_allocator(..)`, `as_raw()` |
| Mutate | `vt_write(bytes)`, `vt_write_until_ground(..)`, `resize(cols, rows, cw_px, ch_px)`, `reset()`, `scroll_viewport(..)` |
| Scrollback | `compress(..)`, `compression_activity(..)`, `scrollback_max_bytes()`, `scrollback_max_lines()` |
| Callbacks | `set_write_pty<F>(..)`, `set_bell<F>(..)`, `bell_count()` |
| Geometry | `cols`, `rows`, `size_px`, `total_rows`, `scrollback_rows`, `scrollbar` |
| Cursor | `cursor_x`, `cursor_y`, `cursor_position`, `cursor_pending_wrap`, `cursor_visible`, `cursor_at_prompt`, `cursor_sgr_style` |
| Screen / modes | `active_screen`, `viewport_active`, `mouse_tracking`, `kitty_keyboard_flags` |
| Parser state / text | `vt_ground`, `has_vt_processing_error`, `title`, `pwd` |
| Theme | `foreground`, `background`, `cursor_color`, `palette`, `default_palette` |

Supporting modules: `error` (`GhosttyError`, mapping every `GhosttyResult`),
`sys` (allocator, owned buffers, two-pass encode helper), `color`, `style`
(`Style`, `StyleColor`, `Underline`), `ffi` (raw bindings, all `unsafe` isolated
here).

Safe RAII wrappers re-exported from the crate root (observed 2026-09-17 03:52 PT):

| Export | Module | Wraps |
|---|---|---|
| `Terminal`, `Viewport` | `terminal` | Terminal lifecycle, queries, mutation |
| `SnapshotDecoder`, `encode_snapshot` | `snapshot` | Snapshot encode/decode with lifetime-enforced rules |
| `RenderState`, `Dirty` | `render` | Render state with borrow-checked row/cell access |
| `Search`, `SearchStatus` | `search` | Scrollback search |
| `Key`, `KeyEncoder`, `KeyEvent`, `Mods` | `key` | Key encoding |
| `MouseEncoder`, `MouseEvent` | `mouse` | Mouse encoding |
| `Selection`, `GridRef` | `selection` | Selection and stable grid references |

Integration tests mirror these: `tests/terminal.rs`, `snapshot.rs`, `render.rs`,
`search.rs`, `key_encoding.rs`, plus `abi_layout.rs` for the layout guard.

### Status and gaps

IN PROGRESS (gate G5). The crate is feature-complete against the WBS module list
and has raw bindings for 198 functions, but:

- The crate doc comment in `lib.rs` still describes wrappers as arriving
  incrementally; the exports above are ahead of that comment.
- There is **no safe formatter wrapper**, so no `text()` / `html()` in Rust. Use
  the raw `ffi` bindings or the WASM package.
- `cargo test` needs a built `libghostty-vt`; without one the test files compile to
  nothing via `ghostty_vt_linked`.
- No `cargo test` run is recorded in this session. Treat the surface as
  present-but-unverified.

---

## 2b. Go — `khostty-go`

IN PROGRESS (gate G6). Cgo bindings for the same C ABI.

Files: `go.mod`; `doc.go` (link contract and toolchain caveats);
`link_default.go` / `link_custom.go` (cgo directives, with a `khostty_custom_lib`
build tag for an out-of-tree library); `ffi.go`, `abi.go`, `manifest.go`,
`enums.go` (FFI helpers, type-manifest access, enum mirrors); `ghostty_vt.go`,
`ghostty_vt_get.go` (lifecycle and typed queries); `ghostty_snapshot.go`,
`ghostty_render.go`, `ghostty_search.go`; `style.go` (style and colour mirrors);
per-area `*_test.go`; and a `Makefile`.

Default link directives point at `../include` and `../zig-out/lib` with an rpath,
so the shared object's `@rpath` install name resolves. Verified at commit time by
its author: `go build ./...` and `go vet ./...` clean, with a link probe calling
`ghostty_type_json()` returning the 43,543-byte type manifest. That verification is
recorded in the commit ledger, not re-run here.

There is **no Python wrapper** yet; that half of G6 is not started.

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

`.` → `js/index.js` (loader + minimal bindings) · `./api` → `js/api.js`
(`Terminal`, `Snapshot`, `Search`, `openTerminal`) · `./abi` → `js/abi.js`
(allocation, opaque handles, typed struct read/write) · `./errors` → `js/errors.js`
(`GhosttyResult` → `GhosttyError`).

### Loading

`Terminal.open(options)` accepts `cols` / `rows` (defaults 80 × 24), `allocator`
(address, or `null` for the library default), and a source — one of `wasmPath`
(Node filesystem path), `wasmUrl` (fetched; default `../khostty-vt.wasm`),
`wasmBytes`, or `wasmModule` — plus `imports` to override the module's declared
imports.

In a browser the artifact must be served over HTTP; `file://` fetch is refused.
Node-only imports are loaded lazily, so a bundler that does not shim Node builtins
still works.

### `Terminal`

| Kind | Members |
|---|---|
| Methods | `write(data)`, `resize(cols, rows)`, `reset()`, `text(opts?)`, `unwrappedText(opts?)`, `html(opts?)`, `vtText(opts?)`, `format(opts?)`, `snapshot()`, `search(needle)`, `close()` |
| Getters | `cols`, `cursorX`, `cursorY`, `screen`, `cursorVisible`, `totalRows`, `scrollbackRows`, `title` |
| Escape hatch | `handle` (raw wasm handle for low-level use) |

`close()` is idempotent and each class implements `Symbol.dispose`, so `using`
works and nothing leaks.

`FormatOptions`: `emit` (`"PLAIN"` \| `"VT"` \| `"HTML"`), `unwrap` (default
false), `trim` (default true).

### `Snapshot` and `Search`

`Snapshot`: `bytes`, `byteLength`, `metadata()` (byte count, source offset, history
rows, …), `restore()`. `Search`: `needle`, `status` (`"COMPLETE"` observed),
`totalMatches`, `selectedIndex`, `run()`, `next()`, `prev()`.

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
| Target-dependent struct layout | Layout read from `ghostty_type_json()` at runtime |
| Data-key → type mapping drift | `tools/gen-terminal-data.mjs` extracts it from the header's `Output type:` lines |
| Linear-memory growth invalidating views | `js/memory.js` reacquires views when buffer identity or length changes |
| Use-after-free on library-owned buffers | Copy before free in the shared helper |
| Consolidated-header drift | Generated by the C preprocessor; `tools/verify-header.sh` fails on any diff or function-set mismatch |

### Limits

- **Kitty graphics excluded** on freestanding targets (needs OS timestamps). The 16
  `ghostty_kitty_graphics_*` functions are the only exports withheld from the
  consolidated header; sequences are still parsed and safely ignored.
- **No OS integration** (no PTY, filesystem, timestamps, clock) and **no renderer** —
  `libghostty-vt` models state, so draw the grid yourself or use `html()`.

Reference artifact: 813,670 bytes, sha256 `08ac8ed8…`, 0 imports, 189 exports
(187 `ghostty_*` + memory).

### Verification

```bash
cd wasm && npm run check   # header sync + typecheck + 52 runtime/ABI tests + exports
```

---

## 4. IPC

### 4.1 Upstream action channel (shipped)

`src/apprt/ipc/mod.zig` (moved from `src/apprt/ipc.zig`; 252 lines). A typed C ABI,
not text.

```zig
pub const Target = union(Key) {
    class: [:0]const u8,   // a named application instance
    detect,                // find the instance to target
};

pub const Action = union(enum) {
    new_window: NewWindow,   // optional config overrides
    new_tab: NewTab,         // target surface_id + overrides
    toggle_quick_terminal: void,
};
```

Reached from the CLI as `+new-window`, `+new-tab`, `+toggle-quick-terminal`, and
from C through `include/ghostty.h` (`ghostty_ipc_target_*`,
`ghostty_ipc_action_*`). Enum order maps directly to the C enum; new actions append
to the end for ABI compatibility.

**Not available on this path:** pane create/close/focus, state query, scrollback
search, event stream, or any JSON wire format.

### 4.2 Khostty agent protocol v1 — IN PROGRESS, no server

**Normative spec:** [`src/apprt/ipc/protocol.md`](../src/apprt/ipc/protocol.md).
That file is the authority for framing, commands, options, auth, versioning, and
known limits. This subsection records status only.

Implemented modules (observed 2026-09-17 03:51 PT):

`protocol.md` (v1 spec), `protocol.zig` (wire types, JSON codec), `state.zig`
(terminal state snapshot), `events.zig` (async event broker), `auth.zig` (token
auth, fail-closed), `pane.zig` (pane lifecycle + `Host` vtable), `fake_host.zig`
(test host).

Unreachable because four things are missing: `server.zig` (no accept loop, nothing
listens), `app_host.zig` (no app-backed host, only the fake test host), no
re-export from `src/apprt/ipc/mod.zig` (not reachable via the `apprt` interface),
and no runtime wiring.

Command set (13 commands), per the spec: `ping`, `pane.create`, `pane.close`,
`pane.focus`, `pane.list`, `pane.write`, `pane.state`, `pane.search`,
`pane.resize_split`, `pane.equalize`, `pane.zoom`, `events.subscribe`,
`events.unsubscribe`.

Transport: Unix domain socket, line-delimited JSON, integer version check.
Default path `~/Library/Caches/khostty/ipc.sock` (macOS) or
`$XDG_RUNTIME_DIR/khostty/ipc.sock` (Linux/BSD), overridable via
`KHOSTTY_IPC_SOCKET`. Windows named pipe is a stated follow-up.

Auth: required for every command except `ping`. Sources in order:
`KHOSTTY_IPC_TOKEN`, then a token file. **Fail-closed** — with no token configured,
authenticated commands are rejected and the server never runs unauthenticated;
comparison is constant-time.

**Do not build against this yet.** See [AGENT.md](AGENT.md#4-agent-ipc-protocol-v1--in-progress-not-yet-reachable).

### 4.3 Windows named-pipe transport — SCAFFOLD

`src/apprt/windows/ipc.zig`:

Pipe `\\.\pipe\khostty-{server_pid}`, mode
`PIPE_READMODE_MESSAGE | PIPE_WAIT`, frame
`extern struct { action: u16, length: u32 }` followed by a packed payload.
Server API: `init`, `deinit`, `acceptConnection`. Client API: `connect`, `deinit`,
`send`, `receive`. **All operations return `error.Unimplemented`.**

The declared security attributes are worth noting: a null security descriptor
(inheriting the process default DACL) and `bInheritHandle = TRUE`. See
[SECURITY.md](SECURITY.md#4-windows-transport-weakness-scaffold).

---

## 5. CLI

Invoked as `khostty +<command>`. Defined by `Action` in `src/cli/ghostty.zig`;
one module per command under `src/cli/`.

| Group | Commands | Backing modules |
|---|---|---|
| Version / help | `+version` (also `--version`), `+help` | `version.zig`, `help.zig` |
| Introspection | `+list-fonts`, `+list-keybinds`, `+list-themes`, `+list-colors`, `+list-actions` | `list_fonts.zig`, `list_keybinds.zig`, `list_themes.zig`, `list_colors.zig`, `list_actions.zig` |
| Configuration | `+edit-config`, `+show-config`, `+explain-config`, `+validate-config` | `edit_config.zig`, `show_config.zig`, `explain_config.zig`, `validate_config.zig` |
| Diagnostics | `+show-face` (which font face serves a codepoint), `+crash-report` | `show_face.zig`, `crash_report.zig` |
| Remote integration | `+ssh`, `+ssh-cache` | `ssh.zig`, `ssh_cache.zig` |
| Drive a running instance (IPC) | `+new-window`, `+new-tab`, `+toggle-quick-terminal` | `new_window.zig`, `new_tab.zig`, `toggle_quick_terminal.zig` |
| Easter egg | `+boo` | `boo.zig` |

Parsing notes (`src/cli/args.zig`): `+command` flags may be interleaved with
config overrides; `-e` terminates command scanning so `khostty -e khostty
+version` works as expected.

---

## See also

- [AGENT.md](AGENT.md) — agent workflows and the IPC status
- [ARCHITECTURE.md](ARCHITECTURE.md) — where each surface sits in the stack
- [BUILD.md](BUILD.md) — producing each artifact · [PLATFORMS.md](PLATFORMS.md) — availability per platform
- [TESTING.md](TESTING.md) — verifying an integration · [SECURITY.md](SECURITY.md) — trust boundaries
- `example/` — authoritative C, Zig, C++, Swift, Python, and WASM samples
