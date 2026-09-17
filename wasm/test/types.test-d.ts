// Type-level test: exercises the declared API surface exactly as a TypeScript
// consumer would. This file is only typechecked, never executed
// (tsc --noEmit against wasm/tsconfig.json).
//
// Its purpose is to fail the build when the declarations stop covering the
// runtime API: a method that exists in js/ but not in the .d.ts is invisible to
// consumers and should be a compile error here rather than a runtime surprise.

import { Terminal, Snapshot, Search, openTerminal, GhosttyError } from "../js/api.js";
import { loadGhosttyVt, type GhosttyVt, type FormatOptions } from "../js/index.js";
import { Abi, type WasmBuffer } from "../js/abi.js";
import { TypeLayout } from "../js/layout.js";
import { Memory } from "../js/memory.js";
import { check, GHOSTTY_SUCCESS, type GhosttyResultCode } from "../js/errors.js";
import { TERMINAL_DATA } from "../js/terminal-data.js";
import { SEARCH_DATA } from "../js/search.js";

/** Helper that only accepts a value of the exact type; used to pin types. */
function expectType<T>(_value: T): void {}

export async function exerciseLoader(): Promise<void> {
  const vt: GhosttyVt = await loadGhosttyVt();
  const fromPath = await loadGhosttyVt({ wasmPath: "wasm/khostty-vt.wasm" });
  const fromUrl = await loadGhosttyVt({ wasmUrl: new URL("https://example.test/x.wasm") });
  const fromBytes = await loadGhosttyVt({ wasmBytes: new Uint8Array() });
  const withImports = await loadGhosttyVt({
    imports: { env: { log: (ptr: number, len: number) => void [ptr, len] } },
  });
  expectType<GhosttyVt[]>([vt, fromPath, fromUrl, fromBytes, withImports]);

  expectType<string>(vt.typeJson);
  expectType<Abi>(vt.abi);
  expectType<Memory>(vt.memory);
  expectType<TypeLayout>(vt.layout);
  expectType<WebAssembly.Exports>(vt.exports);
  expectType<number>(vt.meta.abi.usize_size);
  expectType<number | null>(vt.meta.bytes);
  expectType<string | number>(vt.enum("GhosttyResult", "SUCCESS"));

  // Terminal primitives
  const handle: number = vt.terminalNew({ cols: 80, rows: 24 });
  vt.terminalVtWrite(handle, "hello");
  vt.terminalVtWrite(handle, new Uint8Array([0x68, 0x69]));
  vt.terminalResize(handle, 100, 30);
  vt.terminalReset(handle);
  expectType<unknown>(vt.terminalGet(handle, "COLS"));

  // Formatting
  const opts: FormatOptions = { emit: "HTML", unwrap: true, trim: false };
  const bytes: Uint8Array = vt.formatTerminal(handle, opts);
  expectType<Uint8Array>(bytes);
  expectType<string>(vt.format(handle, { emit: "PLAIN" }));
  const formatter = vt.formatterNew(handle, { emit: "VT" });
  expectType<Uint8Array>(vt.formatterFormat(formatter));
  vt.formatterFree(formatter);

  // Snapshot + search handles
  expectType<Uint8Array>(vt.snapshotEncode(handle));
  const searchHandle = vt.searchNew(handle);
  vt.searchFree(searchHandle);
  vt.terminalFree(handle);
}

export async function exerciseObjectModel(): Promise<void> {
  const term: Terminal = await Terminal.open({ cols: 80, rows: 24 });
  const other: Terminal = await openTerminal({ wasmPath: "wasm/khostty-vt.wasm" });
  expectType<Terminal[]>([term, other]);

  // Chaining
  const chained: Terminal = term.write("x").resize(10, 5).reset();
  expectType<Terminal>(chained);

  // State getters
  expectType<number>(term.cols);
  expectType<number>(term.rows);
  expectType<number>(term.cursorX);
  expectType<number>(term.cursorY);
  expectType<boolean>(term.cursorVisible);
  expectType<string>(term.screen);
  expectType<string>(term.title);
  expectType<string>(term.pwd);
  expectType<number>(term.totalRows);
  expectType<number>(term.scrollbackRows);
  expectType<boolean>(term.mouseTracking);
  expectType<number>(term.handle);
  expectType<boolean>(term.closed);

  // Rendering
  expectType<Uint8Array>(term.format({ emit: "PLAIN" }));
  expectType<string>(term.text());
  expectType<string>(term.unwrappedText());
  expectType<string>(term.html());
  expectType<string>(term.vtText());

  // Snapshot round trip
  const snap: Snapshot = term.snapshot();
  expectType<number>(snap.byteLength);
  expectType<Uint8Array>(snap.bytes);
  const meta = snap.metadata();
  expectType<number>(meta.bytes);
  expectType<number | undefined>(meta.sourceOffset);
  expectType<number | undefined>(meta.historyRowsPrimary);
  expectType<boolean | undefined>(meta.retainContinuation);
  const restored: Terminal = snap.restore();
  restored.close();

  // Search
  const search: Search = term.search();
  const withNeedle: Search = term.search("beta");
  expectType<Search[]>([search, withNeedle]);
  search.needle = "alpha";
  expectType<string>(search.needle);
  expectType<number>(search.totalMatches);
  expectType<boolean>(search.hasMatches);
  expectType<number | undefined>(search.selectedIndex);
  expectType<Search>(search.run());
  expectType<Search>(search.next());
  expectType<Search>(search.prev());
  expectType<Terminal>(search.terminal);
  search.close();

  term.close();
}

/** `using` declarations must be accepted, i.e. Symbol.dispose is declared. */
export async function exerciseDisposal(): Promise<void> {
  using term = await Terminal.open();
  using search = term.search("x");
  using restored = term.snapshot().restore();
  expectType<Terminal>(restored);
  expectType<Search>(search);
}

/** The generated tables must be usable through their declared types. */
export function exerciseTables(): void {
  const descriptor = TERMINAL_DATA.COLS;
  expectType<number>(descriptor.value);
  expectType<"scalar" | "named" | "array" | "input-required">(descriptor.kind);
  expectType<string | undefined>(descriptor.type);
  expectType<number | undefined>(TERMINAL_DATA.SCROLLBACK_ROWS.count);
  expectType<number>(SEARCH_DATA.TOTAL_MATCHES.value);
  expectType<string>(SEARCH_DATA.TOTAL_MATCHES.type);
}

/** Error handling types must narrow as declared. */
export function exerciseErrors(error: unknown): void {
  if (error instanceof GhosttyError) {
    expectType<GhosttyResultCode>(error.code);
    expectType<string>(error.codeName);
    expectType<string | undefined>(error.context);
  }
  expectType<GhosttyResultCode>(check(GHOSTTY_SUCCESS));
}

/** Low-level ABI access must be typed, including buffer pairs. */
export function exerciseAbi(abi: Abi): void {
  const buffer: WasmBuffer = abi.writeBytes("x");
  expectType<number>(buffer.ptr);
  expectType<number>(buffer.len);
  const ptr: number = abi.alloc(16);
  abi.setField("GhosttyString", ptr, "len", 0);
  expectType<unknown>(abi.getField("GhosttyString", ptr, "len"));
  expectType<Record<string, unknown>>(abi.readStruct("GhosttyString", ptr));
  expectType<number>(abi.layout.sizeOf("GhosttyString"));
  expectType<number>(abi.layout.offsetOf("GhosttyString", "len"));
  abi.freeBytes(buffer);
  abi.free(ptr, 16);
}
