// GhosttyResult handling for the libghostty-vt wasm module.
//
// Every libghostty-vt C function that can fail returns a GhosttyResult. In
// WebAssembly these arrive as plain signed integers, so without a decode step
// the only visible failure mode is a magic number in a diff. Everything here
// exists to turn that integer back into a named, contextful exception.

/** GhosttyResult codes, keyed by the numeric value the library returns. */
export const RESULT = {
  0: "SUCCESS",
  "-1": "OUT_OF_MEMORY",
  "-2": "INVALID_VALUE",
  "-3": "OUT_OF_SPACE",
  "-4": "NO_VALUE",
};

export const GHOSTTY_SUCCESS = 0;
export const GHOSTTY_OUT_OF_MEMORY = -1;
export const GHOSTTY_INVALID_VALUE = -2;
export const GHOSTTY_OUT_OF_SPACE = -3;
export const GHOSTTY_NO_VALUE = -4;

/**
 * Thrown for any GhosttyResult other than SUCCESS.
 *
 * Carries both the symbolic code name and the raw integer so callers can
 * branch on `code` while still getting a readable message.
 */
export class GhosttyError extends Error {
  constructor(code, context) {
    const name = RESULT[code] ?? `UNKNOWN(${code})`;
    super(context ? `${context}: ${name} (${code})` : `${name} (${code})`);
    this.name = "GhosttyError";
    this.code = code;
    this.codeName = name;
    this.context = context;
  }
}

/**
 * Throw if a GhosttyResult is not SUCCESS; otherwise return it unchanged.
 *
 * @param {number} code value returned by a libghostty-vt call
 * @param {string} [context] what was being attempted, for the error message
 */
export function check(code, context) {
  if (code !== GHOSTTY_SUCCESS) throw new GhosttyError(code, context);
  return code;
}

/** Name for a raw GhosttyResult integer, for logging. */
export function resultName(code) {
  return RESULT[code] ?? `UNKNOWN(${code})`;
}
