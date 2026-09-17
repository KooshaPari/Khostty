// Type declarations for abi.js.

import type { Memory } from "./memory.js";
import type { TypeLayout } from "./layout.js";
import type { GhosttyResultCode } from "./errors.js";

/** A (ptr, len) pair into wasm memory. */
export interface WasmBuffer {
  ptr: number;
  len: number;
}

/** An exported wasm function, as seen by the bindings. */
export type WasmFunction = (...args: number[]) => number;

/** Typed access to a libghostty-vt wasm instance. */
export declare class Abi {
  constructor(exports: WebAssembly.Exports);

  readonly exports: WebAssembly.Exports;
  readonly memory: Memory;
  readonly layout: TypeLayout;
  readonly usizeSize: number;

  /** An exported function by name, failing at lookup rather than call time. */
  fn(name: string): WasmFunction;
  has(name: string): boolean;

  /** Allocate bytes. Throws on failure. */
  alloc(len: number): number;
  free(ptr: number, len: number): void;
  allocOpaque(): number;
  freeOpaque(slot: number): void;
  takeOpaque(slot: number): number;

  /**
   * Run an opaque-handle constructor and return the resulting handle.
   *
   * Releases the out-parameter slot even when the call fails.
   */
  opaqueNew(call: (slot: number) => number, what: string): number;

  /**
   * Run an out-parameter getter and decode the result.
   *
   * `typeName` may be a scalar name ("u16", "usize", "bool", "pointer") or a
   * manifest type name ("GhosttyString", "GhosttyStyle", ...). Struct, union,
   * and packed types decode to objects; enum types to `{ value, name }`.
   */
  readOut(
    handle: number,
    key: number,
    typeName: string,
    call: (handle: number, key: number, out: number) => number,
    what: string,
  ): unknown;

  /** Encode a string as UTF-8, or copy bytes, into fresh wasm memory. */
  writeBytes(data: string | Uint8Array | ArrayLike<number>): WasmBuffer;
  freeBytes(buffer: WasmBuffer): void;
  /** Detached copy of a buffer the library allocated. */
  takeAllocated(ptr: number, len: number): Uint8Array;
  /** Release a buffer the library allocated, via ghostty_free(). */
  freeAllocated(ptr: number, len: number): void;

  /**
   * Allocate a sized struct, initialize nested `size` fields, and write
   * `fields`. Enum-valued fields accept either a member name or a number.
   */
  writeStruct(structName: string, fields?: Record<string, unknown>): number;
  /** Recursively set the `size` field of a sized struct and its nested structs. */
  initSized(structName: string, ptr: number): void;
  setField(structName: string, ptr: number, fieldName: string, value: unknown): void;
  getField(structName: string, ptr: number, fieldName: string): unknown;
  /** Decode a whole struct into an object, recursing into nested structs. */
  readStruct(structName: string, ptr: number): Record<string, unknown>;
}

/** Re-exported for callers that only import the abi module. */
export type { GhosttyResultCode };
