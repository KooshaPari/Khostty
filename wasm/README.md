# libghostty-vt for WebAssembly

Browser and Node.js bindings for `libghostty-vt`, the virtual terminal emulator
extracted from [Ghostty](https://ghostty.org) and carried in this Khostty fork.

The module is `libghostty-vt` compiled to `wasm32-freestanding`: the same VT
parser, screen model, formatter, snapshot codec, and search index that the
native library provides. There is no JavaScript reimplementation of terminal
semantics, so what runs in the browser is byte-for-byte the parser that runs in
the desktop app.

```js
import { Terminal } from "@khostty/libghostty-vt-wasm/api";

using term = await Terminal.open({ cols: 80, rows: 24 });
term.write("Hello, World!\r\n\x1b[1;32mgreen bold\x1b[0m");

term.text();
// "Hello, World!\ngreen bold"

term.html();
// <div style="font-family: monospace; white-space: pre;">Hello, World!
// <div style="display: inline;color: var(--vt-palette-2);font-weight: bold;">green bold</div></div>
```

## Contents

| Path | What it is |
|---|---|
| `khostty-vt.wasm` | The compiled module. **Not committed**; run `./build.sh`. |
| `build.sh` | Pinned, reproducible wasm32 build of `libghostty-vt`. |
| `js/index.js` | ESM loader plus minimal bindings (terminal, formatter, snapshot, search handles). |
| `js/api.js` | High-level entry point: `Terminal`, `Snapshot`, `Search`, `openTerminal`. |
| `js/terminal.js` | `Terminal`: state getters, `write`, `resize`, `reset`, `text`/`html`/`vtText`, `snapshot`, `search`. |
| `js/snapshot.js` | `Snapshot`: `bytes`, `metadata()`, `restore()`. |
| `js/search.js` | `Search`: `needle`, `status`, `totalMatches`, `selectedIndex`, `run`, `next`, `prev`. |
| `js/abi.js` | `Abi`: allocation, opaque-handle construction, typed struct read/write. |
| `js/layout.js` | `TypeLayout`: the type manifest the library publishes. |
| `js/memory.js` | `Memory`: growth-safe linear memory access. |
| `js/errors.js` | `GhosttyResult` to `GhosttyError`. |
| `js/terminal-data.js` | Generated `GhosttyTerminalData` key to out-parameter type map. |
| `js/*.d.ts` | TypeScript declarations, one file per module. |
| `include/ghostty-vt.h` | The whole public C ABI in a single self-contained header. |
| `tools/` | Generators, the wasm section parser, and the header verifier. |
| `test/` | Runtime smoke test, ABI conformance test, type-level test. |

## Building

```bash
./build.sh                    # ReleaseSmall (default)
./build.sh --debug            # much larger, with debug info
./build.sh --optimize ReleaseFast
```

Requires Zig 0.16 or newer. No additional toolchain: the upstream `build.zig`
already knows how to emit WebAssembly, because a `wasm32` target routes through
`GhosttyLibVt.initWasm()`, which produces a freestanding module with `rdynamic`
exports, a growable indirect function table, no entrypoint, and a 128 KB stack.

`build.sh` validates the emitted file's WebAssembly magic and version rather
than trusting the build's exit code, then prints the artifact's size and hash.

The reference artifact for this commit:

```
813670 bytes   sha256 08ac8ed881ffdae68b9f96f9afa6c834e57ba7ea49280d220e882938508e5bf6
0 imports      189 exports (187 ghostty_* functions + memory)
```

### One build gotcha

The build uses its own cache directory (`.zig-cache/wasm`) instead of the
repository's `.zig-cache`. Two reasons:

1. The wasm and host targets share no compilation artifacts, so a shared cache
   only adds lock contention with concurrent native builds.
2. A cached build runner generated against a different `zig-pkg` layout can go
   stale and fail at startup with `unable to open .../zig-pkg/<dep>: FileNotFound`.
   That failure is unrelated to this build and makes even `zig build --help`
   fail from the affected checkout. Isolating the cache sidesteps it without
   discarding a cache another build may be using.

Set `KHOSTTY_WASM_CACHE` to relocate it.

## Usage

### Node.js

```js
import { Terminal } from "./wasm/js/api.js";

await using term = await Terminal.open({ cols: 80, rows: 24 });
term.write("prompt$ ls -la\r\n");
process.stdout.write(term.text());
```

The default source is the sibling `khostty-vt.wasm`. Point it elsewhere with any
of `wasmPath`, `wasmUrl`, `wasmBytes`, or `wasmModule`:

```js
const term = await Terminal.open({ wasmPath: "/opt/ghostty/libghostty-vt.wasm" });
```

### Browser

```html
<script type="module">
  import { Terminal } from "./wasm/js/api.js";

  const term = await Terminal.open({ cols: 80, rows: 24 });
  term.write("Hello from the browser\r\n");
  document.querySelector("pre").textContent = term.text();
</script>
```

`wasmUrl` defaults to `../khostty-vt.wasm` relative to `js/index.js`, resolved
with `fetch`. The module must be served over HTTP: browsers refuse to fetch a
module from a `file://` page.

The Node-only imports (`node:fs`, `node:url`) are loaded lazily inside the file
path resolver, so a browser or a bundler that does not shim Node builtins still
loads the module.

From a CDN, the artifact and bindings are two fetches:

```js
import { loadGhosttyVt } from "https://cdn.example/@khostty/libghostty-vt-wasm/js/index.js";
const vt = await loadGhosttyVt({ wasmUrl: "https://cdn.example/@khostty/libghostty-vt-wasm/khostty-vt.wasm" });
```

### The object model

```js
await using term = await Terminal.open({ cols: 40, rows: 6 });
term.write("alpha beta\r\ndelta beta");

term.cols;             // 40
term.cursorX;          // 10
term.cursorY;          // 1
term.screen;           // "PRIMARY"
term.cursorVisible;    // true
term.totalRows;        // 6
term.scrollbackRows;   // 0
term.title;            // "" (or the OSC 0/2 title)

term.text();           // plain text
term.unwrappedText();  // soft-wrapped lines joined
term.html();           // HTML with inline styles
term.vtText();         // re-emitted escape sequences

// Snapshot: capture, inspect, restore
const snap = term.snapshot();
snap.byteLength;       // 1118 for the content above
snap.metadata();       // { bytes, sourceOffset, historyRowsPrimary, ... }
const restored = snap.restore();

// Search
const search = term.search("beta");
search.run();
search.totalMatches;   // 2
search.status;         // "COMPLETE"
search.next();
search.selectedIndex;  // 0
```

Every class owns a wasm handle, `close()` is idempotent, and each implements
`Symbol.dispose`, so `using` works and nothing leaks.

### Low-level access

`Terminal#handle` and the module's `exports` are both exposed for anything the
object model does not cover:

```js
const vt = await loadGhosttyVt();
const handle = vt.terminalNew({ cols: 80, rows: 24 });
vt.exports.ghostty_terminal_vt_write(handle, ptr, len);
vt.abi.fn("ghostty_terminal_reset")(handle);
```

## How the bindings stay correct

**No target-dependent number is hardcoded.** The library exports
`ghostty_type_json()`, which returns a JSON manifest of its own C ABI for the
current target: pointer and `size_t` widths, byte order, maximum alignment, and
every public type's kind, size, alignment, field offsets, and enum values. The
bindings read that manifest and lay out every struct from it. A hand-written
offset table would silently corrupt memory on the next struct change; a manifest
lookup fails loudly instead.

**The terminal data-key table is generated.** `ghostty_terminal_get()` writes a
caller-allocated out parameter whose type depends on the key, and that mapping
exists only in `terminal.h`'s documentation. `tools/gen-terminal-data.mjs`
extracts it from the header's `Output type:` lines and normalizes each entry to a
manifest type name, so it cannot drift. Only the search equivalent is
hand-written, because `search.h` documents those types in prose; the ABI test
validates every name, value, and type in it against the manifest.

**Memory views are never cached across an allocation.** `wasm.h` states that an
exported function may grow linear memory, leaving host-side `ArrayBuffer`,
`DataView`, and typed-array objects pointing at a detached buffer. A stale view
still reads and writes, so the bug looks like plausible data rather than a
crash. `Memory` reacquires its views whenever the buffer identity or length
changes, and everything else goes through it.

**Copy before free.** The `*_alloc` APIs return a library-owned buffer that must
be released with `ghostty_free()`. The shared helper copies first and frees
second, because the reverse order is a silent use-after-free.

**The consolidated header is generated, not transcribed.** `include/ghostty-vt.h`
is produced by running the C preprocessor over a translation unit that includes
`<ghostty/vt.h>` and keeping only the regions originating under
`include/ghostty/`. Using the compiler as the extractor means it cannot drift
from the real headers. `tools/verify-header.sh` fails if regenerating changes the
committed file, if it does not compile standalone under clang and `zig cc`, or if
its function set differs from the union of the real headers (203 functions).

## Verifying

```bash
cd wasm
npm run test:header     # consolidated header is in sync and compiles
npm test                # 52 runtime + ABI tests against the built artifact
npm run typecheck       # tsc --strict over the declarations and a type-level test
npm run exports         # dump the module's import/export sections
npm run check           # all of the above
```

There are no npm dependencies. The runtime tests use `node:test`, the wasm
section parser is written from the binary format spec, and `typecheck` fetches
`typescript` on demand via `npx`. Nothing touches the DOM, so there is no jsdom
or headless-browser requirement: the module is freestanding and the bindings are
plain ESM, which means Node exercises the same code path a browser would.

The ABI test asserts that the exported function set equals the set declared in
the consolidated header minus an explicit, reasoned list. The only current entry
is the 16 `ghostty_kitty_graphics_*` functions, which
`src/terminal/build_options.zig` disables on freestanding targets because the
feature needs OS timestamps. Adding an export, or failing to export a new
declaration, fails the test until the change is recorded deliberately.

The type-level test (`test/types.test-d.ts`) exercises the declared surface the
way a TypeScript consumer would, in strict mode with `skipLibCheck: false`. A
method that exists at runtime but is missing from a `.d.ts` is invisible to
consumers, so it becomes a compile error here.

## What this build does not include

- **Kitty graphics.** Disabled on freestanding targets by design, as above. The
  sequences are still consumed and safely ignored, so parsing stays correct.
- **Anything requiring an OS.** No PTY, no filesystem, no timestamps, no
  clock. This is a VT core: bytes in, screen state out.
- **A renderer.** `libghostty-vt` models terminal state. Draw the grid yourself,
  or use `term.html()` for a quick plain-text-plus-style view.

## Relationship to the rest of the repository

- `example/wasm-vt/`, `example/wasm-sgr/`, `example/wasm-key-encode/` are the
  upstream hand-written HTML demos. They show the raw C ABI from a script tag;
  this directory is the packaged, typed binding layer.
- `include/ghostty/` remains the source of truth for the API. Regenerate the
  consolidated header after changing it.
- `conformance/` holds the native VT/ANSI conformance suite. These bindings call
  the same parser, so those cases describe this module's behavior too.

## License

MIT, matching Ghostty and this fork. See `../LICENSE`.
