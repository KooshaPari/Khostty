//! Row iteration over a frame.
//!
//! [`RowIterator`] mirrors `GhosttyRenderStateRowIterator`. Upstream populates a
//! pre-allocated iterator from the render state, then the caller walks rows and
//! reads per-row data. The iterator is bound to one render state, and the row
//! data it exposes points into that state, so it borrows the render state for its
//! whole lifetime. That is what stops a renderer from reading stale rows after an
//! update.
//!
//! The reusable [`Cells`] handle the library expects is owned here rather than by
//! the caller, because upstream's intended pattern is one cells handle bound
//! per row across an entire frame.

use super::cells::Cells;
use super::{sized_selection, RenderState};
use crate::error::{GhosttyError, Result};
use crate::ffi;
use core::ffi::c_void;
use core::marker::PhantomData;
use core::ptr;

/// Iterates the rows of a render state, exposing per-row data and cells.
///
/// Created by [`RenderState::rows`]. Owns the reusable cells handle the library
/// expects to be bound per row.
pub struct RowIterator<'a> {
    raw: ffi::GhosttyRenderStateRowIterator,
    cells: Cells,
    _state: PhantomData<&'a RenderState>,
}

impl<'a> RowIterator<'a> {
    pub(super) fn new(state: &'a RenderState) -> Result<Self> {
        let mut raw: ffi::GhosttyRenderStateRowIterator = ptr::null_mut();
        // SAFETY: NULL selects the library's default allocator and `&mut raw` is
        // a valid out-parameter.
        let code = unsafe { ffi::ghostty_render_state_row_iterator_new(ptr::null(), &mut raw) };
        GhosttyError::from_result(code)?;
        if raw.is_null() {
            return Err(GhosttyError::NullHandle);
        }

        // Bind the iterator to the render state. Note the out-parameter here is
        // the iterator handle itself, not a pointer to new data: upstream
        // populates the pre-allocated iterator.
        // SAFETY: `state.raw` is live and borrowed for `'a`; `&mut raw` points at
        // the handle the library will populate.
        let code = unsafe {
            ffi::ghostty_render_state_get(
                state.raw,
                ffi::GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR,
                (&mut raw as *mut ffi::GhosttyRenderStateRowIterator).cast::<c_void>(),
            )
        };
        GhosttyError::from_result(code)?;

        Ok(RowIterator {
            raw,
            cells: Cells::new()?,
            _state: PhantomData,
        })
    }

    /// Advance to the next row.
    ///
    /// Returns `true` while rows remain. The C call reports only a `bool`, not the
    /// row index; for a known index use [`RowIterator::next_dirty`].
    ///
    /// Named `advance` rather than `next` because it is not an `Iterator::next`.
    pub fn advance(&mut self) -> bool {
        // SAFETY: `self.raw` is a live iterator handle.
        unsafe { ffi::ghostty_render_state_row_iterator_next(self.raw) }
    }

    /// Advance to the next dirty row, returning its index.
    ///
    /// This is the incremental path: pair it with [`RenderState::clean`] once the
    /// frame has been drawn. Returns `None` when no dirty rows remain.
    pub fn next_dirty(&mut self) -> Option<u16> {
        let mut y: u16 = 0;
        // SAFETY: `self.raw` is live and `&mut y` is a valid out-parameter.
        let more = unsafe { ffi::ghostty_render_state_row_iterator_next_dirty(self.raw, &mut y) };
        if more {
            Some(y)
        } else {
            None
        }
    }

    /// Whether the current row is dirty.
    ///
    /// # Errors
    ///
    /// Whatever the query reports.
    pub fn dirty(&self) -> Result<bool> {
        self.get_bool(ffi::GHOSTTY_RENDER_STATE_ROW_DATA_DIRTY)
    }

    /// The raw row value for the current row.
    ///
    /// As with raw cells, upstream does not protect the bit layout by ABI, so
    /// typed accessors are preferred where they exist.
    ///
    /// # Errors
    ///
    /// Whatever the query reports.
    pub fn raw(&self) -> Result<ffi::GhosttyRow> {
        let mut out: ffi::GhosttyRow = 0;
        self.get_into(ffi::GHOSTTY_RENDER_STATE_ROW_DATA_RAW, &mut out)?;
        Ok(out)
    }

    /// The row-local selection range for the current row, if any.
    ///
    /// Columns are inclusive. Rows without a selection report `GHOSTTY_NO_VALUE`,
    /// which maps to `Ok(None)`. Renderers that can draw spans should use this
    /// once per row instead of querying per-cell selection state.
    ///
    /// # Errors
    ///
    /// Whatever the query reports other than the missing-selection case.
    pub fn selection(&self) -> Result<Option<(u16, u16)>> {
        let mut out = sized_selection();
        match self.get_into(ffi::GHOSTTY_RENDER_STATE_ROW_DATA_SELECTION, &mut out) {
            Ok(()) => Ok(Some((out.start_x, out.end_x))),
            Err(err) if err.is_empty_value() => Ok(None),
            Err(err) => Err(err),
        }
    }

    /// Bind the reusable cells handle to the current row and return it.
    ///
    /// The returned reference borrows this iterator, so the cells cannot outlive
    /// the row they belong to.
    ///
    /// # Errors
    ///
    /// Whatever the binding query reports.
    pub fn bind_cells(&mut self) -> Result<&mut Cells> {
        // Upstream's pattern passes the address of the pre-allocated handle so the
        // library can populate it (`ghostty_render_state_row_get(row_iter,
        // GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, &cells)`). Handing over the address
        // of our stored field, rather than a copy, means a rewritten handle would
        // still be observed instead of silently leaking the old one.
        let slot = self.cells.raw_slot();
        let before = self.cells.as_raw();
        // SAFETY: `self.raw` is live, and `slot` points at the live cells handle
        // stored in `self.cells`.
        let code = unsafe {
            ffi::ghostty_render_state_row_get(
                self.raw,
                ffi::GHOSTTY_RENDER_STATE_ROW_DATA_CELLS,
                slot.cast::<c_void>(),
            )
        };
        GhosttyError::from_result(code)?;
        if self.cells.as_raw() != before {
            // The library replaced our handle. We no longer know who owns the
            // previous allocation, so refuse rather than risk a leak or a double
            // free. This never happens with the documented API shape.
            return Err(GhosttyError::InvalidValue);
        }
        Ok(&mut self.cells)
    }

    /// Raw handle, for passing to sibling C APIs.
    pub fn as_raw(&self) -> ffi::GhosttyRenderStateRowIterator {
        self.raw
    }

    fn get_into<T>(&self, key: ffi::GhosttyRenderStateRowData, out: &mut T) -> Result<()> {
        // SAFETY: `self.raw` is live and `out` matches the key's output type.
        let code = unsafe {
            ffi::ghostty_render_state_row_get(self.raw, key, (out as *mut T).cast::<c_void>())
        };
        GhosttyError::from_result(code)
    }

    fn get_bool(&self, key: ffi::GhosttyRenderStateRowData) -> Result<bool> {
        let mut out: u8 = 0;
        self.get_into(key, &mut out)?;
        Ok(out != 0)
    }
}

impl Drop for RowIterator<'_> {
    fn drop(&mut self) {
        if self.raw.is_null() {
            return;
        }
        // SAFETY: `self.raw` is a live handle owned solely by `self`. `cells` is a
        // separate allocation and is freed by its own `Drop`.
        unsafe { ffi::ghostty_render_state_row_iterator_free(self.raw) };
        self.raw = ptr::null_mut();
    }
}
