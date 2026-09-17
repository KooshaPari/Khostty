// Type declarations for api.js: the high-level object model.
//
//   import { Terminal } from "./api.js";
//   using term = await Terminal.open({ cols: 80, rows: 24 });
//   term.write("hello\r\n");
//   console.log(term.text());

export { Terminal } from "./terminal.js";
export type { OpenOptions } from "./terminal.js";
export { Snapshot } from "./snapshot.js";
export type { SnapshotMetadata } from "./snapshot.js";
export { Search, SEARCH_DATA } from "./search.js";
export type { SearchDataDescriptor, SearchStatus } from "./search.js";

// Re-exported so `import { Terminal, GhosttyError } from "./api.js"` works
// without a second import.
export {
  loadGhosttyVt,
  GhosttyVt,
  DEFAULT_WASM_URL,
  RESULT,
  resultName,
  GHOSTTY_SUCCESS,
  GHOSTTY_OUT_OF_MEMORY,
  GHOSTTY_INVALID_VALUE,
  GHOSTTY_OUT_OF_SPACE,
  GHOSTTY_NO_VALUE,
  GhosttyError,
  check,
  Abi,
  Memory,
  TypeLayout,
  TYPE_KIND,
  TERMINAL_DATA,
} from "./index.js";
export type {
  FormatOptions,
  GhosttyResultCode,
  GhosttyVtMeta,
  ImportOverrides,
  LoadOptions,
  TerminalDataDescriptor,
  TerminalInit,
  WasmBuffer,
  WasmFunction,
} from "./index.js";

import { Terminal } from "./terminal.js";
import type { OpenOptions } from "./terminal.js";

/** Load the module and open a terminal in one call. */
export declare function openTerminal(options?: OpenOptions): Promise<Terminal>;

export default Terminal;
