//! Safe Rust wrappers for `libghostty-vt`, the virtual terminal emulator library
//! extracted from [Ghostty](https://ghostty.org).
//!
//! This crate is the Rust half of Khostty's polyglot FFI gate. It parses terminal
//! escape sequences, exposes the resulting screen, persists and restores terminal
//! state, searches scrollback, and turns input events into the escape sequences a
//! program under the terminal expects, all without `unsafe` in application code.
//!
//! The prose documentation lives in `README.md` next to this file; what follows is
//! the map you need to navigate the API.
//!
//! # Modules
//!
//! | Module | Contents |
//! |--------|----------|
//! | [`ffi`] | Raw `extern "C"` declarations, generated from the C headers |
//! | [`error`] | [`GhosttyError`], mapping every `GhosttyResult` code |
//! | [`sys`] | Allocator integration, [`OwnedBuffer`](sys::OwnedBuffer), the two-pass buffer helper |
//! | [`color`] | [`Color`], mirroring `GhosttyColorRgb` |
//! | [`style`] | [`Style`], [`StyleColor`], [`Underline`], mirroring `GhosttyStyle` |
//! | [`selection`] | [`GridRef`], [`Selection`], the value types search reports |
//! | [`terminal`] | [`Terminal`]: VT input, state queries, options, event callbacks |
//! | [`render`] | [`RenderState`], `RowIterator`, `Cells` |
//! | [`snapshot`] | Snapshot encoding and [`SnapshotDecoder`] |
//! | [`search`] | [`Search`]: needle, feed/tick/run, matches as selections |
//! | [`key`] | [`KeyEncoder`], [`KeyEvent`], [`Mods`], [`Key`] |
//! | [`mouse`] | [`MouseEncoder`], [`MouseEvent`] and friends |
//!
//! # Getting started
//!
//! The entry point is [`Terminal`]. Bytes go in, terminal state comes out:
//!
//! ```no_run
//! use khostty_vt::Terminal;
//!
//! # fn main() -> Result<(), khostty_vt::GhosttyError> {
//! let mut term = Terminal::new(80, 24)?;
//! term.vt_write(b"$ echo hi\r\nhi\r\n$ ");
//!
//! assert_eq!(term.cols()?, 80);
//! assert_eq!(term.cursor_position()?, (2, 4));
//! assert!(term.vt_ground()?);
//! # Ok(())
//! # }
//! ```
//!
//! The example above is `no_run` because every constructor here links the native
//! library, which a docs-only environment may not have. The runnable version is
//! `examples/screen_dump.rs`, and the behaviour is covered by the integration
//! tests.
//!
//! Reading the screen means walking the render state, because that is where a
//! frame's rows and cells live:
//!
//! ```no_run
//! use khostty_vt::{render::RenderState, Terminal};
//!
//! # fn read(term: &Terminal) -> Result<String, khostty_vt::GhosttyError> {
//! let mut state = RenderState::new()?;
//! state.update(term)?;
//!
//! let mut text = String::new();
//! let mut rows = state.rows()?;
//! while rows.advance() {
//!     let cells = rows.bind_cells()?;
//!     while cells.advance() {
//!         if cells.grapheme_len()? > 0 {
//!             text.push_str(&cells.graphemes_utf8()?);
//!         }
//!     }
//!     text.push('\n');
//! }
//! # Ok(text)
//! # }
//! ```
//!
//! # What the wrappers guarantee
//!
//! * **RAII.** Every owned handle frees itself in `Drop`, through the library's own
//!   free function. Library-allocated bytes go back through `ghostty_free` with the
//!   allocator that produced them, never through the C `free()`.
//! * **`unsafe` is confined.** Raw calls live in [`ffi`] or at a thin wrapper call
//!   site, each with a `// SAFETY:` comment naming its invariant.
//! * **Lifetime rules are typed.** Row data cannot outlive a render-state update,
//!   a snapshot's source bytes cannot outlive its decoder, a decoded terminal
//!   cannot outlive the history replay, and terminal-touching search calls need a
//!   `&Terminal`. See `README.md` for the table mapping each C rule to the Rust
//!   construct that enforces it.
//! * **Callbacks cannot unwind into C.** Effect closures have their panics caught
//!   at the boundary, and the handle types are deliberately neither [`Send`] nor
//!   [`Sync`] because upstream documents no thread-safety.
//!
//! # Non-FFI extras
//!
//! A few pieces work without the native library at all, which is why they can be
//! shown as runnable examples:
//!
//! ```
//! use khostty_vt::key::Mods;
//!
//! let mods = Mods::CTRL | Mods::SHIFT;
//! assert!(mods.contains(Mods::CTRL));
//! assert!(!mods.is_empty());
//! ```
//!
//! ```
//! use khostty_vt::{ffi, GhosttyError};
//!
//! // C result codes map onto a Rust error type, preserving codes this crate
//! // does not know so a newer library stays representable.
//! assert!(GhosttyError::from_result(ffi::GHOSTTY_SUCCESS).is_ok());
//! assert_eq!(
//!     GhosttyError::from_result(ffi::GHOSTTY_REJECTED),
//!     Err(GhosttyError::Rejected)
//! );
//! assert!(matches!(
//!     GhosttyError::from_result(-99),
//!     Err(GhosttyError::Unknown { code: -99 })
//! ));
//! ```

pub mod color;
pub mod error;
pub mod ffi;
pub mod key;
pub mod mouse;
pub mod render;
pub mod search;
pub mod selection;
pub mod snapshot;
pub mod style;
pub mod sys;
pub mod terminal;

pub use color::Color;
pub use error::{GhosttyError, Result};
pub use key::{Key, KeyEncoder, KeyEvent, Mods};
pub use mouse::{MouseEncoder, MouseEvent};
pub use render::{Dirty, RenderState};
pub use search::{Search, SearchStatus};
pub use selection::{GridRef, Selection};
pub use snapshot::SnapshotDecoder;
pub use snapshot::{encode as encode_snapshot, encode_alloc, encode_to};
pub use style::{Style, StyleColor, Underline};
pub use terminal::{Terminal, Viewport};
