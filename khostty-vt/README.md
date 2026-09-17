# khostty-vt

Safe Rust wrappers for **libghostty-vt**, the virtual terminal emulator library
extracted from [Ghostty](https://ghostty.org).

This crate is the Rust half of Khostty's polyglot FFI gate (Deep WBS G5). It lets
a Rust program parse terminal escape sequences, read the resulting screen, persist
and restore terminal state, search scrollback, and turn input events into the
escape sequences a program under the terminal expects, without touching Zig and
without writing `unsafe` in application code.

```rust
use khostty_vt::{Terminal, Viewport};

let mut term = Terminal::new(80, 24)?;
term.vt_write(b"\x1b[2J\x1b[H$ echo hi\r\nhi\r\n$ ");

assert_eq!(term.cursor_position()?, (2, 4));
assert_eq!(term.cols()?, 80);
assert!(term.vt_ground()?);
# Ok::<(), khostty_vt::GhosttyError>(())
```

## Status

| Area | State |
|------|-------|
| Raw bindings | All 198 exported functions across 34 `include/ghostty/vt/**` headers |
| Safe wrappers | `Terminal`, `RenderState` + row/cell iteration, `SnapshotDecoder` + encoders, `Search`, `KeyEncoder`, `MouseEncoder` |
| Tests | 195 passing across 10 test binaries, all against the real library |
| Verification | ABI layout checked against the C compiler; bindings checked against the headers in both directions |

The upstream headers describe the C API as unstable, so this crate is versioned
independently and every C enum keeps an `Unknown(..)` arm rather than pretending a
newer library's values cannot appear.

## Requirements

A prebuilt `libghostty-vt`. Build it from the Khostty checkout:

```sh
zig build -Dlibghostty-vt=true          # produces zig-out/lib/libghostty-vt.*
```

`build.rs` then finds it automatically, searching in order:

| Variable | Meaning |
|----------|---------|
| `GHOSTTY_VT_LIB` | Explicit path to the library file |
| `GHOSTTY_VT_LIB_DIR` | Directory containing `libghostty-vt.{dylib,so,a}` |
| `GHOSTTY_VT_INCLUDE_DIR` | Directory containing `ghostty/vt.h` |
| `GHOSTTY_VT_LINK_KIND` | Force `dylib` (default) or `static` |

Without any of those it falls back to `../zig-out/lib` and `../include`, which is
where a normal checkout has them.

Two notes on linking:

* On macOS the Zig-produced `libghostty-vt.a` is a fat archive that Apple's `ld`
  rejects ("archive member '/' not a mach-o file"), so shared linking is the
  supported path there. `build.rs` prefers the dylib and adds an rpath so the test
  and example binaries resolve it at run time.
* If no library is found the build still succeeds: `build.rs` prints a warning and
  skips linking, so `cargo check` works on a machine that has not built Zig yet.
  Integration tests and examples then compile to nothing rather than failing.

## Features

| Feature | Default | Effect |
|---------|---------|--------|
| `link` | yes | Emit the linker directives for a prebuilt `libghostty-vt` |
| `bindgen` | no | Regenerate `$OUT_DIR/bindings.rs` with bindgen for the drift check |

```sh
cargo check                              # links, if the library is present
cargo check --no-default-features        # typecheck only
cargo check --features bindgen           # also needs libclang
cargo test
```

`--no-default-features` is a typechecking configuration, not a testable one: it
empties every `extern "C"` symbol, so `cargo check --no-default-features` and
`cargo check --no-default-features --all-targets` both pass, while building a test
or example binary still needs a linked library. Integration tests and examples
compiled without the library become empty rather than failing to build, because
their bodies are gated on the `ghostty_vt_linked` cfg that `build.rs` sets only
after it finds the library.

## Modules

| Module | Contents |
|--------|----------|
| `ffi` | Raw `extern "C"` declarations, generated from the C headers |
| `error` | `GhosttyError`, mapping every `GhosttyResult` code |
| `sys` | Allocator integration, `OwnedBuffer`, the two-pass buffer helper |
| `color`, `style`, `selection` | `Color`, `Style`/`StyleColor`/`Underline`, `GridRef`/`Selection` |
| `terminal` | `Terminal`: VT input, state queries, option setters, event callbacks |
| `render` | `RenderState`, `RowIterator`, `Cells`, frame colours and cursor |
| `snapshot` | Snapshot encode (buffer, alloc, streaming) and `SnapshotDecoder` |
| `search` | `Search`: needle, feed/tick/run, matches as selections |
| `key`, `mouse` | `KeyEncoder`/`KeyEvent`, `MouseEncoder`/`MouseEvent` |

## What the wrappers guarantee

**RAII without leaks.** Every owned handle (`Terminal`, `RenderState`,
`SnapshotDecoder`, `Search`, `KeyEvent`, `KeyEncoder`, `MouseEvent`,
`MouseEncoder`, and the row/cells handles) frees itself in `Drop`, using the
library's own free function. Library-allocated bytes are released through
`ghostty_free` with the allocator that produced them, never through the C `free()`,
which the allocator header calls out as undefined behaviour on Windows.

**`unsafe` is confined.** Every `unsafe` block in this crate is either a raw call
in `ffi` (which is generated), or a thin call site in a wrapper. Each one carries a
`// SAFETY:` comment naming the invariant it relies on.

**Lifetime rules are typed, not documented.** The three upstream rules that are
easy to get wrong are enforced by the borrow checker instead of by comments:

| Upstream rule | How it is enforced |
|---------------|--------------------|
| Row and cell data are invalid once the render state is updated | `RenderState::rows` borrows the state; `update`/`clean` need `&mut self` |
| The terminal from a snapshot READY must outlive the decoder's history replay | `ReadyTerminal` owns the terminal *and* holds the decoder borrow |
| Snapshot source bytes must stay alive until FINISH or free | `SnapshotDecoder` borrows or owns its source |
| One-shot decode may only run before decoding starts | `SnapshotDecoder::decode` consumes the decoder |
| Search `feed`/`set_needle`/`select_*` need exclusive terminal access | Those methods take a `&Terminal` and check it is the right one |

**Callbacks cannot corrupt the process.** Effect closures are called from C. Every
trampoline catches panics so nothing unwinds across the FFI boundary, reentrancy is
handled through interior mutability rather than aliasing, and the terminal is
neither `Send` nor `Sync` because upstream documents no thread-safety (a
compile-time assertion in `src/terminal/mod.rs` keeps it that way).

**Marshalling is checked against the C compiler.** `tests/abi_layout.rs` compares
Rust's `size_of`/`align_of` for 37 mirrored types against a probe compiled and run
against the real headers, recorded in `tests/abi_layout.txt` with its observation
date and compiler. This is not ceremony: it caught `GHOSTTY_TERMINAL_DATA_CURSOR_STYLE`
being documented as returning a whole `GhosttyStyle` (72 bytes) where a 4-byte slot
had been assumed, which corrupted the stack.

## Examples

Two runnable examples, both compiled against the real library:

```sh
cargo run --example screen_dump     # parse VT bytes, print the screen
cargo run --example agent_session   # read, search, snapshot, encode input
```

`screen_dump` output:

```
== screen ==
title: None
size:  48x8
cursor: (2, 4)

 0 |$ cargo build|  (0 coloured cells)
 1 |   Compiling khostty-vt v0.1.0|  (9 coloured cells)
 2 |   Finished dev profile in 1.2s|  (8 coloured cells)
 3 |warning: unused variable `x`|  (7 coloured cells)
 4 |$ |  (0 coloured cells)

dirty: Full
after clean: False
```

`agent_session` shows the agent-shaped workflow, including a real device-attributes
response captured off the write-pty channel:

```
== search ==
matches: 2
selected text: Some("failed")
selected span: row 4 col 22..27

== snapshot ==
snapshot is 1409 bytes
restored title: Some("build")
restored screen matches: true

== input ==
Ctrl+C encodes to [3]

== program query ==
  -> pty: "\u{1b}[?62;22c"
```

## Reading a screen

The most useful thing to build on this crate is a text extractor, which is what
both examples and `tests/end_to_end.rs` do:

```rust
use khostty_vt::render::RenderState;

fn screen_text(term: &khostty_vt::Terminal) -> Result<String, khostty_vt::GhosttyError> {
    let mut state = RenderState::new()?;
    state.update(term)?;

    let mut lines = Vec::new();
    let mut iter = state.rows()?;
    while iter.advance() {
        let mut row = String::new();
        {
            let cells = iter.bind_cells()?;
            while cells.advance() {
                if cells.grapheme_len()? == 0 {
                    continue;
                }
                row.push_str(&cells.graphemes_utf8()?);
            }
        }
        lines.push(row.trim_end().to_string());
    }
    while lines.last().is_some_and(|l| l.is_empty()) {
        lines.pop();
    }
    Ok(lines.join("\n"))
}
```

The inner scope around the row loop is required: `RowIterator` borrows the render
state, so it must be dropped before the state is mutated. That is the header's
"row data is invalid after an update" rule, enforced by the compiler.

## Behaviours worth knowing

Established by probing the linked library, not assumed. Each is pinned by a test.

| Behaviour | Detail |
|-----------|--------|
| Unset colours are `None` | Every colour data key reports `GHOSTTY_NO_VALUE` until something sets it, so `Terminal::foreground()` is `Option<Color>`. `set_background` sets override *and* default; `OSC 11` sets only the override. |
| Render-state theme colours are not derived | `RenderState::colors().background`/`foreground` were observed to stay at zero and to ignore both the terminal options and `OSC 11`. Use your own theme colours and take `palette` from the render state. |
| Mouse reports outside the configured screen are dropped silently | `MouseEncoderSize` needs the real `screen_width`/`screen_height`, not just the cell size, or `encode` returns an empty sequence for everything but the origin. |
| The Alt ESC prefix needs two options | `set_alt_esc_prefix(true)` *and* `set_option_as_alt(OptionAsAlt::True)`; either alone leaves Alt+a as plain `a`. Special keys report Alt through the CSI modifier parameter instead. |
| `set_any_button_pressed` has no observed effect | Across all five formats it did not change the encoded bytes. What decides whether motion is reported is the tracking mode: X10/Normal none, Button drags only, Any everything. |
| `sync_from_terminal` needs the full DECSET pair | Programs enable tracking (1000/1002/1003) and the SGR format (1006) separately; a terminal that only sets 1006 has tracking off and the encoder reports nothing. |
| `MouseFormat::default()` is X10 | X10 is the zero value of `GhosttyMouseFormat`, so it is what an unconfigured encoder uses. It cannot express columns past 223. Reach SGR through 1006 or `set_format`. |
| No `DECSCUSR` read-back | `GHOSTTY_TERMINAL_DATA_CURSOR_STYLE` is the *SGR text style* of the cursor, not its shape. The shape is read from the render state's `cursor().visual_style`. |
| Motion dedup suppresses repeats | The encoder drops a motion report for the same cell as the previous one. `MouseEncoder::reset` clears it. |

## Verification

```sh
cargo test          # 195 tests: 65 unit + 130 integration against the real library
cargo clippy --all-targets
cargo fmt --check
```

The generated artifacts have their own guards:

```sh
python3 tools/gen_ffi.py            # rewrite src/ffi.rs from the headers
python3 tools/gen_ffi.py --check    # fail if src/ffi.rs is stale
python3 tools/dump_abi_layout.py            # refresh tests/abi_layout.txt
python3 tools/dump_abi_layout.py --check    # fail if the ABI snapshot is stale
```

`tests/ffi_coverage.rs` independently re-derives the exported function set from the
headers at test time and compares it against `src/ffi.rs` in both directions, so a
generated file that has drifted cannot pass. Adding a binding the headers do not
declare makes it fail; adding a header function the binding omits makes it fail.

## Regenerating the bindings

```sh
python3 tools/gen_ffi.py
```

The generator parses the real headers and emits `src/ffi.rs`. It honours the
conventions the headers actually use: `GHOSTTY_API` declarations (with the macro's
own `#define` excluded), `int`-backed enums as `c_int` aliases plus constants,
anonymous structs and unions with `#[derive(Clone, Copy)] #[repr(C)]`, opaque
handles as pointers to zero-sized structs, forward `typedef struct Tag Name;`
declarations, bare `struct Tag { .. };` definitions, array members, and the
`#ifdef __wasm__` guard that excludes WebAssembly-only symbols. Anything it cannot
represent is listed in the generated file's `SKIPPED` section rather than dropped.

The generator is three files, each with one concern: `tools/cscan.py` scans C text
(comment stripping, brace-aware declaration boundaries, target guards),
`tools/cabitypes.py` maps C types to Rust and models emitted items, and
`tools/gen_ffi.py` discovers headers and emits Rust.

`build.rs` can additionally generate bindings with bindgen into `$OUT_DIR` under
the `bindgen` feature, which is how the generator's function set was originally
cross-checked against libclang's view of the same headers.

## License

MIT, matching libghostty-vt's own headers.
