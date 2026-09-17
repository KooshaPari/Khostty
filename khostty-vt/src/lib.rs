//! Safe Rust wrappers for `libghostty-vt`, the virtual terminal emulator
//! library extracted from [Ghostty](https://ghostty.org).
//!
//! This crate is the Rust half of the Khostty polyglot FFI gate (Deep WBS G5).
//! The C library is linked from a prebuilt `libghostty-vt`; see `build.rs` for
//! the search order and the `GHOSTTY_VT_LIB_DIR` / `GHOSTTY_VT_INCLUDE_DIR`
//! overrides.
//!
//! The safe RAII wrappers (`terminal`, `snapshot`, `render`, `search`, `key`,
//! `mouse`, `error`) are added incrementally on top of the raw bindings.

/// Number of `GHOSTTY_API` functions this crate is scaffolded to wrap.
pub const WRAPPED_FUNCTION_TARGET: usize = 198;
