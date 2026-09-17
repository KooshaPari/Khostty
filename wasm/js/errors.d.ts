// Type declarations for errors.js.

/** A GhosttyResult code, as returned by libghostty-vt calls. */
export type GhosttyResultCode = number;

/** GhosttyResult codes, keyed by the numeric value the library returns. */
export declare const RESULT: Readonly<Record<string, string>>;

export declare const GHOSTTY_SUCCESS: 0;
export declare const GHOSTTY_OUT_OF_MEMORY: -1;
export declare const GHOSTTY_INVALID_VALUE: -2;
export declare const GHOSTTY_OUT_OF_SPACE: -3;
export declare const GHOSTTY_NO_VALUE: -4;

/** Thrown for any GhosttyResult other than SUCCESS. */
export declare class GhosttyError extends Error {
  constructor(code: GhosttyResultCode, context?: string);
  readonly code: GhosttyResultCode;
  readonly codeName: string;
  readonly context: string | undefined;
}

/** Throw unless `code` is SUCCESS; returns `code` unchanged otherwise. */
export declare function check(code: GhosttyResultCode, context?: string): GhosttyResultCode;

/** Symbolic name for a raw GhosttyResult integer. */
export declare function resultName(code: GhosttyResultCode): string;
