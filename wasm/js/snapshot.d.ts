// Type declarations for snapshot.js.

import type { GhosttyVt } from "./index.js";
import type { Terminal } from "./terminal.js";

/** Framing metadata published by a snapshot decoder. */
export interface SnapshotMetadata {
  /** Total snapshot size in bytes. */
  bytes: number;
  /** Continuation bytes the snapshot provides. */
  maxContinuationBytes: number | undefined;
  /** Offset of the first unconsumed source byte. */
  sourceOffset: number | undefined;
  /** Scrollback rows restored into the primary screen. */
  historyRowsPrimary: number | undefined;
  /** Scrollback rows restored into the alternate screen. */
  historyRowsAlternate: number | undefined;
  /** Whether continuation bytes are retained. */
  retainContinuation: boolean | undefined;
}

/**
 * A serialized terminal state.
 *
 * Snapshots are opaque bytes. `restore()` builds a new Terminal from them;
 * `metadata()` reads the framing information without decoding the terminal.
 */
export declare class Snapshot {
  constructor(
    vt: GhosttyVt,
    bytes: Uint8Array,
    shape?: { cols?: number; rows?: number },
  );

  /** A copy of the snapshot bytes. */
  readonly bytes: Uint8Array;
  readonly byteLength: number;
  /** The module this snapshot belongs to. */
  readonly vt: GhosttyVt;
  /** Viewport size at capture, when known. */
  cols?: number;
  rows?: number;

  /**
   * Read the snapshot's framing metadata.
   *
   * Fields that the decoder only learns after it makes progress are undefined
   * here, because nothing is decoded.
   */
  metadata(): SnapshotMetadata;

  /**
   * Decode the snapshot into a new Terminal.
   *
   * The returned Terminal owns its handle and must be closed by the caller.
   */
  restore(): Terminal;
}
