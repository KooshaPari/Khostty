// High-level object model for libghostty-vt in WebAssembly.
//
// index.js exposes the C ABI as functions taking handles; this module turns
// those into objects with lifetimes:
//
//   import { Terminal } from "./api.js";
//   using term = await Terminal.open({ cols: 80, rows: 24 });
//   term.write("hello\r\n");
//   console.log(term.text());
//
// Each class lives in its own module and owns a wasm handle, freeing it exactly
// once. `close()` is idempotent on all of them, and each implements
// Symbol.dispose so `using` works.
//
// Note on module cycles: terminal.js imports Snapshot (for Terminal#snapshot)
// and snapshot.js imports Terminal (for Snapshot#restore). That cycle is
// deliberate and safe because both references are only dereferenced inside
// method bodies, long after every module body has been evaluated. Neither
// module reads the other's binding at evaluation time.

export { Terminal } from "./terminal.js";
export { Snapshot } from "./snapshot.js";
export { Search, SEARCH_DATA } from "./search.js";

// Re-exported so `import { Terminal, GhosttyError } from "./api.js"` works
// without a second import.
export {
  loadGhosttyVt,
  GhosttyError,
  GhosttyVt,
  DEFAULT_WASM_URL,
  RESULT,
  resultName,
  GHOSTTY_SUCCESS,
  GHOSTTY_OUT_OF_MEMORY,
  GHOSTTY_INVALID_VALUE,
  GHOSTTY_OUT_OF_SPACE,
  GHOSTTY_NO_VALUE,
  TERMINAL_DATA,
} from "./index.js";

import { Terminal } from "./terminal.js";

/**
 * Load the module and open a terminal in one call.
 *
 * @param {object} [options] Terminal.open options
 * @returns {Promise<Terminal>}
 */
export async function openTerminal(options = {}) {
  return Terminal.open(options);
}

export default Terminal;
