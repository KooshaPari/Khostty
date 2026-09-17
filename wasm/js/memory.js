// Growth-safe access to a wasm module's exported linear memory.
//
// include/ghostty/vt/wasm.h states the contract explicitly: an exported
// function may grow linear memory when it allocates, numeric pointers and
// handles stay valid, but any ArrayBuffer, DataView, or typed array the host
// created before the growth may no longer cover live memory. Hosts must
// reacquire exports.memory.buffer immediately before every access and must
// recreate cached views whenever the buffer identity or its byte length
// changes.
//
// A stale view is not detectable after the fact: it still reads and writes,
// just into a detached buffer, so the bug surfaces as quietly wrong data.
// Memory therefore makes reacquisition unconditional rather than opt-in.

/**
 * A view over `exports.memory` that is always valid for the current memory.
 *
 * Accessors reacquire the backing buffer whenever it has been replaced or
 * resized. Callers may hold this object indefinitely; they must not hold the
 * `Uint8Array`/`DataView` it returns across an allocation.
 */
export class Memory {
  #exports;
  #buffer = null;
  #bytes = null;
  #view = null;

  /** @param {WebAssembly.Exports} exports the instantiated module's exports */
  constructor(exports) {
    if (!exports?.memory?.buffer) {
      throw new Error("wasm module does not export memory");
    }
    this.#exports = exports;
  }

  /** Current ArrayBuffer, reacquiring cached views if memory moved. */
  get buffer() {
    const buffer = this.#exports.memory.buffer;
    if (buffer !== this.#buffer || buffer.byteLength !== this.#buffer?.byteLength) {
      this.#buffer = buffer;
      this.#bytes = new Uint8Array(buffer);
      this.#view = new DataView(buffer);
    }
    return buffer;
  }

  /** Whole-memory Uint8Array. Valid until the next allocation. */
  get bytes() {
    this.buffer;
    return this.#bytes;
  }

  /** Whole-memory DataView. Valid until the next allocation. */
  get view() {
    this.buffer;
    return this.#view;
  }

  /**
   * Unsigned size_t at ptr, honoring the target's usize width.
   *
   * usize is 4 bytes on wasm32, but the manifest publishes the width, so this
   * stays correct if libghostty-vt is ever built for wasm64.
   */
  readUsize(ptr, usizeSize) {
    this.buffer;
    if (usizeSize === 4) return this.#view.getUint32(ptr, true);
    if (usizeSize === 8) return Number(this.#view.getBigUint64(ptr, true));
    throw new Error(`unsupported size_t width: ${usizeSize}`);
  }

  /**
   * Copy len bytes at ptr into a detached Uint8Array.
   *
   * Returns a copy rather than a subarray so the result survives later memory
   * growth. Anything handed to user code should come from here.
   */
  copy(ptr, len) {
    this.buffer;
    return this.#bytes.slice(ptr, ptr + len);
  }

  /** Decode len bytes at ptr as UTF-8. */
  readString(ptr, len) {
    return new TextDecoder().decode(this.copy(ptr, len));
  }

  /** Decode the NUL-terminated UTF-8 string at ptr. */
  readCString(ptr) {
    this.buffer;
    let end = ptr;
    while (end < this.#bytes.length && this.#bytes[end] !== 0) end++;
    return this.readString(ptr, end - ptr);
  }
}
