// libghostty-vt — WebAssembly bindings (ESM loader + minimal bindings).
//
// This module loads the wasm32 build of libghostty-vt and exposes its C ABI as
// ergonomic functions. It is the layer between raw `exports.ghostty_*` integers
// and the object model in ./api.js (Terminal, Snapshot, Search).
//
//   import { loadGhosttyVt } from "./index.js";
//   const vt = await loadGhosttyVt();          // Node: reads wasm/khostty-vt.wasm
//   const term = vt.terminalNew({ cols: 80, rows: 24 });
//   vt.terminalVtWrite(term, "hello\r\n");
//   console.log(vt.format(term));
//   vt.terminalFree(term);
//
// Everything target-dependent (struct sizes, field offsets, enum values,
// out-parameter types) comes from the library's own manifest via
// ghostty_type_json(), never from hardcoded numbers. See ./layout.js.

// Node-only modules are imported lazily, inside resolveBytes. A static
// `import "node:fs"` would make this file unloadable in a browser or bundler
// that does not shim Node builtins, even though the browser path never touches
// the filesystem.
import { Abi } from "./abi.js";
import { check, GhosttyError, GHOSTTY_NO_VALUE } from "./errors.js";
import { TERMINAL_DATA } from "./terminal-data.js";

export { Abi } from "./abi.js";
export { Memory } from "./memory.js";
export { TypeLayout, TYPE_KIND } from "./layout.js";
export {
  check,
  GhosttyError,
  resultName,
  RESULT,
  GHOSTTY_SUCCESS,
  GHOSTTY_OUT_OF_MEMORY,
  GHOSTTY_INVALID_VALUE,
  GHOSTTY_OUT_OF_SPACE,
  GHOSTTY_NO_VALUE,
} from "./errors.js";
export { TERMINAL_DATA } from "./terminal-data.js";

/** Default module location: the artifact produced by wasm/build.sh. */
export const DEFAULT_WASM_URL = new URL("../khostty-vt.wasm", import.meta.url);

/** True when running under Node (as opposed to a browser or worker). */
function isNode() {
  return typeof process !== "undefined" && Boolean(process.versions?.node);
}

/**
 * Build a WebAssembly import object for a module.
 *
 * The import object's shape must match the module's declared imports exactly,
 * so it is derived from the module rather than hardcoded: a future build that
 * adds an import fails here with an actionable message instead of a LinkError.
 *
 * @param {WebAssembly.Module} module the compiled module
 * @param {Record<string, Record<string, Function>>} [overrides] user imports
 * @param {() => WebAssembly.Exports | null} getExports for the default log shim
 */
function buildImports(module, overrides = {}, getExports = () => null) {
  const imports = {};
  for (const { module: mod, name, kind } of WebAssembly.Module.imports(module)) {
    imports[mod] ??= {};
    if (overrides[mod]?.[name]) {
      imports[mod][name] = overrides[mod][name];
      continue;
    }
    if (mod === "env" && name === "log" && kind === "function") {
      // Debug logging channel. Decodes from live memory so it stays correct
      // across memory growth, and never throws into the module.
      imports[mod][name] = (ptr, len) => {
        const exports = getExports();
        if (!exports) return;
        try {
          const bytes = new Uint8Array(exports.memory.buffer, ptr, len);
          console.log("[libghostty-vt]", new TextDecoder().decode(bytes));
        } catch {
          /* logging must never break the caller */
        }
      };
      continue;
    }
    throw new Error(
      `unhandled wasm import ${mod}.${name} (${kind}); ` +
        `pass it via loadGhosttyVt({ imports: { ${mod}: { ${name} } } })`,
    );
  }
  return imports;
}

/** Read wasm bytes from whichever source the caller supplied. */
async function resolveBytes({ wasmBytes, wasmModule, wasmUrl, wasmPath }) {
  if (wasmBytes) return wasmBytes;
  if (wasmModule) return null; // already compiled
  if (wasmPath) {
    const read = await readFileInNode("wasmPath");
    return read(wasmPath);
  }
  const url = wasmUrl ?? DEFAULT_WASM_URL;
  if (isNode() && url.protocol === "file:") {
    const { fileURLToPath } = await import("node:url");
    const read = await readFileInNode("the default wasm artifact");
    return read(fileURLToPath(url));
  }
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`failed to fetch ${url}: ${response.status} ${response.statusText}`);
  }
  return new Uint8Array(await response.arrayBuffer());
}

/** Load node:fs lazily and return its readFileSync, with a clear failure. */
async function readFileInNode(what) {
  if (!isNode()) {
    throw new Error(`${what} requires Node; use wasmUrl or wasmBytes in browsers`);
  }
  try {
    const { readFileSync } = await import("node:fs");
    return readFileSync;
  } catch (cause) {
    throw new Error(`could not load node:fs needed to read ${what}`, { cause });
  }
}

/**
 * A loaded libghostty-vt wasm module.
 *
 * Wraps the instance's exports with the ABI layer and the minimal binding set.
 * All methods are synchronous: the module needs no async runtime once
 * instantiated.
 */
export class GhosttyVt {
  /**
   * @param {WebAssembly.Exports} exports
   * @param {{ bytes?: number, url?: string|URL }} [meta]
   */
  constructor(exports, meta = {}) {
    this.abi = new Abi(exports);
    this.meta = Object.freeze({
      bytes: meta.bytes ?? null,
      url: meta.url ? String(meta.url) : null,
      abi: Object.freeze({ ...this.abi.layout.abi }),
    });
  }

  /** Raw wasm exports, for anything the bindings do not cover yet. */
  get exports() {
    return this.abi.exports;
  }

  /** Growth-safe memory view. */
  get memory() {
    return this.abi.memory;
  }

  /** The library's type manifest. */
  get layout() {
    return this.abi.layout;
  }

  /** The type manifest as formatted JSON, for inspection. */
  get typeJson() {
    return JSON.stringify(this.layout, null, 2);
  }

  /** Numeric value of an enum member, e.g. enum("GhosttyResult","SUCCESS"). */
  enum(enumName, member) {
    return this.layout.enumValue(enumName, member);
  }

  // --- terminal lifecycle -------------------------------------------------

  /** Create a terminal. Returns an opaque handle. */
  terminalNew({ cols = 80, rows = 24, allocator = null } = {}) {
    if (!Number.isInteger(cols) || cols <= 0) throw new Error(`invalid cols: ${cols}`);
    if (!Number.isInteger(rows) || rows <= 0) throw new Error(`invalid rows: ${rows}`);
    return this.abi.opaqueNew(
      (slot) => this.abi.fn("ghostty_terminal_new")(allocator, slot, cols, rows),
      `ghostty_terminal_new(${cols}x${rows})`,
    );
  }

  /** Free a terminal handle. Safe with 0/undefined. */
  terminalFree(handle) {
    if (handle) this.abi.fn("ghostty_terminal_free")(handle);
  }

  /** Reset a terminal to its initial state, keeping its size. */
  terminalReset(handle) {
    this.abi.fn("ghostty_terminal_reset")(handle);
  }

  /** Resize a terminal. */
  terminalResize(handle, cols, rows) {
    check(
      this.abi.fn("ghostty_terminal_resize")(handle, cols, rows),
      `ghostty_terminal_resize(${cols}x${rows})`,
    );
  }

  /** Write VT-encoded bytes into a terminal. */
  terminalVtWrite(handle, data) {
    if (data.length === 0) return;
    const buffer = this.abi.writeBytes(data);
    try {
      this.abi.fn("ghostty_terminal_vt_write")(handle, buffer.ptr, buffer.len);
    } finally {
      this.abi.freeBytes(buffer);
    }
  }

  /**
   * Read one GhosttyTerminalData field.
   *
   * Returns a number, a boolean, a string (for GhosttyString out parameters),
   * or an object (for struct out parameters). Returns undefined when the field
   * has no value, i.e. GHOSTTY_NO_VALUE.
   *
   * @param {number} handle terminal handle
   * @param {string} key a member name from TERMINAL_DATA, e.g. "COLS"
   */
  terminalGet(handle, key) {
    const desc = TERMINAL_DATA[key];
    if (!desc) throw new Error(`unknown terminal data key: ${key}`);
    if (desc.kind === "input-required") {
      throw new Error(
        `GhosttyTerminalData.${key} ${desc.note}; use abi.writeStruct + ` +
          `ghostty_terminal_get directly`,
      );
    }
    if (desc.kind === "array") {
      throw new Error(
        `GhosttyTerminalData.${key} is a fixed-size array; allocate ` +
          `${desc.count} x ${desc.type} via abi and read it with abi.getField`,
      );
    }

    const call = (h, dataKey, out) => this.abi.fn("ghostty_terminal_get")(h, dataKey, out);
    let value;
    try {
      value = this.abi.readOut(handle, desc.value, desc.type, call, `terminal_get(${key})`);
    } catch (error) {
      if (error instanceof GhosttyError && error.code === GHOSTTY_NO_VALUE) return undefined;
      throw error;
    }

    // GhosttyString out parameters are structs holding a borrowed pointer.
    if (desc.type === "GhosttyString") {
      return this.memory.readString(value.ptr, value.len);
    }
    return value;
  }

  // --- formatting ---------------------------------------------------------

  /**
   * Create a formatter bound to a terminal's active screen.
   *
   * @param {number} terminal
   * @param {{emit?: string, unwrap?: boolean, trim?: boolean, extra?: object}} [options]
   *   `emit` is a GhosttyFormatterFormat member name: PLAIN, VT, or HTML.
   */
  formatterNew(terminal, { emit = "PLAIN", unwrap = false, trim = true, extra } = {}) {
    const options = this.abi.writeStruct("GhosttyFormatterTerminalOptions", {
      emit,
      unwrap,
      trim,
      ...(extra ? { extra } : {}),
    });
    try {
      return this.abi.opaqueNew(
        (slot) => this.abi.fn("ghostty_formatter_terminal_new")(null, slot, terminal, options),
        "ghostty_formatter_terminal_new",
      );
    } finally {
      this.abi.free(options, this.layout.sizeOf("GhosttyFormatterTerminalOptions"));
    }
  }

  /** Free a formatter handle. Safe with 0/undefined. */
  formatterFree(formatter) {
    if (formatter) this.abi.fn("ghostty_formatter_free")(formatter);
  }

  /** Format using a formatter handle. Returns a detached Uint8Array. */
  formatterFormat(formatter) {
    return this.#allocBytes(
      (outSlot, lenPtr) =>
        this.abi.fn("ghostty_formatter_format_alloc")(formatter, null, outSlot, lenPtr),
      "ghostty_formatter_format_alloc",
    );
  }

  /**
   * Format a terminal and return the bytes.
   *
   * Convenience over formatterNew + formatterFormat + formatterFree, which is
   * what almost every caller wants. The formatter is always freed.
   */
  formatTerminal(terminal, options) {
    const formatter = this.formatterNew(terminal, options);
    try {
      return this.formatterFormat(formatter);
    } finally {
      this.formatterFree(formatter);
    }
  }

  /** Format a terminal's active screen as text. */
  format(terminal, options = {}) {
    return new TextDecoder().decode(this.formatTerminal(terminal, options));
  }

  // --- snapshot -----------------------------------------------------------

  /**
   * Encode a terminal's state. Returns a detached Uint8Array.
   *
   * The terminal must be encodable: its VT parser and UTF-8 decoder must both
   * be at ground, or snapshot tracking must have been enabled before the input
   * that produced the current state. Otherwise the library returns
   * GHOSTTY_INVALID_VALUE.
   */
  snapshotEncode(terminal) {
    return this.#allocBytes(
      (outSlot, lenPtr) =>
        this.abi.fn("ghostty_snapshot_encode_alloc")(terminal, null, outSlot, lenPtr),
      "ghostty_snapshot_encode_alloc",
    );
  }

  // --- search -------------------------------------------------------------

  /**
   * Create a search bound to a terminal. Returns an opaque handle.
   *
   * Only handle lifecycle lives here; needle/status/match semantics are in
   * api.js's Search class, which is the layer that should own them.
   */
  searchNew(terminal) {
    return this.abi.opaqueNew(
      (slot) => this.abi.fn("ghostty_search_new")(null, slot, terminal),
      "ghostty_search_new",
    );
  }

  /** Free a search handle. Safe with 0/undefined. */
  searchFree(search) {
    if (search) this.abi.fn("ghostty_search_free")(search);
  }

  /**
   * Run a `*_alloc` method and return a detached copy of its buffer.
   *
   * Both `*_alloc` APIs follow the same shape: allocate an opaque slot for the
   * data pointer and a size_t for its length, call, check, take the pointer,
   * copy, then release the library buffer with ghostty_free. Copying strictly
   * before freeing is the point of centralizing this: the reverse order is a
   * use-after-free that reads plausible-looking garbage instead of crashing.
   *
   * @param {(outSlot: number, lenPtr: number) => number} call returns a result
   * @param {string} what used in error messages
   */
  #allocBytes(call, what) {
    const usizeSize = this.abi.usizeSize;
    const outSlot = this.abi.allocOpaque();
    const lenPtr = this.abi.alloc(usizeSize);
    try {
      check(call(outSlot, lenPtr), what);
      const ptr = this.abi.takeOpaque(outSlot);
      const len = this.memory.readUsize(lenPtr, usizeSize);
      const bytes = this.abi.takeAllocated(ptr, len);
      this.abi.freeAllocated(ptr, len);
      return bytes;
    } finally {
      this.abi.free(lenPtr, usizeSize);
      this.abi.freeOpaque(outSlot);
    }
  }
}

/**
 * Load and instantiate the libghostty-vt wasm module.
 *
 * Source precedence: wasmBytes, wasmModule, wasmPath (Node), wasmUrl, then the
 * default sibling artifact.
 *
 * @param {{
 *   wasmBytes?: BufferSource, wasmModule?: WebAssembly.Module,
 *   wasmPath?: string, wasmUrl?: string|URL,
 *   imports?: Record<string, Record<string, Function>>,
 * }} [options]
 * @returns {Promise<GhosttyVt>}
 */
export async function loadGhosttyVt(options = {}) {
  const { wasmModule, imports = {} } = options;
  const raw = await resolveBytes(options);

  let current = null;
  const module = wasmModule ?? (await WebAssembly.compile(raw));
  const instance = await WebAssembly.instantiate(
    module,
    buildImports(module, imports, () => current),
  );
  current = instance;

  return new GhosttyVt(instance.exports, {
    bytes: raw ? raw.byteLength : null,
    url: options.wasmUrl ?? (options.wasmPath ? null : DEFAULT_WASM_URL),
  });
}

export default loadGhosttyVt;
