// Type declarations for search.js.

import type { GhosttyVt } from "./index.js";
import type { Terminal } from "./terminal.js";

/** Descriptor for one GhosttySearchData key's out parameter. */
export interface SearchDataDescriptor {
  /** The GhosttySearchData enum value. */
  value: number;
  /** Manifest or scalar type name. */
  type: string;
}

/**
 * GhosttySearchData member -> out parameter descriptor.
 *
 * Hand-written because search.h documents out-parameter types in prose rather
 * than in the machine-readable form terminal.h uses. The ABI test validates
 * every name, value, and type against the library manifest.
 */
export declare const SEARCH_DATA: Readonly<Record<string, SearchDataDescriptor>>;

/** Progress state of a search. */
export type SearchStatus = "RUNNING" | "FEED_REQUIRED" | "COMPLETE" | number;

/** A `ghostty_search_*` handle bound to a Terminal. */
export declare class Search {
  constructor(vt: GhosttyVt, terminal: Terminal);

  readonly handle: number;
  readonly closed: boolean;
  /** The terminal this search is bound to. */
  readonly terminal: Terminal;

  /**
   * The needle to search for.
   *
   * Matching is byte-exact except ASCII letters, which compare
   * case-insensitively. Assigning a byte-identical value keeps existing
   * results; anything else restarts the search. "" clears the needle.
   */
  needle: string;

  /** Progress state. */
  readonly status: SearchStatus;
  /** Total matches found. */
  readonly totalMatches: number;
  /** Index of the selected match, or undefined when none is selected. */
  readonly selectedIndex: number | undefined;
  /** True when at least one match is known. */
  readonly hasMatches: boolean;

  /** Feed the terminal and tick until the search is caught up. */
  run(): this;
  /** Select the next match, moving toward older content. Wraps. */
  next(): this;
  /** Select the previous match, moving toward newer content. Wraps. */
  prev(): this;

  close(): void;
  [Symbol.dispose](): void;
}
