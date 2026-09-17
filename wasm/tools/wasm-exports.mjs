#!/usr/bin/env node
// Inspect a WebAssembly module's import and export sections without pulling in
// wabt/binaryen. Used by wasm/test/abi-exports.test.mjs and available
// standalone for eyeballing an artifact:
//
//   node wasm/tools/wasm-exports.mjs wasm/khostty-vt.wasm            # summary
//   node wasm/tools/wasm-exports.mjs wasm/khostty-vt.wasm --json     # machine
//   node wasm/tools/wasm-exports.mjs wasm/khostty-vt.wasm --names    # one/line
//
// The parser is intentionally strict: any malformed length or section size is
// an error rather than a silent truncation, so it cannot report a clean module
// for a corrupt file.

import { readFileSync } from "node:fs";

const MAGIC = 0x6d736100; // "\0asm"
const VERSION = 1;

/** WASM section ids we care about. */
const SECTION_IMPORT = 2;
const SECTION_EXPORT = 7;

/** External kinds, per the core spec's `externkind`. */
export const KIND = {
  0: "function",
  1: "table",
  2: "memory",
  3: "global",
};

class Reader {
  #buf;
  #pos = 0;
  constructor(buf) {
    this.#buf = buf;
  }
  get pos() {
    return this.#pos;
  }
  get remaining() {
    return this.#buf.length - this.#pos;
  }
  eof() {
    return this.#pos >= this.#buf.length;
  }
  u8() {
    if (this.remaining < 1) throw new Error(`unexpected end of input at ${this.#pos}`);
    return this.#buf[this.#pos++];
  }
  bytes(n) {
    if (this.remaining < n) {
      throw new Error(`wanted ${n} bytes at ${this.#pos}, only ${this.remaining} left`);
    }
    const out = this.#buf.subarray(this.#pos, this.#pos + n);
    this.#pos += n;
    return out;
  }
  /** Unsigned LEB128. Guards against unbounded shift loops in corrupt files. */
  uleb() {
    let result = 0;
    let shift = 0;
    for (;;) {
      const byte = this.u8();
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) === 0) return result >>> 0;
      shift += 7;
      if (shift > 35) throw new Error(`LEB128 too long at ${this.#pos}`);
      // Keep the accumulator in the safe-integer range.
      if (shift > 28) {
        result = 0;
      }
    }
  }
  name() {
    const len = this.uleb();
    return new TextDecoder().decode(this.bytes(len));
  }
  /** A single `externkind` byte plus its type/limits payload. */
  externDesc() {
    const kind = this.u8();
    switch (kind) {
      case 0: // func: typeidx
        return { kind: KIND[0], typeIdx: this.uleb() };
      case 1: {
        // table: reftype, limits
        const refType = this.u8();
        const limits = this.limits();
        return { kind: KIND[1], refType, ...limits };
      }
      case 2: {
        // mem: limits
        return { kind: KIND[2], ...this.limits() };
      }
      case 3: {
        // global: valtype, mutability
        const valType = this.u8();
        const mutable = this.u8() === 1;
        return { kind: KIND[3], valType, mutable };
      }
      default:
        throw new Error(`unknown external kind ${kind} at ${this.#pos - 1}`);
    }
  }
  limits() {
    const flags = this.uleb();
    const min = this.uleb();
    const max = flags & 0x01 ? this.uleb() : null;
    return { min, max, shared: (flags & 0x02) !== 0, memory64: (flags & 0x04) !== 0 };
  }
}

/**
 * Parse a .wasm binary. Returns module header info, imports, exports, and the
 * section table. Throws on malformed input.
 */
export function parseWasm(bytes) {
  const reader = new Reader(bytes);
  const magic = reader.u8() | (reader.u8() << 8) | (reader.u8() << 16) | (reader.u8() << 24);
  if ((magic >>> 0) !== MAGIC) throw new Error("not a WebAssembly module (bad magic)");
  const version = reader.u8() | (reader.u8() << 8) | (reader.u8() << 16) | (reader.u8() << 24);
  if ((version >>> 0) !== VERSION) {
    throw new Error(`unsupported WebAssembly version ${version >>> 0}`);
  }

  const imports = [];
  const exports = [];
  const sections = [];

  while (!reader.eof()) {
    const id = reader.u8();
    const size = reader.uleb();
    const start = reader.pos;
    if (reader.remaining < size) {
      throw new Error(`section ${id} declares ${size} bytes but only ${reader.remaining} remain`);
    }
    const payload = new Reader(bytes.subarray(start, start + size));
    // Only the sections we actually decode can be checked for exact
    // consumption; anything else is skipped wholesale by design.
    let parsed = false;

    switch (id) {
      case SECTION_IMPORT: {
        const count = payload.uleb();
        for (let i = 0; i < count; i++) {
          const module = payload.name();
          const name = payload.name();
          imports.push({ module, name, ...payload.externDesc() });
        }
        parsed = true;
        break;
      }
      case SECTION_EXPORT: {
        const count = payload.uleb();
        for (let i = 0; i < count; i++) {
          const name = payload.name();
          const kind = payload.u8();
          const index = payload.uleb();
          if (!(kind in KIND)) throw new Error(`bad export kind ${kind} for ${name}`);
          exports.push({ name, kind: KIND[kind], index });
        }
        parsed = true;
        break;
      }
      default:
        break;
    }

    sections.push({ id, size, offset: start });
    if (parsed && payload.remaining !== 0) {
      throw new Error(`section ${id} has ${payload.remaining} trailing bytes`);
    }
    reader.bytes(size);
  }

  return { version: version >>> 0, imports, exports, sections };
}

/** Exported function names, sorted. */
export function exportedFunctions(mod) {
  return mod.exports.filter((e) => e.kind === "function").map((e) => e.name).sort();
}

function main(argv) {
  const [file, ...flags] = argv;
  if (!file) {
    console.error("usage: wasm-exports.mjs <module.wasm> [--json|--names|--check]");
    return 2;
  }
  const mod = parseWasm(readFileSync(file));

  if (flags.includes("--json")) {
    console.log(JSON.stringify(mod, null, 2));
    return 0;
  }
  if (flags.includes("--names")) {
    for (const name of exportedFunctions(mod)) console.log(name);
    return 0;
  }

  const fns = exportedFunctions(mod);
  const mem = mod.exports.find((e) => e.kind === "memory");
  console.log(`module:      ${file}`);
  console.log(`version:     ${mod.version}`);
  console.log(`sections:    ${mod.sections.map((s) => s.id).join(", ")}`);
  console.log(`imports:     ${mod.imports.length}`);
  for (const imp of mod.imports) {
    console.log(`  - ${imp.module}.${imp.name} (${imp.kind})`);
  }
  console.log(`exports:     ${mod.exports.length} (${fns.length} functions)`);
  console.log(`memory:      ${mem ? `exported as "${mem.name}"` : "not exported"}`);
  const nonApi = fns.filter((n) => !n.startsWith("ghostty_"));
  console.log(`ghostty_*:   ${fns.filter((n) => n.startsWith("ghostty_")).length}`);
  if (nonApi.length > 0) console.log(`non-ghostty: ${nonApi.join(", ")}`);
  return 0;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  process.exit(main(process.argv.slice(2)));
}
