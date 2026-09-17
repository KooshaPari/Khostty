// C ABI export verification.
//
// Answers, from the artifact itself rather than from the build's exit code:
//
//   1. Which functions does the wasm module actually export?
//   2. Does that set match the public API declared in the consolidated header?
//   3. Are the changes to that set exactly the ones we have documented a reason
//      for, so a silent regression cannot pass?
//   4. Do the binding data tables agree with the library's own manifest?
//
// The module is parsed directly (tools/wasm-exports.mjs) so this needs no wabt
// or binaryen install.
//
// Run: node --test wasm/test/   (from the wasm/ directory: npm test)

import { test, describe, before } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { parseWasm, exportedFunctions } from "../tools/wasm-exports.mjs";
import { loadGhosttyVt } from "../js/index.js";
import { TERMINAL_DATA } from "../js/terminal-data.js";
import { SEARCH_DATA } from "../js/search.js";

const WASM = fileURLToPath(new URL("../khostty-vt.wasm", import.meta.url));
const HEADER = fileURLToPath(new URL("../include/ghostty-vt.h", import.meta.url));

/**
 * Declarations the consolidated header exposes that the wasm32 build does not
 * export, with the reason. Every entry must be justified: an unexplained
 * absence is a bug, and a new absence fails the equality check below.
 */
const EXPECTED_ABSENT = new Map([
  // Active directory (kitty graphics): requires OS timestamps, so
  // src/terminal/build_options.zig disables it on freestanding targets for any
  // value of the kitty_graphics feature, which removes these 16 exports.
  ...[
    "ghostty_kitty_graphics_get",
    "ghostty_kitty_graphics_image",
    "ghostty_kitty_graphics_image_get",
    "ghostty_kitty_graphics_image_get_multi",
    "ghostty_kitty_graphics_placement_get",
    "ghostty_kitty_graphics_placement_get_multi",
    "ghostty_kitty_graphics_placement_grid_size",
    "ghostty_kitty_graphics_placement_iterator_free",
    "ghostty_kitty_graphics_placement_iterator_new",
    "ghostty_kitty_graphics_placement_iterator_set",
    "ghostty_kitty_graphics_placement_next",
    "ghostty_kitty_graphics_placement_pixel_size",
    "ghostty_kitty_graphics_placement_rect",
    "ghostty_kitty_graphics_placement_render_info",
    "ghostty_kitty_graphics_placement_source_rect",
    "ghostty_kitty_graphics_placement_viewport_pos",
  ].map((name) => [name, "kitty graphics disabled on freestanding targets"]),
]);

/** Function names the consolidated header declares with GHOSTTY_API. */
function declaredFunctions() {
  const text = readFileSync(HEADER, "utf8");
  const pattern = /GHOSTTY_API\b[^;{}#]*?\b(ghostty_[A-Za-z0-9_]+)\s*\(/gs;
  return new Set([...text.matchAll(pattern)].map((m) => m[1]));
}

let mod;
let exports;
let vt;
let layout;

before(async () => {
  assert.ok(existsSync(WASM), `missing ${WASM}; build it with: wasm/build.sh`);
  mod = parseWasm(readFileSync(WASM));
  exports = exportedFunctions(mod);
  vt = await loadGhosttyVt({ wasmPath: WASM });
  layout = vt.layout;
});

describe("wasm module shape", () => {
  test("is a well-formed version 1 module", () => {
    assert.equal(mod.version, 1);
    assert.ok(mod.sections.length > 0);
  });

  test("imports nothing", () => {
    // The module is freestanding. If a future build starts importing, the
    // loader's import-object derivation must be updated deliberately.
    assert.deepEqual(mod.imports, []);
  });

  test("exports linear memory as \"memory\"", () => {
    const memory = mod.exports.find((e) => e.kind === "memory");
    assert.ok(memory, "no memory export");
    assert.equal(memory.name, "memory");
  });
});

describe("exported functions", () => {
  test("every exported function is part of the ghostty_* C ABI", () => {
    const stray = exports.filter((name) => !name.startsWith("ghostty_"));
    assert.deepEqual(stray, [], `non-ABI exports leaked: ${stray.join(", ")}`);
  });

  test("exports a non-trivial ABI surface", () => {
    assert.ok(
      exports.length >= 150,
      `only ${exports.length} function exports; expected the full libghostty-vt ABI`,
    );
    for (const required of [
      "ghostty_terminal_new",
      "ghostty_terminal_free",
      "ghostty_terminal_vt_write",
      "ghostty_terminal_get",
      "ghostty_terminal_resize",
      "ghostty_formatter_terminal_new",
      "ghostty_formatter_format_alloc",
      "ghostty_snapshot_encode_alloc",
      "ghostty_search_new",
      "ghostty_search_run",
      "ghostty_type_json",
      "ghostty_wasm_alloc",
      "ghostty_wasm_free",
      "ghostty_wasm_alloc_opaque",
      "ghostty_wasm_take_opaque",
      "ghostty_free",
    ]) {
      assert.ok(exports.includes(required), `${required} is not exported`);
    }
  });

  test("the wasm-only helpers in wasm.h are all exported", () => {
    // include/ghostty/vt/wasm.h gates these on __wasm__; they are the reason
    // the wasm build exists as a distinct artifact.
    for (const name of [
      "ghostty_wasm_alloc",
      "ghostty_wasm_free",
      "ghostty_wasm_alloc_opaque",
      "ghostty_wasm_free_opaque",
      "ghostty_wasm_take_opaque",
    ]) {
      assert.ok(exports.includes(name), `${name} from wasm.h is not exported`);
    }
  });

  test("exports exactly the declared API minus documented exceptions", () => {
    const declared = declaredFunctions();
    assert.ok(declared.size > 0, "parsed no declarations from the header");

    const exportedSet = new Set(exports);
    const missing = [...declared].filter((n) => !exportedSet.has(n)).sort();
    const expected = [...EXPECTED_ABSENT.keys()].sort();

    assert.deepEqual(
      missing,
      expected,
      "the set of unexported declarations changed; each entry needs a " +
        "documented reason in EXPECTED_ABSENT",
    );

    const extra = exports.filter((n) => !declared.has(n));
    assert.deepEqual(
      extra,
      [],
      "the module exports functions the consolidated header does not declare",
    );
  });

  test("each documented absence names a real declaration", () => {
    const declared = declaredFunctions();
    for (const [name, reason] of EXPECTED_ABSENT) {
      assert.ok(declared.has(name), `${name} is not declared in the header`);
      assert.ok(reason.length > 0, `${name} has no recorded reason`);
    }
  });

  test("kitty graphics is the only documented absence", () => {
    for (const [name, reason] of EXPECTED_ABSENT) {
      assert.match(name, /^ghostty_kitty_graphics_/, `${name}: unexpected absence`);
      assert.match(reason, /freestanding/, `${name}: reason should cite freestanding`);
    }
  });
});

describe("manifest and binding tables", () => {
  // Every check below reads the library's own manifest through a loaded
  // module, so they all share one instantiation.
  test("describes a little-endian wasm32 target", () => {
    assert.equal(layout.abi.target, "wasm32");
    assert.equal(layout.abi.endian, "little");
    assert.equal(layout.abi.usize_size, 4);
  });

  test("has a plausible number of public types", () => {
    assert.ok(Object.keys(layout.types).length >= 100);
  });

  test("sized option structs carry a matching size field", () => {
    // The bindings rely on Abi.initSized() filling these in, so a struct that
    // gains a `size` field of an unexpected type must be noticed.
    for (const name of [
      "GhosttyFormatterTerminalOptions",
      "GhosttyFormatterTerminalExtra",
      "GhosttyFormatterScreenExtra",
    ]) {
      assert.ok(layout.isSizedStruct(name), `${name} is not a sized struct`);
      const field = layout.field(name, "size");
      assert.ok(
        field.type === "u32" || field.type === "u64",
        `${name}.size has unexpected type ${field.type}`,
      );
      assert.ok(
        layout.sizeOf(name) >= field.offset + field.size,
        `${name}: size field overruns the struct`,
      );
    }
  });

  test("struct field offsets stay inside their struct", () => {
    for (const [name, type] of Object.entries(layout.types)) {
      if (!type.fields || typeof type.size !== "number") continue;
      for (const [fieldName, field] of Object.entries(type.fields)) {
        assert.ok(
          field.offset + field.size <= type.size,
          `${name}.${fieldName} runs past the end of ${name} (${type.size} bytes)`,
        );
      }
    }
  });

  test("TERMINAL_DATA covers every GhosttyTerminalData member", () => {
    const members = layout.enumMembers("GhosttyTerminalData");
    for (const [name, value] of Object.entries(members)) {
      if (name === "INVALID" || name === "MAX_VALUE") continue;
      const entry = TERMINAL_DATA[name];
      assert.ok(entry, `TERMINAL_DATA is missing ${name}`);
      assert.equal(entry.value, value, `TERMINAL_DATA.${name} has the wrong value`);
    }
  });

  test("TERMINAL_DATA declares nothing the library does not", () => {
    const members = layout.enumMembers("GhosttyTerminalData");
    for (const name of Object.keys(TERMINAL_DATA)) {
      assert.ok(
        Object.hasOwn(members, name),
        `TERMINAL_DATA.${name} does not exist in the manifest`,
      );
    }
  });

  test("every TERMINAL_DATA type resolves, and array keys are not misread", () => {
    for (const [name, entry] of Object.entries(TERMINAL_DATA)) {
      if (entry.kind === "named") {
        assert.ok(
          layout.has(entry.type),
          `TERMINAL_DATA.${name} references unknown type ${entry.type}`,
        );
      }
      if (entry.kind === "array") {
        assert.ok(Number.isInteger(entry.count) && entry.count > 0, `${name}: bad count`);
        assert.ok(layout.has(entry.type), `${name}: unknown element type ${entry.type}`);
        // Fixed-size arrays must not be silently readable as a scalar: the
        // binding refuses them instead of reading the first element.
        assert.throws(
          () => vt.terminalGet(1, name),
          /array/,
          `${name} should be refused by the scalar path`,
        );
      }
      if (entry.kind === "input-required") {
        assert.throws(
          () => vt.terminalGet(1, name),
          /input-required|requires a caller-initialized/,
          `${name} should be refused by the scalar path`,
        );
      }
    }
  });

  test("SEARCH_DATA covers every GhosttySearchData member", () => {
    const members = layout.enumMembers("GhosttySearchData");
    for (const [name, value] of Object.entries(members)) {
      if (name === "INVALID" || name === "MAX_VALUE") continue;
      const entry = SEARCH_DATA[name];
      assert.ok(entry, `SEARCH_DATA is missing ${name}`);
      assert.equal(entry.value, value, `SEARCH_DATA.${name} has the wrong value`);
    }
  });

  test("SEARCH_DATA declares nothing the library does not", () => {
    const members = layout.enumMembers("GhosttySearchData");
    for (const name of Object.keys(SEARCH_DATA)) {
      assert.ok(
        Object.hasOwn(members, name),
        `SEARCH_DATA.${name} does not exist in the manifest`,
      );
    }
  });

  test("every SEARCH_DATA type resolves, and kind matches", () => {
    const scalars = new Set(["usize", "u8", "u16", "u32", "u64", "bool", "pointer"]);
    for (const [name, entry] of Object.entries(SEARCH_DATA)) {
      assert.ok(
        scalars.has(entry.type) || layout.has(entry.type),
        `SEARCH_DATA.${name} references unknown type ${entry.type}`,
      );
    }
    // Guards against a typo that names an existing but wrong type.
    assert.equal(layout.type("GhosttyString").kind, "struct");
    assert.equal(layout.type("GhosttySelectionBuffer").kind, "struct");
    assert.equal(layout.type("GhosttySearchStatus").kind, "enum");
    assert.equal(layout.type("GhosttyTerminalScreen").kind, "enum");
    assert.equal(layout.type("GhosttyColorRgb").kind, "struct");
  });
});
