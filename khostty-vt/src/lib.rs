//! Safe Rust wrappers for `libghostty-vt`, the virtual terminal emulator
//! library extracted from [Ghostty](https://ghostty.org).
//!
//! This crate is the Rust half of the Khostty polyglot FFI gate (Deep WBS G5).
//! The C library is linked from a prebuilt `libghostty-vt`; see `build.rs` for
//! the search order and the `GHOSTTY_VT_LIB_DIR` / `GHOSTTY_VT_INCLUDE_DIR`
//! overrides.
//!
//! ## Layout
//!
//! | Module  | Contents                                                       |
//! |---------|----------------------------------------------------------------|
//! | [`ffi`] | Raw `extern "C"` declarations, generated from the C headers    |
//!
//! The safe RAII wrappers (`terminal`, `snapshot`, `render`, `search`, `key`,
//! `mouse`, `error`) are added incrementally on top of these raw bindings.

pub mod ffi;
