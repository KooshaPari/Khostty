// Smoke test: parse VT into a terminal and read the screen back.
//
// Uses node:test and node:assert only. There is no jsdom or vitest dependency
// because nothing here touches the DOM: the wasm module is freestanding and the
// bindings are plain ESM, so plain Node exercises the same code path a browser
// would.
//
// Run: node --test wasm/test/   (from the wasm/ directory: npm test)
//
// If wasm/khostty-vt.wasm is missing this test fails with the build command
// rather than skipping, because a skipped acceptance test is indistinguishable
// from a passing one in CI output.

import { test, describe, before } from "node:test";
import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { Terminal, Snapshot, Search } from "../js/api.js";
import { loadGhosttyVt, GhosttyError } from "../js/index.js";

const WASM = fileURLToPath(new URL("../khostty-vt.wasm", import.meta.url));

/** A VT stream exercising text, SGR color, cursor moves, and erase. */
const SAMPLE =
  "Hello, World!\r\n" +
  "\x1b[1;32mGreen Bold\x1b[0m and \x1b[4mUnderline\x1b[0m\r\n" +
  "Line 3: placeholder\r\n" +
  "\x1b[3;1H\x1b[2KLine 3: Overwritten!";

const EXPECTED_TEXT = [
  "Hello, World!",
  "Green Bold and Underline",
  "Line 3: Overwritten!",
].join("\n");

let vt;

before(async () => {
  assert.ok(
    existsSync(WASM),
    `missing ${WASM}; build it with: wasm/build.sh`,
  );
  vt = await loadGhosttyVt({ wasmPath: WASM });
});

describe("module", () => {
  test("reports a wasm32 freestanding ABI", () => {
    assert.equal(vt.meta.abi.target, "wasm32");
    assert.equal(vt.meta.abi.os, "freestanding");
    assert.equal(vt.meta.abi.pointer_size, 4);
    assert.equal(vt.meta.abi.usize_size, 4);
    assert.equal(vt.meta.abi.endian, "little");
  });

  test("has no imports and exports memory", () => {
    // env.log exists only as a shim; the module must not actually import it.
    assert.ok(vt.exports.memory);
    assert.equal(typeof vt.exports.ghostty_terminal_new, "function");
  });

  test("publishes a type manifest with the public types", () => {
    for (const name of [
      "GhosttyTerminal",
      "GhosttyFormatterTerminalOptions",
      "GhosttyString",
      "GhosttyResult",
    ]) {
      assert.ok(vt.layout.has(name), `manifest is missing ${name}`);
    }
    assert.equal(vt.layout.enumValue("GhosttyResult", "SUCCESS"), 0);
  });
});

describe("parse VT and read the screen", () => {
  test("formats written VT as plain text", async () => {
    await using term = await Terminal.open({ vt, cols: 40, rows: 6 });
    term.write(SAMPLE);
    assert.equal(term.text(), EXPECTED_TEXT);
  });

  test("accepts raw bytes as well as strings", async () => {
    await using term = await Terminal.open({ vt, cols: 20, rows: 3 });
    term.write(new TextEncoder().encode("bytes path\r\nok"));
    assert.equal(term.text(), "bytes path\nok");
  });

  test("reports terminal geometry and cursor", async () => {
    await using term = await Terminal.open({ vt, cols: 40, rows: 6 });
    assert.equal(term.cols, 40);
    assert.equal(term.rows, 6);
    term.write(SAMPLE);
    // "\x1b[3;1H" moves to row 2 (0-based); the erase and text leave the
    // cursor after the final "!" on that row.
    assert.equal(term.cursorY, 2);
    assert.equal(term.cursorX, 20);
    assert.equal(term.totalRows, 6);
    assert.equal(term.scrollbackRows, 0);
  });

  test("reports the active screen and cursor visibility", async () => {
    await using term = await Terminal.open({ vt, cols: 20, rows: 4 });
    assert.equal(term.screen, "PRIMARY");
    assert.equal(term.cursorVisible, true);
  });

  test("unwrappedText joins soft-wrapped lines", async () => {
    await using term = await Terminal.open({ vt, cols: 10, rows: 4 });
    term.write("0123456789ABCDEFGHIJ");
    // Wrapped at column 10, so the wrapped form has a newline and the
    // unwrapped form does not.
    assert.equal(term.text(), "0123456789\nABCDEFGHIJ");
    assert.equal(term.unwrappedText(), "0123456789ABCDEFGHIJ");
  });

  test("reads the terminal title set by OSC 2", async () => {
    await using term = await Terminal.open({ vt, cols: 20, rows: 3 });
    term.write("\x1b]2;my title\x07hello");
    assert.equal(term.title, "my title");
  });

  test("empty title reads as an empty string, not undefined", async () => {
    await using term = await Terminal.open({ vt, cols: 20, rows: 3 });
    assert.equal(term.title, "");
  });

  test("reset clears written content", async () => {
    await using term = await Terminal.open({ vt, cols: 20, rows: 3 });
    term.write("gone");
    term.reset();
    assert.equal(term.text(), "");
  });

  test("resize reflows and updates geometry", async () => {
    await using term = await Terminal.open({ vt, cols: 20, rows: 3 });
    term.write("trace me");
    term.resize(40, 5);
    assert.equal(term.cols, 40);
    assert.equal(term.rows, 5);
    assert.equal(term.text(), "trace me");
  });
});

describe("rendering modes", () => {
  test("HTML output carries the color and style", async () => {
    await using term = await Terminal.open({ vt, cols: 40, rows: 3 });
    term.write("\x1b[1;32mgreen\x1b[0m plain");
    const html = term.html();
    assert.match(html, /green/);
    assert.match(html, /font-weight: bold/);
    assert.match(html, /plain/);
  });

  test("VT output re-emits escape sequences", async () => {
    await using term = await Terminal.open({ vt, cols: 40, rows: 3 });
    term.write("\x1b[1;31mred\x1b[0m");
    assert.match(term.vtText(), /\x1b\[/);
  });

  test("trim controls trailing whitespace", async () => {
    await using term = await Terminal.open({ vt, cols: 12, rows: 2 });
    // trim only removes whitespace that is part of the written content; a row
    // whose content stops at column 2 has nothing to trim either way.
    term.write("hi    ");
    assert.equal(term.text(), "hi");
    assert.equal(term.text({ trim: false }), "hi    ");
  });
});

describe("snapshot", () => {
  test("round-trips terminal state", async () => {
    await using term = await Terminal.open({ vt, cols: 40, rows: 6 });
    term.write(SAMPLE);
    const snap = term.snapshot();
    assert.ok(snap instanceof Snapshot);
    assert.ok(snap.byteLength > 0);

    using restored = snap.restore();
    assert.equal(restored.text(), term.text());
    assert.equal(restored.cols, term.cols);
    assert.equal(restored.rows, term.rows);
  });

  test("metadata decodes without restoring", async () => {
    await using term = await Terminal.open({ vt, cols: 40, rows: 6 });
    term.write(SAMPLE);
    const meta = term.snapshot().metadata();
    assert.equal(meta.bytes, term.snapshot().byteLength);
    assert.equal(meta.sourceOffset, 0);
  });

  test("restored terminal is independent of the original", async () => {
    await using term = await Terminal.open({ vt, cols: 20, rows: 3 });
    term.write("original");
    using restored = term.snapshot().restore();
    restored.write("\r\nchanged");
    assert.equal(term.text(), "original");
    assert.notEqual(restored.text(), term.text());
  });
});

describe("search", () => {
  test("finds every match on the screen", async () => {
    await using term = await Terminal.open({ vt, cols: 40, rows: 5 });
    term.write("alpha beta gamma\r\ndelta beta epsilon\r\nbeta again");
    using search = term.search("beta");
    search.run();
    assert.equal(search.status, "COMPLETE");
    assert.equal(search.totalMatches, 3);
    assert.equal(search.hasMatches, true);
  });

  test("nothing is selected until next or prev is called", async () => {
    await using term = await Terminal.open({ vt, cols: 40, rows: 5 });
    term.write("x marks the spot");
    using search = term.search("x");
    search.run();
    assert.equal(search.selectedIndex, undefined);
    search.next();
    assert.equal(search.selectedIndex, 0);
  });

  test("matching ASCII letters is case-insensitive", async () => {
    await using term = await Terminal.open({ vt, cols: 40, rows: 4 });
    term.write("Beta beta BETA");
    using search = term.search("bEtA");
    search.run();
    assert.equal(search.totalMatches, 3);
  });

  test("a needle with no matches yields zero, not an error", async () => {
    await using term = await Terminal.open({ vt, cols: 40, rows: 4 });
    term.write("nothing here");
    using search = term.search("absent");
    search.run();
    assert.equal(search.totalMatches, 0);
    assert.equal(search.hasMatches, false);
    assert.equal(search.selectedIndex, undefined);
  });

  test("needle reads back as text", async () => {
    await using term = await Terminal.open({ vt, cols: 40, rows: 3 });
    term.write("find me");
    using search = term.search("find me");
    search.run();
    assert.equal(search.needle, "find me");
  });

  test("search finds text in scrollback", async () => {
    await using term = await Terminal.open({ vt, cols: 20, rows: 3 });
    // 10 lines into a 3-row viewport pushes 7 rows into scrollback.
    term.write("needle-at-top\r\n" + Array.from({ length: 9 }, (_, i) => `l${i}`).join("\r\n"));
    assert.ok(term.scrollbackRows > 0, "expected scrollback to exist");
    using search = term.search("needle-at-top");
    search.run();
    assert.equal(search.totalMatches, 1);
  });

  test("closing a terminal closes its searches", async () => {
    const term = await Terminal.open({ vt, cols: 20, rows: 3 });
    const search = term.search("x");
    term.close();
    assert.equal(search.closed, true);
    // Second close must be a no-op rather than a double free.
    term.close();
    search.close();
  });
});

describe("lifetimes", () => {
  test("close is idempotent on a terminal", async () => {
    const term = await Terminal.open({ vt, cols: 20, rows: 3 });
    term.close();
    term.close();
    assert.equal(term.closed, true);
  });

  test("using a closed terminal throws instead of corrupting memory", async () => {
    const term = await Terminal.open({ vt, cols: 20, rows: 3 });
    term.close();
    assert.throws(() => term.write("x"), /closed/);
    assert.throws(() => term.text(), /closed/);
    assert.throws(() => term.handle, /closed/);
  });

  test("many terminals can be opened and closed without exhausting memory", async () => {
    for (let i = 0; i < 200; i++) {
      // Wide enough that the counter never soft-wraps.
      using term = await Terminal.open({ vt, cols: 20, rows: 2 });
      term.write(`n=${i}`);
      assert.equal(term.text(), `n=${i}`);
    }
  });

  test("reusing one module across terminals keeps state separate", async () => {
    using a = await Terminal.open({ vt, cols: 20, rows: 2 });
    using b = await Terminal.open({ vt, cols: 20, rows: 2 });
    a.write("aaa");
    b.write("bbb");
    assert.equal(a.text(), "aaa");
    assert.equal(b.text(), "bbb");
  });
});

describe("errors", () => {
  test("invalid geometry is rejected before reaching the library", () => {
    assert.throws(() => vt.terminalNew({ cols: 0, rows: 24 }), /invalid cols/);
    assert.throws(() => vt.terminalNew({ cols: 80, rows: -1 }), /invalid rows/);
  });

  test("unknown data keys are rejected", async () => {
    using term = await Terminal.open({ vt, cols: 20, rows: 2 });
    assert.throws(() => vt.terminalGet(term.handle, "NOPE"), /unknown terminal data key/);
  });

  test("GhosttyError carries a symbolic code name", () => {
    const error = new GhosttyError(-2, "test");
    assert.equal(error.code, -2);
    assert.equal(error.codeName, "INVALID_VALUE");
    assert.match(error.message, /INVALID_VALUE/);
  });
});

describe("high-level api entry point", () => {
  test("Search and Snapshot are constructible from api.js", () => {
    assert.equal(typeof Search, "function");
    assert.equal(typeof Snapshot, "function");
    assert.equal(typeof Terminal, "function");
  });
});
