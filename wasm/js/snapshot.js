// The Snapshot object: a serialized terminal state.
//
// Snapshots are opaque bytes. `restore()` builds a new Terminal from them;
// `metadata()` reads the framing information without decoding the whole
// terminal, which is what a tool needs in order to decide whether restoring is
// worth it.

import { GhosttyError, GHOSTTY_NO_VALUE } from "./errors.js";
import { Terminal } from "./terminal.js";

export class Snapshot {
  #vt;
  #bytes;

  /**
   * @param {object} vt a loaded libghostty-vt module
   * @param {Uint8Array} bytes snapshot bytes
   * @param {{cols?: number, rows?: number}} [shape] viewport size at capture
   */
  constructor(vt, bytes, { cols, rows } = {}) {
    if (!vt) throw new Error("Snapshot requires a module");
    this.#vt = vt;
    this.#bytes = bytes;
    this.cols = cols;
    this.rows = rows;
  }

  /** A copy of the snapshot bytes. */
  get bytes() {
    return this.#bytes.slice();
  }

  get byteLength() {
    return this.#bytes.length;
  }

  /** The module this snapshot belongs to. */
  get vt() {
    return this.#vt;
  }

  /**
   * Read the snapshot's framing metadata.
   *
   * Uses a decoder over the borrowed bytes and queries only scalar fields, so
   * nothing is decoded and no terminal is created. The decoder and the
   * borrowed buffer are always released, including on error.
   */
  metadata() {
    const abi = this.#vt.abi;
    const buffer = abi.writeBytes(this.#bytes);
    const decoder = abi.opaqueNew(
      (slot) =>
        abi.fn("ghostty_snapshot_decoder_new_buf")(null, slot, buffer.ptr, buffer.len),
      "ghostty_snapshot_decoder_new_buf",
    );
    try {
      return {
        bytes: this.#bytes.length,
        maxContinuationBytes: this.#decoderGet(decoder, "MAX_CONTINUATION_BYTES", "usize"),
        sourceOffset: this.#decoderGet(decoder, "SOURCE_OFFSET", "usize"),
        historyRowsPrimary: this.#decoderGet(decoder, "HISTORY_ROWS_PRIMARY", "usize"),
        historyRowsAlternate: this.#decoderGet(decoder, "HISTORY_ROWS_ALTERNATE", "usize"),
        retainContinuation: this.#decoderGet(decoder, "RETAIN_CONTINUATION", "bool"),
      };
    } finally {
      abi.fn("ghostty_snapshot_decoder_free")(decoder);
      abi.freeBytes(buffer);
    }
  }

  /** Read one GhosttySnapshotDecoderData field, or undefined when unset. */
  #decoderGet(decoder, dataKey, typeName) {
    const vt = this.#vt;
    try {
      return vt.abi.readOut(
        decoder,
        vt.enum("GhosttySnapshotDecoderData", dataKey),
        typeName,
        (handle, key, out) => vt.abi.fn("ghostty_snapshot_decoder_get")(handle, key, out),
        `snapshot_decoder_get(${dataKey})`,
      );
    } catch (error) {
      // An absent optional field is not a reason to fail a metadata read.
      if (error instanceof GhosttyError && error.code === GHOSTTY_NO_VALUE) return undefined;
      throw error;
    }
  }

  /**
   * Decode the snapshot into a new Terminal.
   *
   * Decoding is all-at-once via ghostty_snapshot_decoder_decode, which
   * allocates the terminal. The returned Terminal owns that handle and must be
   * closed by the caller.
   */
  restore() {
    const abi = this.#vt.abi;
    const buffer = abi.writeBytes(this.#bytes);
    let decoder = 0;
    try {
      decoder = abi.opaqueNew(
        (slot) =>
          abi.fn("ghostty_snapshot_decoder_new_buf")(null, slot, buffer.ptr, buffer.len),
        "ghostty_snapshot_decoder_new_buf",
      );
      const handle = abi.opaqueNew(
        (slot) => abi.fn("ghostty_snapshot_decoder_decode")(decoder, slot),
        "ghostty_snapshot_decoder_decode",
      );
      return new Terminal(this.#vt, handle);
    } finally {
      if (decoder) abi.fn("ghostty_snapshot_decoder_free")(decoder);
      // Safe here and not earlier: decode() reached FINISH, so the decoder no
      // longer reads the borrowed bytes. Freeing before decode completes would
      // leave it reading freed memory.
      abi.freeBytes(buffer);
    }
  }
}
