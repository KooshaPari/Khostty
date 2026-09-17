// Type declarations for memory.js.

/**
 * Growth-safe access to a wasm module's exported linear memory.
 *
 * Accessors reacquire the backing buffer whenever it has been replaced or
 * resized. Callers must not hold the `Uint8Array`/`DataView` these return
 * across an allocation.
 */
export declare class Memory {
  constructor(exports: WebAssembly.Exports);

  /** Current ArrayBuffer, reacquiring cached views if memory moved. */
  readonly buffer: ArrayBuffer;
  /** Whole-memory bytes. Valid until the next allocation. */
  readonly bytes: Uint8Array;
  /** Whole-memory view. Valid until the next allocation. */
  readonly view: DataView;

  /** Unsigned size_t at ptr, honoring the target's usize width. */
  readUsize(ptr: number, usizeSize: number): number;
  /** Detached copy of `len` bytes at `ptr`; survives later memory growth. */
  copy(ptr: number, len: number): Uint8Array;
  /** Decode `len` bytes at ptr as UTF-8. */
  readString(ptr: number, len: number): string;
  /** Decode the NUL-terminated UTF-8 string at ptr. */
  readCString(ptr: number): string;
}
