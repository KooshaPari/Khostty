// Type declarations for index.js (loader + minimal bindings).

import type { Abi } from "./abi.js";
import type { Memory } from "./memory.js";
import type { TypeLayout, GhosttyAbiInfo } from "./layout.js";

export type { GhosttyResultCode } from "./errors.js";
export {
  RESULT,
  GHOSTTY_SUCCESS,
  GHOSTTY_OUT_OF_MEMORY,
  GHOSTTY_INVALID_VALUE,
  GHOSTTY_OUT_OF_SPACE,
  GHOSTTY_NO_VALUE,
  GhosttyError,
  check,
  resultName,
} from "./errors.js";
export { Memory } from "./memory.js";
export {
  TYPE_KIND,
  TypeLayout,
} from "./layout.js";
export type {
  GhosttyAbiInfo,
  GhosttyFieldInfo,
  GhosttyTypeInfo,
  GhosttyTypeManifest,
} from "./layout.js";
export { Abi } from "./abi.js";
export type { WasmBuffer, WasmFunction } from "./abi.js";
export { TERMINAL_DATA } from "./terminal-data.js";
export type { TerminalDataDescriptor } from "./terminal-data.js";

/**
 * A function supplied to the wasm module as an import.
 *
 * Deliberately untyped in its parameters: the concrete signature is fixed by
 * the module's declared import, not by the host, so callers annotate their own
 * function and this only has to accept it.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type WasmImportFunction = (...args: any[]) => any;

/** Import values for modules the wasm module imports. */
export type ImportOverrides = Record<string, Record<string, WasmImportFunction>>;

/** Options accepted by every load path. */
export interface LoadOptions {
  /** A compiled module, used as-is. */
  wasmModule?: WebAssembly.Module;
  /** Bytes to compile. */
  wasmBytes?: BufferSource;
  /** Node only: a filesystem path to the .wasm artifact. */
  wasmPath?: string;
  /** A URL to fetch (or read, for `file:` URLs under Node). */
  wasmUrl?: string | URL;
  /** Overrides for the module's declared imports. */
  imports?: ImportOverrides;
}

/** Options for terminal construction. */
export interface TerminalInit {
  /** Columns. Default 80. */
  cols?: number;
  /** Rows. Default 24. */
  rows?: number;
  /** Allocator address, or null for the library default. */
  allocator?: number | null;
}

/** Options for the terminal formatter. */
export interface FormatOptions {
  /** GhosttyFormatterFormat member name. Default "PLAIN". */
  emit?: "PLAIN" | "VT" | "HTML";
  /** Join soft-wrapped lines. Default false. */
  unwrap?: boolean;
  /** Trim trailing whitespace on non-blank lines. Default true. */
  trim?: boolean;
  /** GhosttyFormatterTerminalExtra fields, as a partial object. */
  extra?: Record<string, unknown>;
}

/** Instantiation metadata recorded on a loaded module. */
export interface GhosttyVtMeta {
  /** Size of the wasm artifact in bytes, when known. */
  bytes: number | null;
  /** Where the artifact came from, when known. */
  url: string | null;
  /** The ABI the module was compiled for. */
  abi: GhosttyAbiInfo;
}

/** A loaded libghostty-vt wasm module. */
export declare class GhosttyVt {
  constructor(exports: WebAssembly.Exports, meta?: { bytes?: number; url?: string });

  /** The ABI layer: allocations, struct layout, out-parameter decoding. */
  readonly abi: Abi;
  /** Instantiation metadata. */
  readonly meta: Readonly<GhosttyVtMeta>;

  /** Raw wasm exports, for anything the bindings do not cover yet. */
  readonly exports: WebAssembly.Exports;
  /** Growth-safe memory view. */
  readonly memory: Memory;
  /** The library's type manifest. */
  readonly layout: TypeLayout;
  /** The type manifest as formatted JSON. */
  readonly typeJson: string;

  /** Numeric value of an enum member, e.g. enum("GhosttyResult","SUCCESS"). */
  enum(enumName: string, member: string): number;

  // Terminal lifecycle
  terminalNew(init?: TerminalInit): number;
  terminalFree(handle: number): void;
  terminalReset(handle: number): void;
  terminalResize(handle: number, cols: number, rows: number): void;
  /** Write a string (encoded as UTF-8) or raw bytes. */
  terminalVtWrite(handle: number, data: string | Uint8Array): void;

  /**
   * Read one GhosttyTerminalData field by member name.
   *
   * Returns a number, boolean, string (for GhosttyString out parameters), or
   * object (for struct out parameters). Returns undefined on GHOSTTY_NO_VALUE.
   * Throws for keys whose `kind` is "array" or "input-required".
   */
  terminalGet(handle: number, key: string): unknown;

  // Formatting
  formatterNew(terminal: number, options?: FormatOptions): number;
  formatterFree(formatter: number): void;
  /** Format via a formatter handle. Returns detached bytes. */
  formatterFormat(formatter: number): Uint8Array;
  /** Format a terminal, allocating and freeing a formatter internally. */
  formatTerminal(terminal: number, options?: FormatOptions): Uint8Array;
  /** Format a terminal's active screen as text. */
  format(terminal: number, options?: FormatOptions): string;

  // Snapshot
  snapshotEncode(terminal: number): Uint8Array;

  // Search handle lifecycle (semantics live in api.js's Search)
  searchNew(terminal: number): number;
  searchFree(search: number): void;
}

/** Default module location: the artifact produced by wasm/build.sh. */
export declare const DEFAULT_WASM_URL: URL;

/**
 * Load and instantiate the libghostty-vt wasm module.
 *
 * Source precedence: wasmBytes, wasmModule, wasmPath (Node), wasmUrl, then the
 * default sibling artifact.
 */
export declare function loadGhosttyVt(options?: LoadOptions): Promise<GhosttyVt>;

export default loadGhosttyVt;
