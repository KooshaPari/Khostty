// Type declarations for terminal.js.

import type { GhosttyVt, FormatOptions, LoadOptions, TerminalInit } from "./index.js";
import type { Snapshot } from "./snapshot.js";
import type { Search } from "./search.js";

/** Any loadGhosttyVt option, plus a module to reuse and cols/rows. */
export interface OpenOptions extends LoadOptions, TerminalInit {
  /** An already-loaded module, avoiding a second instantiation. */
  vt?: GhosttyVt;
}

/**
 * A `ghostty_terminal_*` handle.
 *
 * Property reads are live calls into the wasm module, not cached state, so
 * they always reflect the terminal as of the last write.
 */
export declare class Terminal {
  constructor(
    vt: GhosttyVt,
    handle: number,
    shape?: { cols?: number; rows?: number },
  );

  /** Load the wasm module (unless supplied) and create a terminal. */
  static open(options?: OpenOptions): Promise<Terminal>;

  /** The wasm module this terminal belongs to. */
  readonly vt: GhosttyVt;
  /** The raw wasm handle, for calls the bindings do not wrap yet. */
  readonly handle: number;
  readonly closed: boolean;

  /** Viewport columns. */
  cols: number;
  /** Viewport rows. */
  rows: number;

  /** Cursor column, 0-based. */
  readonly cursorX: number;
  /** Cursor row, 0-based. */
  readonly cursorY: number;
  /** Whether the cursor is visible (DEC mode 25). */
  readonly cursorVisible: boolean;
  /** Active screen: "PRIMARY" or "ALTERNATE". */
  readonly screen: string;
  /** Title set by OSC 0/2, or "" if unset. */
  readonly title: string;
  /** Working directory set by OSC 7, or "" if unset. */
  readonly pwd: string;
  /** Total rows in the active screen, including scrollback. */
  readonly totalRows: number;
  /** Scrollback rows: total rows minus viewport rows. */
  readonly scrollbackRows: number;
  /** Whether any mouse tracking mode is active. */
  readonly mouseTracking: boolean;
  /** The style that will be applied to newly printed characters. */
  readonly cursorStyle: unknown;
  /** Viewport scrollbar state. */
  readonly scrollbar: unknown;

  /** Write VT-encoded data. A string is encoded as UTF-8 first. */
  write(data: string | Uint8Array): this;
  /** Resize, reflowing contents. */
  resize(cols: number, rows: number): this;
  /** Reset to the initial state, keeping the current size. */
  reset(): this;

  /** Format the active screen. Returns raw bytes. */
  format(options?: FormatOptions): Uint8Array;
  /** Active screen as plain text, soft-wrapped lines kept wrapped. */
  text(options?: FormatOptions): string;
  /** Active screen as plain text with soft-wrapped lines joined. */
  unwrappedText(options?: FormatOptions): string;
  /** Active screen as HTML with inline styles. */
  html(options?: FormatOptions): string;
  /** Active screen as VT escape sequences. */
  vtText(options?: FormatOptions): string;

  /** Capture the terminal's state. */
  snapshot(): Snapshot;
  /** Create a Search bound to this terminal. */
  search(needle?: string): Search;

  /** Release the terminal handle along with any searches bound to it. */
  close(): void;
  [Symbol.dispose](): void;
}
