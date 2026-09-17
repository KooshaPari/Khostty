// Type declarations for terminal-data.js.
// Generated data: see wasm/tools/gen-terminal-data.mjs.

/** Descriptor for one GhosttyTerminalData key's out parameter. */
export interface TerminalDataDescriptor {
  /** The GhosttyTerminalData enum value. */
  value: number;
  /**
   * "scalar" for a fixed-width number/boolean, "named" for a manifest type,
   * "array" for a fixed-size array, "input-required" for keys the generic
   * read path must refuse because they need a caller-initialized input.
   */
  kind: "scalar" | "named" | "array" | "input-required";
  /** Manifest or scalar type name; absent for "input-required". */
  type?: string;
  /** For "array" keys, the element count. */
  count?: number;
  /** For "input-required" keys, why the generic path refuses it. */
  note?: string;
}

/** GhosttyTerminalData member -> out parameter descriptor. */
export declare const TERMINAL_DATA: Readonly<Record<string, TerminalDataDescriptor>>;
