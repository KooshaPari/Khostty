// The Terminal object: a `ghostty_terminal_*` handle with a lifetime.
//
// Property reads are live calls into the wasm module rather than cached state,
// so they always reflect the terminal as of the last write. Every mutating
// method returns `this` so calls chain.

import { loadGhosttyVt } from "./index.js";
import { Snapshot } from "./snapshot.js";
import { Search } from "./search.js";

export class Terminal {
  #vt;
  #handle;
  #closed = false;
  #children = new Set();

  /**
   * Wrap an existing terminal handle.
   *
   * Prefer Terminal.open() unless you already have a handle, from a snapshot
   * restore for instance.
   */
  constructor(vt, handle, { cols, rows } = {}) {
    if (!vt || !handle) throw new Error("Terminal requires a module and a handle");
    this.#vt = vt;
    this.#handle = handle;
    this.cols = cols ?? vt.terminalGet(handle, "COLS");
    this.rows = rows ?? vt.terminalGet(handle, "ROWS");
  }

  /**
   * Load the wasm module (unless one is supplied) and create a terminal.
   *
   * @param {{cols?: number, rows?: number, vt?: object} & object} [options]
   *   Any loadGhosttyVt option (wasmPath, wasmUrl, wasmBytes, imports, ...)
   *   plus cols/rows.
   */
  static async open(options = {}) {
    const { cols = 80, rows = 24, vt, ...loadOptions } = options;
    const module = vt ?? (await loadGhosttyVt(loadOptions));
    return new Terminal(module, module.terminalNew({ cols, rows }), { cols, rows });
  }

  /** The wasm module this terminal belongs to. */
  get vt() {
    return this.#vt;
  }

  /** The raw wasm handle, for calls the bindings do not wrap yet. */
  get handle() {
    this.#assertOpen();
    return this.#handle;
  }

  get closed() {
    return this.#closed;
  }

  #assertOpen() {
    if (this.#closed) throw new Error("terminal is closed");
  }

  #get(key) {
    this.#assertOpen();
    return this.#vt.terminalGet(this.#handle, key);
  }

  // --- state --------------------------------------------------------------

  /** Cursor column, 0-based. */
  get cursorX() {
    return this.#get("CURSOR_X");
  }

  /** Cursor row, 0-based. */
  get cursorY() {
    return this.#get("CURSOR_Y");
  }

  /** Whether the cursor is visible (DEC mode 25). */
  get cursorVisible() {
    return this.#get("CURSOR_VISIBLE");
  }

  /** Active screen: "PRIMARY" or "ALTERNATE". */
  get screen() {
    const value = this.#get("ACTIVE_SCREEN");
    return value?.name ?? value;
  }

  /** The terminal title set by OSC 0/2, or "" if unset. */
  get title() {
    return this.#get("TITLE");
  }

  /** The working directory set by OSC 7, or "" if unset. */
  get pwd() {
    return this.#get("PWD");
  }

  /** Total rows in the active screen, including scrollback. */
  get totalRows() {
    return this.#get("TOTAL_ROWS");
  }

  /** Scrollback rows: total rows minus viewport rows. */
  get scrollbackRows() {
    return this.#get("SCROLLBACK_ROWS");
  }

  /** Whether any mouse tracking mode is active. */
  get mouseTracking() {
    return this.#get("MOUSE_TRACKING");
  }

  /** The style that will be applied to newly printed characters. */
  get cursorStyle() {
    return this.#get("CURSOR_STYLE");
  }

  /** Viewport scrollbar state. */
  get scrollbar() {
    return this.#get("SCROLLBAR");
  }

  // --- mutation -----------------------------------------------------------

  /**
   * Write VT-encoded data.
   *
   * @param {string|Uint8Array} data a string is encoded as UTF-8 first
   */
  write(data) {
    this.#assertOpen();
    this.#vt.terminalVtWrite(this.#handle, data);
    return this;
  }

  /** Resize the terminal, reflowing its contents. */
  resize(cols, rows) {
    this.#assertOpen();
    this.#vt.terminalResize(this.#handle, cols, rows);
    this.cols = cols;
    this.rows = rows;
    return this;
  }

  /** Reset to the initial state, keeping the current size. */
  reset() {
    this.#assertOpen();
    this.#vt.terminalReset(this.#handle);
    return this;
  }

  // --- rendering ----------------------------------------------------------

  /**
   * Format the active screen.
   *
   * @param {{emit?: "PLAIN"|"VT"|"HTML", unwrap?: boolean, trim?: boolean}} [options]
   * @returns {Uint8Array} raw formatted bytes
   */
  format(options = {}) {
    this.#assertOpen();
    return this.#vt.formatTerminal(this.#handle, options);
  }

  /** Active screen as plain text, with soft-wrapped lines kept wrapped. */
  text(options = {}) {
    return new TextDecoder().decode(this.format(options));
  }

  /** Active screen as plain text with soft-wrapped lines joined. */
  unwrappedText(options = {}) {
    return this.text({ ...options, unwrap: true });
  }

  /** Active screen as HTML with inline styles. */
  html(options = {}) {
    return this.text({ ...options, emit: "HTML" });
  }

  /** Active screen as VT escape sequences. */
  vtText(options = {}) {
    return this.text({ ...options, emit: "VT" });
  }

  // --- related objects ----------------------------------------------------

  /** Capture the terminal's state as a Snapshot. */
  snapshot() {
    this.#assertOpen();
    return new Snapshot(this.#vt, this.#vt.snapshotEncode(this.#handle), {
      cols: this.cols,
      rows: this.rows,
    });
  }

  /**
   * Create a Search bound to this terminal.
   *
   * The search is tracked as a child so closing the terminal closes it. The
   * library allows the two to be freed in either order, but closing both from
   * one place removes the choice.
   */
  search(needle) {
    this.#assertOpen();
    const search = new Search(this.#vt, this);
    this.#children.add(search);
    if (needle !== undefined) search.needle = needle;
    return search;
  }

  /** Release the terminal handle along with any searches bound to it. */
  close() {
    if (this.#closed) return;
    for (const child of this.#children) child.close();
    this.#children.clear();
    this.#vt.terminalFree(this.#handle);
    this.#closed = true;
  }

  [Symbol.dispose]() {
    this.close();
  }
}
