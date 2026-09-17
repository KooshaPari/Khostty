// The Search object: a `ghostty_search_*` handle bound to a Terminal.
//
// The search data table below is hand-written, unlike the terminal data table
// in terminal-data.js which is generated. include/ghostty/vt/search.h
// documents each GhosttySearchData key's out-parameter type in prose rather
// than in the machine-readable "Output type:" form terminal.h uses, so there
// is nothing to generate from. The ABI test validates every member name, value,
// and type name here against the library manifest, so it cannot drift silently.

import { check, GhosttyError, GHOSTTY_NO_VALUE } from "./errors.js";

/** GhosttySearchData member -> out parameter descriptor. */
export const SEARCH_DATA = Object.freeze({
  STATUS: { value: 0, type: "GhosttySearchStatus" },
  NEEDLE: { value: 1, type: "GhosttyString" },
  TOTAL_MATCHES: { value: 2, type: "usize" },
  SELECTED_INDEX: { value: 3, type: "usize" },
  SELECTED_MATCH: { value: 4, type: "GhosttySelection" },
  MATCHES: { value: 5, type: "GhosttySelectionBuffer" },
  VIEWPORT_MATCHES: { value: 6, type: "GhosttySelectionBuffer" },
  SELECT_SCROLL: { value: 7, type: "GhosttySearchScroll" },
});

/**
 * Write a GhosttySearchOption.
 *
 * Lives here rather than in index.js because options are search semantics, and
 * index.js deliberately carries only handle lifecycle for search.
 *
 * @param {object} vt loaded module
 * @param {number} handle search handle
 * @param {string} option GhosttySearchOption member name
 * @param {number} value address of the option's input value (0 for NULL)
 */
function writeSearchOption(vt, handle, option, value) {
  check(
    vt.abi.fn("ghostty_search_set")(handle, vt.enum("GhosttySearchOption", option), value),
    `ghostty_search_set(${option})`,
  );
}

export class Search {
  #vt;
  #terminal;
  #handle;
  #closed = false;
  /** @param {object} vt loaded module @param {object} terminal owning Terminal */
  constructor(vt, terminal) {
    this.#vt = vt;
    this.#terminal = terminal;
    this.#handle = vt.searchNew(terminal.handle);
  }

  get handle() {
    if (this.#closed) throw new Error("search is closed");
    return this.#handle;
  }

  get closed() {
    return this.#closed;
  }

  /** The terminal this search is bound to. */
  get terminal() {
    return this.#terminal;
  }

  #read(dataKey) {
    const vt = this.#vt;
    const desc = SEARCH_DATA[dataKey];
    try {
      const value = vt.abi.readOut(
        this.#handle,
        vt.enum("GhosttySearchData", dataKey),
        desc.type,
        (handle, key, out) => vt.abi.fn("ghostty_search_get")(handle, key, out),
        `search_get(${dataKey})`,
      );
      // GhosttyString out parameters are structs holding a borrowed pointer,
      // so decode them to text rather than handing back a {ptr, len} pair.
      if (desc.type === "GhosttyString" && value) {
        return vt.memory.readString(value.ptr, value.len);
      }
      return value;
    } catch (error) {
      // "Nothing selected" and friends are states, not failures.
      if (error instanceof GhosttyError && error.code === GHOSTTY_NO_VALUE) return undefined;
      throw error;
    }
  }

  /**
   * The needle to search for.
   *
   * Matching is byte-exact except ASCII letters, which compare
   * case-insensitively. Assigning a byte-identical value keeps existing
   * results; anything else restarts the search and drops them. An empty string
   * clears the needle and returns the search to idle.
   */
  set needle(value) {
    const vt = this.#vt;
    const abi = vt.abi;
    const buffer = abi.writeBytes(new TextEncoder().encode(value));
    const string = abi.alloc(vt.layout.sizeOf("GhosttyString"));
    try {
      abi.setField("GhosttyString", string, "ptr", buffer.ptr);
      abi.setField("GhosttyString", string, "len", buffer.len);
      writeSearchOption(this.#vt, this.#handle, "NEEDLE", string);
    } finally {
      abi.free(string, vt.layout.sizeOf("GhosttyString"));
      abi.freeBytes(buffer);
    }
  }

  /** The current needle, or "" when unset. */
  get needle() {
    return this.#read("NEEDLE") ?? "";
  }

  /** Progress state: "RUNNING", "FEED_REQUIRED", or "COMPLETE". */
  get status() {
    const value = this.#read("STATUS");
    return value?.name ?? value;
  }

  /** Total matches found, or undefined when the search has not run. */
  get totalMatches() {
    return this.#read("TOTAL_MATCHES") ?? 0;
  }

  /** Index of the selected match, or undefined when nothing is selected. */
  get selectedIndex() {
    return this.#read("SELECTED_INDEX");
  }

  /** True when at least one match is known. */
  get hasMatches() {
    return this.totalMatches > 0;
  }

  /**
   * Feed the terminal and tick until the search is caught up.
   *
   * Convenience over the library's tick/feed pair. Searching a large
   * scrollback blocks for the duration, so an interactive caller that must
   * stay responsive should drive those two directly.
   */
  run() {
    check(this.#vt.abi.fn("ghostty_search_run")(this.#handle), "ghostty_search_run");
    return this;
  }

  /** Select the next match, moving toward older content. Wraps. */
  next() {
    writeSearchOption(this.#vt, this.#handle, "SELECT_NEXT", 0);
    return this;
  }

  /** Select the previous match, moving toward newer content. Wraps. */
  prev() {
    writeSearchOption(this.#vt, this.#handle, "SELECT_PREV", 0);
    return this;
  }

  close() {
    if (this.#closed) return;
    this.#vt.searchFree(this.#handle);
    this.#closed = true;
  }

  [Symbol.dispose]() {
    this.close();
  }
}
