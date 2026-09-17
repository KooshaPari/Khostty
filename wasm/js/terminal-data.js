// Generated from include/ghostty/vt/terminal.h by
// wasm/tools/gen-terminal-data.mjs -- do not edit by hand.
//
// Maps each readable GhosttyTerminalData key to the out-parameter type that
// ghostty_terminal_get() writes, normalized to the type names used by the
// library's own ABI manifest. "value" is the enum value, which is what the
// bindings pass to the exported function.
//
// Regenerate: node wasm/tools/gen-terminal-data.mjs

/** GhosttyTerminalData member -> out parameter descriptor. */
export const TERMINAL_DATA = Object.freeze({
  COLS: Object.freeze({ value: 1, kind: "scalar", type: "u16" }),  // uint16_t *
  ROWS: Object.freeze({ value: 2, kind: "scalar", type: "u16" }),  // uint16_t *
  CURSOR_X: Object.freeze({ value: 3, kind: "scalar", type: "u16" }),  // uint16_t *
  CURSOR_Y: Object.freeze({ value: 4, kind: "scalar", type: "u16" }),  // uint16_t *
  CURSOR_PENDING_WRAP: Object.freeze({ value: 5, kind: "scalar", type: "bool" }),  // bool *
  ACTIVE_SCREEN: Object.freeze({ value: 6, kind: "named", type: "GhosttyTerminalScreen" }),  // GhosttyTerminalScreen *
  CURSOR_VISIBLE: Object.freeze({ value: 7, kind: "scalar", type: "bool" }),  // bool *
  KITTY_KEYBOARD_FLAGS: Object.freeze({ value: 8, kind: "scalar", type: "u8" }),  // GhosttyKittyKeyFlags * (uint8_t *)
  SCROLLBAR: Object.freeze({ value: 9, kind: "named", type: "GhosttyTerminalScrollbar" }),  // GhosttyTerminalScrollbar *
  CURSOR_STYLE: Object.freeze({ value: 10, kind: "named", type: "GhosttyStyle" }),  // GhosttyStyle *
  MOUSE_TRACKING: Object.freeze({ value: 11, kind: "scalar", type: "bool" }),  // bool *
  TITLE: Object.freeze({ value: 12, kind: "named", type: "GhosttyString" }),  // GhosttyString *
  PWD: Object.freeze({ value: 13, kind: "named", type: "GhosttyString" }),  // GhosttyString *
  TOTAL_ROWS: Object.freeze({ value: 14, kind: "scalar", type: "usize" }),  // size_t *
  SCROLLBACK_ROWS: Object.freeze({ value: 15, kind: "scalar", type: "usize" }),  // size_t *
  WIDTH_PX: Object.freeze({ value: 16, kind: "scalar", type: "u32" }),  // uint32_t *
  HEIGHT_PX: Object.freeze({ value: 17, kind: "scalar", type: "u32" }),  // uint32_t *
  COLOR_FOREGROUND: Object.freeze({ value: 18, kind: "named", type: "GhosttyColorRgb" }),  // GhosttyColorRgb *
  COLOR_BACKGROUND: Object.freeze({ value: 19, kind: "named", type: "GhosttyColorRgb" }),  // GhosttyColorRgb *
  COLOR_CURSOR: Object.freeze({ value: 20, kind: "named", type: "GhosttyColorRgb" }),  // GhosttyColorRgb *
  COLOR_PALETTE: Object.freeze({ value: 21, kind: "array", type: "GhosttyColorRgb", count: 256 }),  // GhosttyColorRgb[256] *
  COLOR_FOREGROUND_DEFAULT: Object.freeze({ value: 22, kind: "named", type: "GhosttyColorRgb" }),  // GhosttyColorRgb *
  COLOR_BACKGROUND_DEFAULT: Object.freeze({ value: 23, kind: "named", type: "GhosttyColorRgb" }),  // GhosttyColorRgb *
  COLOR_CURSOR_DEFAULT: Object.freeze({ value: 24, kind: "named", type: "GhosttyColorRgb" }),  // GhosttyColorRgb *
  COLOR_PALETTE_DEFAULT: Object.freeze({ value: 25, kind: "array", type: "GhosttyColorRgb", count: 256 }),  // GhosttyColorRgb[256] *
  KITTY_IMAGE_STORAGE_LIMIT: Object.freeze({ value: 26, kind: "scalar", type: "u64" }),  // uint64_t *
  KITTY_IMAGE_MEDIUM_FILE: Object.freeze({ value: 27, kind: "scalar", type: "bool" }),  // bool *
  KITTY_IMAGE_MEDIUM_TEMP_FILE: Object.freeze({ value: 28, kind: "named", type: "GhosttyString" }),  // GhosttyString *
  KITTY_IMAGE_MEDIUM_SHARED_MEM: Object.freeze({ value: 29, kind: "scalar", type: "bool" }),  // bool *
  KITTY_GRAPHICS: Object.freeze({ value: 30, kind: "named", type: "GhosttyKittyGraphics" }),  // GhosttyKittyGraphics *
  SELECTION: Object.freeze({ value: 31, kind: "named", type: "GhosttySelection" }),  // GhosttySelection *
  VIEWPORT_ACTIVE: Object.freeze({ value: 32, kind: "scalar", type: "bool" }),  // bool *
  VT_PROCESSING_ERROR: Object.freeze({ value: 33, kind: "scalar", type: "bool" }),  // bool *
  SCROLLBACK_MAX_BYTES: Object.freeze({ value: 34, kind: "scalar", type: "usize" }),  // size_t *
  SCROLLBACK_MAX_LINES: Object.freeze({ value: 35, kind: "scalar", type: "usize" }),  // size_t *
  CONTINUATION_MAX_BYTES: Object.freeze({ value: 36, kind: "scalar", type: "usize" }),  // size_t *
  MODE: Object.freeze({ value: 37, kind: "input-required", note: "requires a caller-initialized config" }),
  VT_GROUND: Object.freeze({ value: 38, kind: "scalar", type: "bool" }),  // bool *
  CURSOR_AT_PROMPT: Object.freeze({ value: 39, kind: "scalar", type: "bool" }),  // bool *
  CLIPBOARD_WRITE_MAX_BYTES: Object.freeze({ value: 40, kind: "scalar", type: "usize" }),  // size_t *
});
