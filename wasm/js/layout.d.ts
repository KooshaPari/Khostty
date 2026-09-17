// Type declarations for layout.js.

/** Byte widths and properties of the target this module was compiled for. */
export interface GhosttyAbiInfo {
  /** e.g. "wasm32". */
  target: string;
  /** e.g. "freestanding". */
  os: string;
  environment: string;
  /** Pointer width in bytes (4 on wasm32). */
  pointer_size: number;
  /** size_t width in bytes (4 on wasm32). */
  usize_size: number;
  max_alignment: number;
  /** "little" or "big". */
  endian: string;
}

/** One field of a manifest struct/union, positioned at a byte offset. */
export interface GhosttyFieldInfo {
  offset: number;
  size: number;
  /** A scalar name ("u32", "bool", "usize", "pointer") or a manifest type. */
  type: string;
  /** For pointer fields: the pointed-to type. */
  elem?: string;
  const?: boolean;
  nullable?: boolean;
  /** For tagged-union members: the discriminator field name. */
  tag?: string;
  arms?: Record<string, string | null>;
}

/** A type entry in the manifest published by ghostty_type_json(). */
export interface GhosttyTypeInfo {
  kind: "struct" | "union" | "enum" | "packed" | "alias" | "opaque";
  size?: number;
  align?: number;
  /** For struct/union/packed. */
  fields?: Record<string, GhosttyFieldInfo>;
  /** For enums. */
  underlying?: "i32" | "u32" | "u8" | string;
  prefix?: string;
  /** For enums: member name (prefix stripped) to value. */
  values?: Record<string, number>;
}

/** The full type manifest. */
export interface GhosttyTypeManifest {
  abi: GhosttyAbiInfo;
  types: Record<string, GhosttyTypeInfo>;
}

/** Kinds the manifest can report for a type. */
export declare const TYPE_KIND: Readonly<{
  STRUCT: "struct";
  UNION: "union";
  ENUM: "enum";
  PACKED: "packed";
  ALIAS: "alias";
  OPAQUE: "opaque";
}>;

/** The library's self-published type manifest, with lookup helpers. */
export declare class TypeLayout {
  constructor(json: GhosttyTypeManifest);
  readonly abi: GhosttyAbiInfo;
  readonly types: Record<string, GhosttyTypeInfo>;
  readonly usizeSize: number;
  readonly pointerSize: number;

  has(name: string): boolean;
  type(name: string): GhosttyTypeInfo;
  sizeOf(name: string): number;
  alignOf(name: string): number;
  field(structName: string, fieldName: string): GhosttyFieldInfo;
  offsetOf(structName: string, fieldName: string): number;
  /** True if the type is a sized struct (first field is `size`). */
  isSizedStruct(name: string): boolean;
  enumValue(enumName: string, member: string): number;
  enumMembers(enumName: string): Readonly<Record<string, number>>;
  /** Symbolic name for an enum value, or the raw value if unrecognized. */
  enumName(enumName: string, value: number): string | number;
  /** Member names excluding the MAX_VALUE sentinel. */
  enumMemberNames(enumName: string): string[];
}
