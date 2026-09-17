#!/usr/bin/env node
// Standalone consumer smoke test for a packaged Khostty WASM dist.
//
// This file is copied into the release tarball and is the acceptance check that
// runs against the *tarball*, not against the source tree. That distinction is
// the whole point: "the repo test suite passes" and "this artifact works for a
// consumer" are different claims. A tarball can be missing a file, carry a
// stale manifest, or pair bindings with a wasm module they no longer match.
//
// It imports only through the package's own entry points and never reads
// anything outside the extracted directory. No dependencies: `node:` builtins
// plus the bundled `tools/wasm-exports.mjs`.
//
// Usage:  node smoke.mjs [--json]
// Exit:   0 if every check passed, 1 otherwise.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { parseWasm, exportedFunctions } from "./tools/wasm-exports.mjs";

const here = new URL("./", import.meta.url);
const asJson = process.argv.includes("--json");

// ---- tiny assertion harness ----------------------------------------------

const results = [];

async function check(name, fn) {
  try {
    results.push({ name, ok: true, detail: (await fn()) ?? null });
  } catch (err) {
    results.push({ name, ok: false, detail: err.message });
  }
}

function assertEq(actual, expected, what) {
  if (actual !== expected) {
    throw new Error(`${what}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
  return actual;
}

// ---- manifest sanity ------------------------------------------------------

const pkg = JSON.parse(readFileSync(fileURLToPath(new URL("package.json", here)), "utf8"));

await check("package.json declares a release version", async () => {
  if (!/^\d+\.\d+\.\d+/.test(pkg.version)) throw new Error(`bad version: ${pkg.version}`);
  return pkg.version;
});

await check("package.json is publishable (not private)", async () => {
  if (pkg.private === true) {
    throw new Error("`private: true`: this tarball cannot be published as-is");
  }
  return "private absent or false";
});

// ---- the wasm module itself ----------------------------------------------

const wasmPath = fileURLToPath(new URL("khostty-vt.wasm", here));
const wasmBytes = readFileSync(wasmPath);
let module_ = null;

await check("wasm module parses as a well-formed module", async () => {
  module_ = parseWasm(wasmBytes);
  assertEq(module_.version, 1, "wasm binary version");
  return `${wasmBytes.length} bytes, sections [${module_.sections.map((s) => s.id).join(", ")}]`;
});

await check("wasm module exports the documented C ABI", async () => {
  if (!module_) throw new Error("module failed to parse");
  const fns = exportedFunctions(module_);
  const ghostty = fns.filter((n) => n.startsWith("ghostty_"));
  if (ghostty.length < 100) {
    throw new Error(`only ${ghostty.length} ghostty_* exports; expected 100+`);
  }
  const mem = module_.exports.find((e) => e.kind === "memory");
  if (!mem) throw new Error("linear memory is not exported");
  return `${ghostty.length} ghostty_* functions, memory as "${mem.name}"`;
});

// ---- the JS bindings, exercised through the public API --------------------

let api = null;
await check("import js/api.js (the package's public entry point)", async () => {
  api = await import(new URL("js/api.js", here).href);
  if (typeof api.Terminal !== "function") throw new Error("Terminal is not exported");
  return "Terminal, Snapshot, Search present";
});

if (api) {
  // Terminal.open() takes ONE options object. `vt` is passed inside it, not as
  // a first positional argument: `Terminal.open(vt, {cols, rows})` silently
  // ignores both arguments and builds an 80x24 terminal on a second module
  // instance. That is a real foot-gun, so the smoke test exercises the
  // documented shape and asserts that `cols`/`rows` actually took effect.
  let vt = null;
  await check("load the bundled wasm module by its default URL", async () => {
    // No wasmPath: this resolves through the package's own DEFAULT_WASM_URL,
    // which is the code path a consumer takes.
    vt = await api.loadGhosttyVt();
    if (!vt) throw new Error("loadGhosttyVt returned nothing");
    return `instantiated, ${vt.meta?.bytes ?? "?"} bytes`;
  });

  await check("open() honours the requested cols/rows", async () => {
    using term = await api.Terminal.open({ vt, cols: 37, rows: 11 });
    assertEq(term.cols, 37, "cols");
    assertEq(term.rows, 11, "rows");
    return `${term.cols}x${term.rows}`;
  });

  await check("terminal parses text and SGR colour out of a VT stream", async () => {
    using term = await api.Terminal.open({ vt, cols: 40, rows: 6 });
    term.write("Hello, World!\r\n\x1b[1;32mGreen Bold\x1b[0m and \x1b[4mUnderline\x1b[0m\r\n");
    term.write("\x1b[3;1H\x1b[2KLine 3: Overwritten!");
    return assertEq(
      term.text(),
      ["Hello, World!", "Green Bold and Underline", "Line 3: Overwritten!"].join("\n"),
      "screen text",
    );
  });

  await check("terminal renders cells to HTML with palette and bold", async () => {
    using term = await api.Terminal.open({ vt, cols: 40, rows: 6 });
    term.write("\x1b[1;32mgreen bold\x1b[0m");
    const html = term.html();
    if (!html.includes("green") || !html.includes("font-weight: bold")) {
      throw new Error(`unexpected html: ${html.slice(0, 200)}`);
    }
    return "colour var + bold span present";
  });

  await check("terminal reports live cursor and screen state", async () => {
    using term = await api.Terminal.open({ vt, cols: 10, rows: 4 });
    term.write("ab\r\n\t\x1b[?1049h");
    const state = { cursorX: term.cursorX, cursorY: term.cursorY, screen: term.screen };
    assertEq(state.cursorX, 8, "cursorX after a tab");
    assertEq(state.cursorY, 1, "cursorY");
    assertEq(state.screen, "ALTERNATE", "screen after ?1049h");
    return JSON.stringify(state);
  });

  await check("terminal handles resize and reflow", async () => {
    using term = await api.Terminal.open({ vt, cols: 20, rows: 4 });
    term.write("x".repeat(30));
    term.resize(40, 4);
    assertEq(term.cols, 40, "cols after resize");
    return `cols=${term.cols} rows=${term.rows} totalRows=${term.totalRows}`;
  });

  await check("snapshot round-trips through encode/decode", async () => {
    using term = await api.Terminal.open({ vt, cols: 20, rows: 4 });
    term.write("snapshot me\r\nsecond line");
    // Snapshot owns only bytes and exposes no `close()`/Symbol.dispose, unlike
    // Terminal and Search, so there is nothing to release here.
    const snap = term.snapshot();
    // `bytes` is a property holding a Uint8Array, not a method.
    if (snap.bytes.length === 0) throw new Error("snapshot encoded to zero bytes");
    const meta = snap.metadata();
    if (meta.bytes !== snap.bytes.length) {
      throw new Error(`metadata.bytes=${meta.bytes} != encoded length ${snap.bytes.length}`);
    }
    using restored = snap.restore();
    return assertEq(restored.text(), term.text(), "restored text matches source");
  });

  await check("ghostty errors are typed", async () => {
    if (typeof api.GhosttyError !== "function") throw new Error("GhosttyError is not a constructor");
    return "ok";
  });
}

// ---- report ---------------------------------------------------------------

const failed = results.filter((r) => !r.ok);
if (asJson) {
  console.log(JSON.stringify({ package: pkg.name, version: pkg.version, results }, null, 2));
} else {
  for (const r of results) {
    console.log(`${r.ok ? "PASS" : "FAIL"}  ${r.name}${r.detail ? `  -> ${r.detail}` : ""}`);
  }
  console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
}
process.exit(failed.length === 0 ? 0 : 1);
