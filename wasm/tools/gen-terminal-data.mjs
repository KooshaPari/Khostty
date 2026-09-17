#!/usr/bin/env node
// Generate wasm/js/terminal-data.js from include/ghostty/vt/terminal.h.
//
// ghostty_terminal_get() writes a caller-allocated out parameter whose type
// depends on the GhosttyTerminalData key. That mapping exists only in the
// header's documentation, so the bindings need a table. Hand-writing it would
// reintroduce exactly the drift the rest of the bindings avoid, so it is
// derived from the header: each key's doc comment states its output type as
// "Output type: <C type> *", and this script normalizes that to the type name
// the library's own manifest (ghostty_type_json) uses.
//
// Regenerate: node wasm/tools/gen-terminal-data.mjs
// The ABI test asserts the generated table covers every key the manifest
// declares, and that every referenced type name resolves.

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, "..", "..");
const headerPath = join(repoRoot, "include", "ghostty", "vt", "terminal.h");
const outPath = join(repoRoot, "wasm", "js", "terminal-data.js");

/** C scalar types mapped to their manifest names. */
const SCALARS = {
  uint8_t: "u8",
  int8_t: "i8",
  uint16_t: "u16",
  int16_t: "i16",
  uint32_t: "u32",
  int32_t: "i32",
  uint64_t: "u64",
  int64_t: "i64",
  size_t: "usize",
  bool: "bool",
};

/**
 * Keys whose out parameter cannot be produced by a zeroed allocation, so the
 * generic read path must refuse them instead of reading garbage.
 *
 * GHOSTTY_TERMINAL_DATA_MODE reads and writes a GhosttyTerminalModeConfig that
 * the caller must initialize (which mode, and which screen) before the call,
 * so there is no sensible default.
 */
const REQUIRES_INPUT = new Set(["MODE"]);

function parse() {
  const text = readFileSync(headerPath, "utf8");
  const table = new Map();
  let pendingOutputType = null;
  let inDataEnum = false;

  for (const line of text.split("\n")) {
    if (/^\s*\}\s*GhosttyTerminalData\s*;/.test(line)) inDataEnum = false;

    const outputType = line.match(/Output type:\s*(.+?)\s*$/);
    if (outputType) {
      pendingOutputType = outputType[1];
      continue;
    }

    const member = line.match(/^\s*(GHOSTTY_TERMINAL_DATA_\w+)\s*=\s*(\d+)\s*,/);
    if (!member) continue;
    const [, symbol, rawValue] = member;
    const name = symbol.replace("GHOSTTY_TERMINAL_DATA_", "");
    if (name === "MAX_VALUE") continue;
    if (name === "INVALID") {
      inDataEnum = true;
      pendingOutputType = null;
      continue;
    }
    // Only the GhosttyTerminalData enum uses the "Output type:" convention;
    // requiring the enum body guards against a stray match elsewhere.
    if (!inDataEnum) continue;

    table.set(name, { value: Number(rawValue), outputType: pendingOutputType });
    pendingOutputType = null;
  }
  return table;
}

/** Turn a raw C "Output type" string into a binding descriptor. */
function normalize(name, raw) {
  if (REQUIRES_INPUT.has(name)) {
    return { kind: "input-required", note: "requires a caller-initialized config" };
  }
  if (!raw) {
    throw new Error(`no documented output type for GHOSTTY_TERMINAL_DATA_${name}`);
  }

  // "GhosttyColorRgb[256] *" -> array of 256
  const array = raw.match(/^(.+?)\[(\d+)\]\s*\*$/);
  if (array) {
    return { kind: "array", type: array[1].trim(), count: Number(array[2]) };
  }

  // "GhosttyKittyKeyFlags * (uint8_t *)" -> use the parenthesized concrete type
  const parenthesized = raw.match(/^(.+?)\s*\*?\s*\((\w[\w\s]*?)\s*\*\)$/);
  if (parenthesized) {
    const concrete = parenthesized[2].trim();
    if (SCALARS[concrete]) return { kind: "scalar", type: SCALARS[concrete] };
    return { kind: "named", type: parenthesized[1].trim() };
  }

  const plain = raw.match(/^(.+?)\s*\*$/);
  if (!plain) throw new Error(`unrecognized output type for ${name}: ${raw}`);
  const base = plain[1].trim();

  if (SCALARS[base]) return { kind: "scalar", type: SCALARS[base] };
  return { kind: "named", type: base };
}

function render(table) {
  const rows = [];
  for (const [name, { value, outputType }] of table) {
    const desc = normalize(name, outputType);
    const comment = outputType ? `  // ${outputType}` : "";
    let literal;
    switch (desc.kind) {
      case "scalar":
      case "named":
        literal = `Object.freeze({ value: ${value}, kind: "${desc.kind}", type: "${desc.type}" })`;
        break;
      case "array":
        literal = `Object.freeze({ value: ${value}, kind: "array", type: "${desc.type}", count: ${desc.count} })`;
        break;
      case "input-required":
        literal = `Object.freeze({ value: ${value}, kind: "input-required", note: "${desc.note}" })`;
        break;
      default:
        throw new Error(`unhandled kind ${desc.kind}`);
    }
    rows.push(`  ${name}: ${literal},${comment}`);
  }

  return `// Generated from include/ghostty/vt/terminal.h by
// wasm/tools/gen-terminal-data.mjs -- do not edit by hand.
//
// Maps each readable GhosttyTerminalData key to the out-parameter type that
// ghostty_terminal_get() writes, normalized to the type names used by the
// library's own ABI manifest. "value" is the enum value, which is what the
// bindings pass to the exported function.
//
// Regenerate: node wasm/tools/gen-terminal-data.mjs

/** GhosttyTerminalData member -> out parameter descriptor. */
export const TERMINAL_DATA = Object.freeze({
${rows.join("\n")}
});
`;
}

const table = parse();
if (table.size === 0) {
  throw new Error("extracted no GhosttyTerminalData members; the parser is not working");
}
writeFileSync(outPath, render(table));
console.log(
  `wrote ${relative(repoRoot, outPath)}: ${table.size} GhosttyTerminalData keys`,
);
