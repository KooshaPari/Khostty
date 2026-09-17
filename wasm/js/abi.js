// Typed access to a libghostty-vt wasm instance.
//
// This is the "higher-level API that abstracts away all this" that
// include/ghostty/vt/wasm.h calls for. It owns the export table, the
// growth-safe memory view, the type manifest, and every allocation idiom the
// wasm ABI documents.
//
// Two rules from that header are enforced structurally rather than by
// convention:
//
//   * Views are never cached across an allocation. Every read and write goes
//     through Memory, which reacquires on growth.
//   * Opaque handles are never created inline. opaqueNew() performs the
//     allocate-slot, call, check, take, free-slot sequence so a result can
//     never be dropped on the floor, and a failed constructor can never leak
//     its slot.

import { Memory } from "./memory.js";
import { TypeLayout, TYPE_KIND } from "./layout.js";
import { check } from "./errors.js";

/**
 * Byte widths of the fixed-width scalar types the manifest uses for out
 * parameters.
 *
 * `usize` and `pointer` are absent on purpose: both are target-dependent and
 * are resolved from the manifest instead of being hardcoded here.
 */
const SCALAR_SIZES = Object.freeze({
  u8: 1,
  i8: 1,
  bool: 1,
  u16: 2,
  i16: 2,
  u32: 4,
  i32: 4,
  f32: 4,
  u64: 8,
  i64: 8,
  f64: 8,
});

/**
 * Byte width of an out-parameter scalar, or undefined if it is not a scalar.
 * @param {string} name manifest scalar name
 * @param {{usizeSize: number, pointerSize: number}} abi target widths
 */
function scalarWidth(name, abi) {
  if (name === "usize") return abi.usizeSize;
  if (name === "pointer") return abi.pointerSize;
  return SCALAR_SIZES[name];
}

/**
 * A wasm instance's exported ABI, with typed struct and allocation helpers.
 */
export class Abi {
  /** @param {WebAssembly.Exports} exports a libghostty-vt wasm module's exports */
  constructor(exports) {
    if (typeof exports?.ghostty_type_json !== "function") {
      throw new Error(
        "ghostty_type_json is not exported; this is not a libghostty-vt wasm module",
      );
    }
    this.exports = exports;
    this.memory = new Memory(exports);
    this.layout = new TypeLayout(
      JSON.parse(this.memory.readCString(exports.ghostty_type_json())),
    );
  }

  get usizeSize() {
    return this.layout.usizeSize;
  }

  /**
   * An exported function by name, failing at lookup instead of call time.
   * A half-implemented binding should break where it is written.
   */
  fn(name) {
    const fn = this.exports[name];
    if (typeof fn !== "function") {
      throw new Error(`wasm module does not export ${name}`);
    }
    return fn;
  }

  /** True if the module exports the named function. */
  has(name) {
    return typeof this.exports[name] === "function";
  }

  // --- raw allocation -----------------------------------------------------

  /** Allocate len uninitialized bytes. Throws on failure. */
  alloc(len) {
    const ptr = this.exports.ghostty_wasm_alloc(len);
    if (ptr === 0) throw new Error(`ghostty_wasm_alloc(${len}) failed`);
    return ptr;
  }

  /** Release a ghostty_wasm_alloc() buffer using its original length. */
  free(ptr, len) {
    if (ptr && len) this.exports.ghostty_wasm_free(ptr, len);
  }

  /** Allocate one opaque out-parameter slot, initialized to NULL. */
  allocOpaque() {
    const slot = this.exports.ghostty_wasm_alloc_opaque();
    if (slot === 0) throw new Error("ghostty_wasm_alloc_opaque() failed");
    return slot;
  }

  freeOpaque(slot) {
    if (slot) this.exports.ghostty_wasm_free_opaque(slot);
  }

  /** Read the handle in an out-parameter slot and reset the slot to NULL. */
  takeOpaque(slot) {
    return this.exports.ghostty_wasm_take_opaque(slot);
  }

  /**
   * Run an opaque-handle constructor and return the resulting handle.
   *
   * Every `ghostty_*_new()` has the same shape: allocate a slot, call with the
   * slot as an out parameter, check the result, take the handle, release the
   * slot. This makes that shape unmissable and guarantees the slot is released
   * even when the result is an error.
   *
   * @param {(slot: number) => number} call receives the slot, returns a result
   * @param {string} what used in error messages
   */
  opaqueNew(call, what) {
    const slot = this.allocOpaque();
    try {
      check(call(slot), what);
      const handle = this.takeOpaque(slot);
      if (handle === 0) throw new Error(`${what} produced a NULL handle`);
      return handle;
    } finally {
      this.freeOpaque(slot);
    }
  }

  /**
   * Run an out-parameter `ghostty_*_get()` and decode the result.
   *
   * @param {number} handle the terminal/search/etc handle
   * @param {number} key the DATA enum value to read
   * @param {string} typeName out-parameter type: a scalar name ("u16", "usize",
   *   "bool", ...) or a manifest type name ("GhosttyString", "GhosttyStyle", ...)
   * @param {(handle: number, key: number, out: number) => number} call
   * @param {string} what used in error messages
   */
  readOut(handle, key, typeName, call, what) {
    const width = scalarWidth(typeName, this);
    if (width !== undefined) {
      const out = this.alloc(width);
      try {
        check(call(handle, key, out), what);
        return this.#readScalar(out, typeName);
      } finally {
        this.free(out, width);
      }
    }

    const type = this.layout.type(typeName);
    const size = type.size ?? this.layout.pointerSize;
    const out = this.alloc(size);
    try {
      check(call(handle, key, out), what);
      if (type.kind === TYPE_KIND.STRUCT || type.kind === TYPE_KIND.UNION) {
        return this.readStruct(typeName, out);
      }
      if (type.kind === TYPE_KIND.ENUM) {
        const raw = this.#readScalar(out, type.underlying);
        return { value: raw, name: this.layout.enumName(typeName, raw) };
      }
      if (type.kind === TYPE_KIND.ALIAS) {
        return this.#readScalar(out, type.underlying ?? "u32");
      }
      // opaque: nothing meaningful to decode, return the raw first word.
      return this.#readScalar(out, "u32");
    } finally {
      this.free(out, size);
    }
  }

  // --- byte buffers -------------------------------------------------------

  /**
   * Copy bytes into fresh wasm memory. Pair with freeBytes().
   *
   * Accepts a string (encoded as UTF-8), a Uint8Array, or any array-like of
   * octets. Strings are encoded explicitly because Uint8Array.from("x") does
   * not encode: it coerces each character to a number and yields zeros.
   */
  writeBytes(data) {
    const bytes =
      typeof data === "string"
        ? new TextEncoder().encode(data)
        : data instanceof Uint8Array
          ? data
          : Uint8Array.from(data);
    const ptr = this.alloc(bytes.length);
    // Copy through the live view: alloc may have grown memory.
    this.memory.bytes.set(bytes, ptr);
    return { ptr, len: bytes.length };
  }

  freeBytes({ ptr, len }) {
    this.free(ptr, len);
  }

  /**
   * Copy a buffer the library allocated with its own allocator.
   *
   * Returns a detached copy so the caller can free the wasm-side buffer
   * immediately and never has to reason about view validity.
   */
  takeAllocated(ptr, len) {
    return this.memory.copy(ptr, len);
  }

  /** Release a buffer the library allocated, via ghostty_free(). */
  freeAllocated(ptr, len) {
    if (ptr && len) this.fn("ghostty_free")(0, ptr, len);
  }

  // --- typed structs ------------------------------------------------------

  /**
   * Allocate a struct, zero it, and write the given fields.
   *
   * Sized option structs get their `size` field filled in automatically,
   * recursively for nested structs, so callers never compute sizeof by hand
   * (and cannot get it wrong).
   */
  writeStruct(structName, fields = {}) {
    const size = this.layout.sizeOf(structName);
    const ptr = this.alloc(size);
    this.memory.bytes.fill(0, ptr, ptr + size);
    this.initSized(structName, ptr);
    for (const [name, value] of Object.entries(fields)) {
      this.setField(structName, ptr, name, value);
    }
    return ptr;
  }

  /** Recursively set the `size` field of a sized struct and its nested structs. */
  initSized(structName, ptr) {
    const type = this.layout.type(structName);
    if (type.kind !== TYPE_KIND.STRUCT && type.kind !== TYPE_KIND.UNION) return;
    const sizeField = type.fields?.size;
    if (sizeField && (sizeField.type === "u32" || sizeField.type === "u64")) {
      this.#writeScalar(ptr + sizeField.offset, sizeField.type, type.size);
    }
    for (const field of Object.values(type.fields ?? {})) {
      const nested = this.layout.types[field.type];
      if (nested && (nested.kind === TYPE_KIND.STRUCT || nested.kind === TYPE_KIND.UNION)) {
        this.initSized(field.type, ptr + field.offset);
      }
    }
  }

  /** Write one struct field at its manifest offset. */
  setField(structName, ptr, fieldName, value) {
    const field = this.layout.field(structName, fieldName);
    const at = ptr + field.offset;

    if (field.type === "pointer") {
      if (value === null || value === undefined) {
        this.memory.view.setUint32(at, 0, true);
      } else if (typeof value === "number") {
        this.memory.view.setUint32(at, value, true);
      } else {
        throw new Error(`${structName}.${fieldName} expects an address or null`);
      }
      return;
    }

    const nested = this.layout.types[field.type];
    if (nested && (nested.kind === TYPE_KIND.STRUCT || nested.kind === TYPE_KIND.UNION)) {
      if (typeof value !== "object" || value === null) {
        throw new Error(`${structName}.${fieldName} expects a nested object`);
      }
      for (const [key, nestedValue] of Object.entries(value)) {
        this.setField(field.type, at, key, nestedValue);
      }
      return;
    }

    this.#writeScalar(at, field.type, value);
  }

  /** Read one struct field, decoding nested structs and enums. */
  getField(structName, ptr, fieldName) {
    const field = this.layout.field(structName, fieldName);
    const at = ptr + field.offset;
    if (field.type === "pointer") return this.memory.view.getUint32(at, true);
    const nested = this.layout.types[field.type];
    if (nested && (nested.kind === TYPE_KIND.STRUCT || nested.kind === TYPE_KIND.UNION)) {
      return this.readStruct(field.type, at);
    }
    if (nested?.kind === TYPE_KIND.ENUM) {
      const raw = this.#readScalar(at, nested.underlying);
      return { value: raw, name: this.layout.enumName(field.type, raw) };
    }
    return this.#readScalar(at, field.type);
  }

  /** Decode a whole struct into a plain object, recursing into nested structs. */
  readStruct(structName, ptr) {
    const out = {};
    for (const [name, field] of Object.entries(this.layout.type(structName).fields ?? {})) {
      out[name] = this.getField(structName, ptr, name);
    }
    return out;
  }

  // --- scalars ------------------------------------------------------------

  #readScalar(offset, simpleType) {
    const view = this.memory.view;
    switch (simpleType) {
      case "u8":
        return view.getUint8(offset);
      case "i8":
        return view.getInt8(offset);
      case "u16":
        return view.getUint16(offset, true);
      case "i16":
        return view.getInt16(offset, true);
      case "u32":
        return view.getUint32(offset, true);
      case "i32":
        return view.getInt32(offset, true);
      case "u64":
        return view.getBigUint64(offset, true);
      case "i64":
        return view.getBigInt64(offset, true);
      case "bool":
        return view.getUint8(offset) !== 0;
      case "f32":
        return view.getFloat32(offset, true);
      case "f64":
        return view.getFloat64(offset, true);
      case "usize":
        return this.memory.readUsize(offset, this.usizeSize);
      default: {
        // Enum members carry their underlying integer type.
        const target = this.layout.types[simpleType];
        if (target?.kind === TYPE_KIND.ENUM) {
          return this.#readScalar(offset, target.underlying);
        }
        // "pointer" appears here when reached directly rather than as a
        // struct field; the manifest sizes it from pointer_size.
        if (simpleType === "pointer") return view.getUint32(offset, true);
        throw new Error(`unsupported ABI scalar type: ${simpleType}`);
      }
    }
  }

  #writeScalar(offset, simpleType, value) {
    const view = this.memory.view;
    switch (simpleType) {
      case "u8":
        view.setUint8(offset, value);
        break;
      case "i8":
        view.setInt8(offset, value);
        break;
      case "u16":
        view.setUint16(offset, value, true);
        break;
      case "i16":
        view.setInt16(offset, value, true);
        break;
      case "u32":
        view.setUint32(offset, value, true);
        break;
      case "i32":
        view.setInt32(offset, value, true);
        break;
      case "u64":
        view.setBigUint64(offset, BigInt(value), true);
        break;
      case "i64":
        view.setBigInt64(offset, BigInt(value), true);
        break;
      case "bool":
        view.setUint8(offset, value ? 1 : 0);
        break;
      case "f32":
        view.setFloat32(offset, value, true);
        break;
      case "f64":
        view.setFloat64(offset, value, true);
        break;
      case "usize":
        if (this.usizeSize === 4) view.setUint32(offset, value, true);
        else view.setBigUint64(offset, BigInt(value), true);
        break;
      default: {
        const target = this.layout.types[simpleType];
        if (target?.kind === TYPE_KIND.ENUM) {
          const resolved =
            typeof value === "string" ? this.layout.enumValue(simpleType, value) : value;
          this.#writeScalar(offset, target.underlying, resolved);
          break;
        }
        if (simpleType === "pointer") {
          view.setUint32(offset, value ?? 0, true);
          break;
        }
        throw new Error(`unsupported ABI scalar type: ${simpleType}`);
      }
    }
  }
}
