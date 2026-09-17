//! Render state: an incremental, frame-oriented view of a terminal.
//!
//! [`RenderState`] mirrors `GhosttyRenderState`. It holds a snapshot of
//! everything a renderer needs for one frame, so the renderer never walks
//! terminal internals: call [`RenderState::update`], check [`RenderState::dirty`],
//! iterate dirty rows, and clear dirty flags with [`RenderState::clean`].
//!
//! # Validity, enforced by the borrow checker
//!
//! Row and cell data point into the render state that produced them. Upstream
//! states the rule as a comment; here it is a compile-time guarantee:
//!
//! * [`RenderState::rows`] returns a [`RowIterator`] that borrows the render
//!   state immutably.
//! * [`RenderState::update`], [`RenderState::begin_update`], and
//!   [`RenderState::clean`] all need `&mut self`.
//!
//! So a row iterator cannot be held across an update, which is exactly the
//! hazard the C header warns about.
//!
//! # Sized structs
//!
//! Two queries (`..._DATA_CURSOR` and `..._DATA_COLORS`) return structs whose
//! first field is a `size` the caller must pre-initialise, the way
//! `GHOSTTY_INIT_SIZED` does. The library uses it to detect the caller's ABI
//! version. [`RenderState::cursor`] and [`RenderState::colors`] do that
//! internally and reject the result if the library's declared size disagrees
//! with this crate's, so a stale binding fails loudly instead of silently
//! mixing layouts.

pub mod cells;
pub mod row;
pub mod types;

pub use cells::Cells;
pub use row::RowIterator;
pub use types::{Colors, Cursor, CursorVisualStyle, Dirty};

use crate::color::Color;
use crate::error::{GhosttyError, Result};
use crate::ffi;
use crate::terminal::Terminal;
use core::ffi::c_void;
use core::marker::PhantomData;
use core::ptr;

/// An incremental render state for a terminal.
///
/// Dropping this value calls `ghostty_render_state_free`. Row and cell data
/// derived from it must not outlive it, which the borrow checker enforces via
/// [`RowIterator`].
pub struct RenderState {
    raw: ffi::GhosttyRenderState,
    _not_thread_safe: PhantomData<*mut ()>,
}

impl RenderState {
    /// Allocate a render state.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_render_state_new` reports.
    pub fn new() -> Result<Self> {
        let mut raw: ffi::GhosttyRenderState = ptr::null_mut();
        // SAFETY: NULL selects the library's default allocator and `&mut raw` is
        // a valid out-parameter.
        let code = unsafe { ffi::ghostty_render_state_new(ptr::null(), &mut raw) };
        GhosttyError::from_result(code)?;
        if raw.is_null() {
            return Err(GhosttyError::NullHandle);
        }
        Ok(RenderState {
            raw,
            _not_thread_safe: PhantomData,
        })
    }

    /// Refresh the render state from `terminal`.
    ///
    /// Invalidates any row or cell data previously read out of this state; the
    /// `&mut self` borrow is what makes that a compile error rather than a
    /// dangling read.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_render_state_update` reports.
    pub fn update(&mut self, terminal: &Terminal) -> Result<()> {
        // SAFETY: both handles are live and the update finishes within this call.
        let code = unsafe { ffi::ghostty_render_state_update(self.raw, terminal.as_raw()) };
        GhosttyError::from_result(code)
    }

    /// Begin an update, for renderers that want to interleave work with the
    /// refresh.
    ///
    /// Pair every `begin_update` with exactly one [`RenderState::end_update`]. A
    /// forgotten `end_update` leaves the state mid-update; upstream returns an
    /// error for an unbalanced `begin_update`.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_render_state_begin_update` reports.
    pub fn begin_update(&mut self, terminal: &Terminal) -> Result<()> {
        // SAFETY: both handles are live.
        let code = unsafe { ffi::ghostty_render_state_begin_update(self.raw, terminal.as_raw()) };
        GhosttyError::from_result(code)
    }

    /// Finish an update started with [`RenderState::begin_update`].
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_render_state_end_update` reports.
    pub fn end_update(&mut self) -> Result<()> {
        // SAFETY: `self.raw` is live.
        let code = unsafe { ffi::ghostty_render_state_end_update(self.raw) };
        GhosttyError::from_result(code)
    }

    /// Clear global and per-row dirty state after a complete frame is drawn.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_render_state_clean` reports.
    pub fn clean(&mut self) -> Result<()> {
        // SAFETY: `self.raw` is live.
        let code = unsafe { ffi::ghostty_render_state_clean(self.raw) };
        GhosttyError::from_result(code)
    }

    /// Viewport width in cells.
    ///
    /// # Errors
    ///
    /// Whatever the query reports.
    pub fn cols(&self) -> Result<u16> {
        self.get_scalar(ffi::GHOSTTY_RENDER_STATE_DATA_COLS)
    }

    /// Viewport height in cells.
    ///
    /// # Errors
    ///
    /// Whatever the query reports.
    pub fn rows_count(&self) -> Result<u16> {
        self.get_scalar(ffi::GHOSTTY_RENDER_STATE_DATA_ROWS)
    }

    /// How much of the frame needs redrawing.
    ///
    /// # Errors
    ///
    /// Whatever the query reports.
    pub fn dirty(&self) -> Result<Dirty> {
        Ok(Dirty::from_raw(
            self.get_scalar::<i32>(ffi::GHOSTTY_RENDER_STATE_DATA_DIRTY)?,
        ))
    }

    /// Set the global dirty state.
    ///
    /// Renderers occasionally need to force a full redraw, for example after a
    /// font change.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_render_state_set` reports.
    pub fn set_dirty(&mut self, dirty: Dirty) -> Result<()> {
        let value = dirty.to_raw();
        // SAFETY: `self.raw` is live and `value` matches the option's documented
        // input type (`GhosttyRenderStateDirty`).
        let code = unsafe {
            ffi::ghostty_render_state_set(
                self.raw,
                ffi::GHOSTTY_RENDER_STATE_OPTION_DIRTY,
                (&value as *const ffi::GhosttyRenderStateDirty).cast::<c_void>(),
            )
        };
        GhosttyError::from_result(code)
    }

    /// Frame colours, including the palette needed to resolve indexed colours.
    ///
    /// # Errors
    ///
    /// Whatever the query reports, plus [`GhosttyError::InvalidValue`] if the
    /// library's declared struct size disagrees with this crate's.
    pub fn colors(&self) -> Result<Colors> {
        let mut raw = sized_colors();
        self.get_into(ffi::GHOSTTY_RENDER_STATE_DATA_COLORS, &mut raw)?;
        check_declared_size(
            raw.size,
            core::mem::size_of::<ffi::GhosttyRenderStateColors>(),
        )?;
        Ok(Colors {
            background: Color::from_ffi(raw.background),
            foreground: Color::from_ffi(raw.foreground),
            cursor: Color::from_ffi(raw.cursor),
            cursor_has_value: raw.cursor_has_value,
            palette: raw.palette.map(Color::from_ffi),
        })
    }

    /// Cursor state for the frame.
    ///
    /// # Errors
    ///
    /// Whatever the query reports, plus [`GhosttyError::InvalidValue`] if the
    /// library's declared struct size disagrees with this crate's.
    pub fn cursor(&self) -> Result<Cursor> {
        let mut raw = sized_cursor();
        self.get_into(ffi::GHOSTTY_RENDER_STATE_DATA_CURSOR, &mut raw)?;
        check_declared_size(
            raw.size,
            core::mem::size_of::<ffi::GhosttyRenderStateCursor>(),
        )?;
        Ok(Cursor {
            viewport_has_value: raw.viewport_has_value,
            viewport_x: raw.viewport_x,
            viewport_y: raw.viewport_y,
            wide_tail: raw.wide_tail,
            visible: raw.visible,
            blinking: raw.blinking,
            password_input: raw.password_input,
            visual_style: CursorVisualStyle::from_raw(raw.visual_style),
        })
    }

    /// The background colour.
    ///
    /// Prefer [`RenderState::colors`], which reads background, foreground,
    /// cursor, and the palette in one call.
    ///
    /// # Errors
    ///
    /// Whatever the query reports.
    pub fn background(&self) -> Result<Color> {
        self.get_color(ffi::GHOSTTY_RENDER_STATE_DATA_COLOR_BACKGROUND)
    }

    /// The foreground colour.
    ///
    /// # Errors
    ///
    /// Whatever the query reports.
    pub fn foreground(&self) -> Result<Color> {
        self.get_color(ffi::GHOSTTY_RENDER_STATE_DATA_COLOR_FOREGROUND)
    }

    /// The explicit cursor colour, if the terminal set one.
    ///
    /// The C API returns `GHOSTTY_INVALID_VALUE` when no explicit cursor colour
    /// is set, which is a normal answer rather than a failure, so it maps to
    /// `None`.
    ///
    /// # Errors
    ///
    /// Whatever the query reports other than the missing-value case.
    pub fn cursor_color(&self) -> Result<Option<Color>> {
        let mut raw = ffi::GhosttyColorRgb { r: 0, g: 0, b: 0 };
        match self.get_into(ffi::GHOSTTY_RENDER_STATE_DATA_COLOR_CURSOR, &mut raw) {
            Ok(()) => Ok(Some(Color::from_ffi(raw))),
            Err(GhosttyError::InvalidValue) => Ok(None),
            Err(err) => Err(err),
        }
    }

    /// The active 256-entry palette.
    ///
    /// # Errors
    ///
    /// Whatever the query reports.
    pub fn palette(&self) -> Result<[Color; 256]> {
        let mut raw = [ffi::GhosttyColorRgb { r: 0, g: 0, b: 0 }; 256];
        self.get_into(ffi::GHOSTTY_RENDER_STATE_DATA_COLOR_PALETTE, &mut raw)?;
        Ok(raw.map(Color::from_ffi))
    }

    /// Iterate the rows of the current frame.
    ///
    /// The iterator borrows this render state; updating the state, cleaning it,
    /// or setting a dirty flag all require `&mut self`, so stale row reads are a
    /// compile error.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_render_state_row_iterator_new` or the iterator-filling
    /// query reports.
    pub fn rows(&self) -> Result<RowIterator<'_>> {
        RowIterator::new(self)
    }

    /// Raw handle, for passing to sibling C APIs.
    pub fn as_raw(&self) -> ffi::GhosttyRenderState {
        self.raw
    }

    // ---- Private plumbing --------------------------------------------------

    fn get_into<T>(&self, key: ffi::GhosttyRenderStateData, out: &mut T) -> Result<()> {
        // SAFETY: `self.raw` is live and `out` points at a `T` matching the key's
        // documented output type.
        let code = unsafe {
            ffi::ghostty_render_state_get(self.raw, key, (out as *mut T).cast::<c_void>())
        };
        GhosttyError::from_result(code)
    }

    fn get_scalar<T: Copy + Default>(&self, key: ffi::GhosttyRenderStateData) -> Result<T> {
        let mut out = T::default();
        self.get_into(key, &mut out)?;
        Ok(out)
    }

    fn get_color(&self, key: ffi::GhosttyRenderStateData) -> Result<Color> {
        let mut raw = ffi::GhosttyColorRgb { r: 0, g: 0, b: 0 };
        self.get_into(key, &mut raw)?;
        Ok(Color::from_ffi(raw))
    }
}

impl Drop for RenderState {
    fn drop(&mut self) {
        if self.raw.is_null() {
            return;
        }
        // SAFETY: `self.raw` is a live handle owned solely by `self`.
        unsafe { ffi::ghostty_render_state_free(self.raw) };
        self.raw = ptr::null_mut();
    }
}

/// A zeroed value of a sized C struct, with its `size` field set.
///
/// This is the Rust spelling of `GHOSTTY_INIT_SIZED`. The library reads `size` to
/// decide how much of the struct the caller understands, so *every* query that
/// returns one of these structs must set it: passing a zeroed struct without a
/// size is how a query turns into `GHOSTTY_INVALID_VALUE`.
///
/// Every field of the render-state sized structs is an integer, a `bool`, or a
/// nested POD struct, so an all-zero bit pattern is a valid value for each.
pub(super) fn sized_zeroed<T: Copy>(size: usize) -> T {
    let mut out: T = {
        // SAFETY: as described above.
        unsafe { core::mem::zeroed() }
    };
    // `T` is one of the render-state sized structs, whose first field is always
    // `size_t size`. Writing through a pointer to the head of the struct is the
    // same thing `GHOSTTY_INIT_SIZED` does in C.
    //
    // SAFETY: `out` is a live, properly aligned `T`, and the first field of
    // every `T` this is used with is `size: usize`, matching the C layout.
    unsafe { core::ptr::write(core::ptr::addr_of_mut!(out).cast::<usize>(), size) };
    out
}

/// A sized `GhosttyRenderStateColors` ready to hand to the library.
pub(super) fn sized_colors() -> ffi::GhosttyRenderStateColors {
    sized_zeroed(core::mem::size_of::<ffi::GhosttyRenderStateColors>())
}

/// A sized `GhosttyRenderStateCursor` ready to hand to the library.
pub(super) fn sized_cursor() -> ffi::GhosttyRenderStateCursor {
    sized_zeroed(core::mem::size_of::<ffi::GhosttyRenderStateCursor>())
}

/// A sized `GhosttyRenderStateRowSelection` ready to hand to the library.
pub(super) fn sized_selection() -> ffi::GhosttyRenderStateRowSelection {
    sized_zeroed(core::mem::size_of::<ffi::GhosttyRenderStateRowSelection>())
}

/// Reject a sized-struct result whose declared size is not ours.
///
/// A mismatch means the library and this binding disagree about the struct
/// layout, so the fields would be read at the wrong offsets.
pub(super) fn check_declared_size(declared: usize, expected: usize) -> Result<()> {
    if declared != expected {
        return Err(GhosttyError::InvalidValue);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sized_structs_declare_their_own_size() {
        // Regression guard: handing the library a zeroed struct with `size == 0`
        // makes every query return GHOSTTY_INVALID_VALUE.
        let colors = sized_colors();
        assert_eq!(
            colors.size,
            core::mem::size_of::<ffi::GhosttyRenderStateColors>()
        );
        let cursor = sized_cursor();
        assert_eq!(
            cursor.size,
            core::mem::size_of::<ffi::GhosttyRenderStateCursor>()
        );

        // The other fields stay zeroed.
        assert!(!colors.cursor_has_value);
        assert!(!cursor.visible);
        assert_eq!(cursor.viewport_x, 0);
    }

    #[test]
    fn size_mismatch_is_rejected_rather_than_read_at_wrong_offsets() {
        assert!(check_declared_size(24, 24).is_ok());
        assert_eq!(check_declared_size(23, 24), Err(GhosttyError::InvalidValue));
    }
}
