// The library's self-published type manifest, with lookup helpers.
//
// libghostty-vt exports ghostty_type_json(), which returns a JSON description
// of its own C ABI as compiled for the current target: pointer and size_t
// widths, byte order, maximum alignment, and every public type's kind, size,
// alignment, field offsets, and enum values.
//
// The bindings use this manifest instead of hardcoded numbers so that struct
// layouts cannot drift from the library. A hand-written offset table would
// silently corrupt memory on the next struct change; a manifest lookup fails
// loudly instead.
//
// Shape (abridged; see include/ghostty/vt/types.h for the full contract):
//
//   {
//     "abi": { "target": "wasm32", "os": "freestanding", "pointer_size": 4,
//              "usize_size": 4, "max_alignment": 16, "endian": "little" },
//     "types": {
//       "GhosttyString": {
//         "kind": "struct", "size": 8, "align": 4,
//         "fields": { "ptr": { "offset": 0, "size": 4, "type": "pointer",
//                              "elem": "u8", "const": true },
//                     "len": { "offset": 4, "size": 4, "type": "u32" } } },
//       "GhosttyResult": {
//         "kind": "enum", "size": 4, "align": 4, "underlying": "i32",
//         "prefix": "GHOSTTY_", "values": { "SUCCESS": 0, ... } }
//     }
//   }

/** Kinds the manifest can report for a type. */
export const TYPE_KIND = Object.freeze({
  STRUCT: "struct",
  UNION: "union",
  ENUM: "enum",
  PACKED: "packed",
  ALIAS: "alias",
  OPAQUE: "opaque",
});

export class TypeLayout {
  /** @param {{abi: object, types: Record<string, object>}} json manifest */
  constructor(json) {
    if (!json?.types || !json?.abi) {
      throw new Error("malformed libghostty-vt type manifest");
    }
    this.abi = json.abi;
    this.types = json.types;
  }

  /** size_t width in bytes for this build (4 on wasm32). */
  get usizeSize() {
    return this.abi.usize_size;
  }

  /** Pointer width in bytes for this build. */
  get pointerSize() {
    return this.abi.pointer_size;
  }

  /** True if the named type is present in the manifest. */
  has(name) {
    return Object.hasOwn(this.types, name);
  }

  /** Manifest entry for a named type. Throws if unknown. */
  type(name) {
    const type = this.types[name];
    if (!type) throw new Error(`unknown ABI type: ${name}`);
    return type;
  }

  /** sizeof for a named type. */
  sizeOf(name) {
    const type = this.type(name);
    if (typeof type.size !== "number") {
      throw new Error(`ABI type ${name} has no size`);
    }
    return type.size;
  }

  /** Alignment for a named type. */
  alignOf(name) {
    return this.type(name).align ?? 1;
  }

  /** Field descriptor {offset, size, type, ...} for a struct/union field. */
  field(structName, fieldName) {
    const field = this.type(structName).fields?.[fieldName];
    if (!field) throw new Error(`unknown field ${structName}.${fieldName}`);
    return field;
  }

  /** Byte offset of a field within its struct. */
  offsetOf(structName, fieldName) {
    return this.field(structName, fieldName).offset;
  }

  /** True if the type is a sized struct (one whose first field is `size`). */
  isSizedStruct(name) {
    const type = this.types[name];
    if (!type || (type.kind !== TYPE_KIND.STRUCT && type.kind !== TYPE_KIND.UNION)) {
      return false;
    }
    const size = type.fields?.size;
    return Boolean(size && (size.type === "u32" || size.type === "u64"));
  }

  /** Numeric value of an enum member, e.g. enumValue("GhosttyResult","SUCCESS"). */
  enumValue(enumName, member) {
    const type = this.type(enumName);
    if (type.kind !== TYPE_KIND.ENUM) throw new Error(`${enumName} is not an enum`);
    const value = type.values?.[member];
    if (value === undefined) throw new Error(`unknown enum member ${enumName}.${member}`);
    return value;
  }

  /** All members of an enum as a frozen {NAME: value} map. */
  enumMembers(enumName) {
    const type = this.type(enumName);
    if (type.kind !== TYPE_KIND.ENUM) throw new Error(`${enumName} is not an enum`);
    return Object.freeze({ ...type.values });
  }

  /**
   * Symbolic name for an enum value.
   *
   * Returns the raw value when it is unrecognized (a newer library enum
   * member, for instance) rather than throwing, since this is used for
   * diagnostics on paths that already succeeded. MAX_VALUE is skipped because
   * it is a sentinel, not a real member.
   */
  enumName(enumName, value) {
    const type = this.type(enumName);
    for (const [name, member] of Object.entries(type.values ?? {})) {
      if (member === value && name !== "MAX_VALUE") return name;
    }
    return value;
  }

  /**
   * Names of the members an enum declares, excluding the MAX_VALUE sentinel.
   * Useful for asserting that a binding covers the whole surface.
   */
  enumMemberNames(enumName) {
    return Object.keys(this.enumMembers(enumName)).filter((n) => n !== "MAX_VALUE");
  }
}
