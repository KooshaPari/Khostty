//! Cell cursor over a render-state row.
//!
//! [`Cells`] is a pre-allocated scratch handle that the library binds to one row
//! at a time. Reusing a single handle across rows and frames is the intended
//! pattern (see `example/c-vt-render/src/main.c`), so this type is owned by
//! [`RowIterator`](super::RowIterator) rather than created per row.
//!
//! # Validity
//!
//! Cell data points into the render state it was bound from. Upstream states the
//! rule plainly: "Cell data is only valid as long as the underlying render state
//! is not updated. It is unsafe to use cell data after updating the render
//! state." Here that is enforced by the type system rather than by comment:
//! [`Cells`] is only reachable through a [`RowIterator`](super::RowIterator)
//! borrowed from the render state, and updating the render state needs a mutable
//! borrow that the iterator holds.

use crate::color::Color;
use crate::error::{GhosttyError, Result};
use crate::ffi;
use crate::style::Style;
use core::ptr;

/// A pre-allocated row-cells handle.
pub struct Cells {
    raw: ffi::GhosttyRenderStateRowCells,
    _not_thread_safe: core::marker::PhantomData<*mut ()>,
}

impl Cells {
    /// Allocate a cells handle.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_render_state_row_cells_new` reports.
    pub(super) fn new() -> Result<Self> {
        let mut raw: ffi::GhosttyRenderStateRowCells = ptr::null_mut();
        // SAFETY: NULL selects the library's default allocator and `&mut raw` is
        // a valid out-parameter.
        let code = unsafe { ffi::ghostty_render_state_row_cells_new(ptr::null(), &mut raw) };
        GhosttyError::from_result(code)?;
        if raw.is_null() {
            return Err(GhosttyError::NullHandle);
        }
        Ok(Cells {
            raw,
            _not_thread_safe: core::marker::PhantomData,
        })
    }

    /// Advance to the next cell, returning `false` at the end of the row.
    ///
    /// Named `advance` rather than `next` because it is not an
    /// `Iterator::next`: it reports only whether a cell is available, and never
    /// yields a value.
    pub fn advance(&mut self) -> bool {
        // SAFETY: `self.raw` is a live cells handle.
        unsafe { ffi::ghostty_render_state_row_cells_next(self.raw) }
    }

    /// Select the cell at column `x` instead of iterating.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_render_state_row_cells_select` reports.
    pub fn select(&mut self, x: u16) -> Result<()> {
        // SAFETY: `self.raw` is live.
        let code = unsafe { ffi::ghostty_render_state_row_cells_select(self.raw, x) };
        GhosttyError::from_result(code)
    }

    /// Number of grapheme codepoints in the current cell, including the base
    /// codepoint. Zero means the cell has no text.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_render_state_row_cells_get` reports.
    pub fn grapheme_len(&self) -> Result<u32> {
        let mut out: u32 = 0;
        self.get_into(
            ffi::GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN,
            &mut out,
        )?;
        Ok(out)
    }

    /// The style of the current cell.
    ///
    /// The output is a sized struct, so it is pre-initialised with its `size`
    /// field the way `GHOSTTY_INIT_SIZED` does; the library uses that to detect
    /// the caller's ABI version.
    ///
    /// # Errors
    ///
    /// Whatever the query reports, plus [`GhosttyError::InvalidValue`] if the
    /// library's declared struct size disagrees with this crate's, which means
    /// the binding is stale.
    pub fn style(&self) -> Result<Style> {
        let mut out = sized_style();
        self.get_into(ffi::GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE, &mut out)?;
        let (style, declared_size) = Style::from_ffi(out);
        if declared_size != core::mem::size_of::<ffi::GhosttyStyle>() {
            return Err(GhosttyError::InvalidValue);
        }
        Ok(style)
    }

    /// Whether the cell has any explicit styling.
    ///
    /// Cheaper than [`Cells::style`] when a renderer only needs to know whether
    /// fetching the full style is worthwhile.
    ///
    /// # Errors
    ///
    /// Whatever the query reports.
    pub fn has_styling(&self) -> Result<bool> {
        self.get_bool(ffi::GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_HAS_STYLING)
    }

    /// Whether the cell falls inside the current selection.
    ///
    /// Renderers drawing spans can instead query the row-local range once via
    /// [`super::RowIterator::selection`].
    ///
    /// # Errors
    ///
    /// Whatever the query reports.
    pub fn selected(&self) -> Result<bool> {
        self.get_bool(ffi::GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_SELECTED)
    }

    /// The resolved background colour of the cell.
    ///
    /// Returns `Ok(None)` when the cell has no background colour of its own, in
    /// which case the caller should use the terminal background. Options are not
    /// flattened here, so `None` genuinely means "unset".
    ///
    /// # Errors
    ///
    /// Whatever the query reports.
    pub fn background(&self) -> Result<Option<Color>> {
        self.get_color(ffi::GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_BG_COLOR)
    }

    /// The resolved foreground colour of the cell.
    ///
    /// Palette indices are resolved by the library. Bold colour handling is not
    /// applied, matching the C contract; the caller applies bold separately.
    ///
    /// # Errors
    ///
    /// Whatever the query reports.
    pub fn foreground(&self) -> Result<Option<Color>> {
        self.get_color(ffi::GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_FG_COLOR)
    }

    /// The grapheme codepoints of the current cell.
    ///
    /// The base codepoint comes first, followed by any combining codepoints.
    /// Querying `GRAPHEMES_LEN` first and then filling exactly that many slots
    /// means the library never writes past this buffer.
    ///
    /// # Errors
    ///
    /// Whatever the queries report.
    pub fn graphemes(&self) -> Result<Vec<u32>> {
        let len = self.grapheme_len()? as usize;
        if len == 0 {
            return Ok(Vec::new());
        }
        let mut buf = vec![0u32; len];
        self.get_ptr(
            ffi::GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF,
            buf.as_mut_ptr(),
        )?;
        Ok(buf)
    }

    /// The current cell's full grapheme cluster as UTF-8.
    ///
    /// Uses the documented `GhosttyBuffer` protocol: a null buffer with zero
    /// capacity reports the required size in `len`, then a correctly sized buffer
    /// receives the bytes. Returns an empty string for a cell with no text.
    ///
    /// # Errors
    ///
    /// Anything other than the expected `OUT_OF_SPACE` size query.
    pub fn graphemes_utf8(&self) -> Result<String> {
        let mut query = ffi::GhosttyBuffer {
            ptr: ptr::null_mut(),
            cap: 0,
            len: 0,
        };
        match self.get_into(
            ffi::GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_UTF8,
            &mut query,
        ) {
            // The documented size query: a null buffer with zero capacity asks
            // for the required length and reports OUT_OF_SPACE.
            Ok(()) | Err(GhosttyError::OutOfSpace { .. }) => {}
            Err(err) => return Err(err),
        }
        if query.len == 0 {
            return Ok(String::new());
        }

        let mut buf = vec![0u8; query.len];
        let mut fill = ffi::GhosttyBuffer {
            ptr: buf.as_mut_ptr(),
            cap: buf.len(),
            len: 0,
        };
        self.get_into(
            ffi::GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_UTF8,
            &mut fill,
        )?;
        if fill.len > buf.len() {
            // The library over-reported; refuse rather than read past the Vec.
            return Err(GhosttyError::InvalidValue);
        }
        buf.truncate(fill.len);
        Ok(String::from_utf8_lossy(&buf).into_owned())
    }

    /// The raw cell value.
    ///
    /// Prefer the typed accessors above: upstream warns that the bit layout of a
    /// raw cell is not ABI-protected, and that callers should read the layout
    /// from `ghostty_type_json` or use `ghostty_cell_get`. This is exposed for
    /// embedders that deliberately trade that stability for fewer FFI calls.
    ///
    /// # Errors
    ///
    /// Whatever the query reports.
    pub fn raw(&self) -> Result<ffi::GhosttyCell> {
        let mut out: ffi::GhosttyCell = 0;
        self.get_into(ffi::GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW, &mut out)?;
        Ok(out)
    }

    /// Raw handle, for passing to sibling C APIs.
    pub fn as_raw(&self) -> ffi::GhosttyRenderStateRowCells {
        self.raw
    }

    /// Address of the stored handle.
    ///
    /// Some C entry points take the *address* of a pre-allocated handle so they
    /// can populate it. Exposing the address of our own field, rather than a
    /// copy, means a rewritten handle stays observable.
    pub(super) fn raw_slot(&mut self) -> *mut ffi::GhosttyRenderStateRowCells {
        &mut self.raw
    }

    // ---- Private plumbing --------------------------------------------------

    fn get_into<T>(&self, key: ffi::GhosttyRenderStateRowCellsData, out: &mut T) -> Result<()> {
        self.get_ptr(key, out as *mut T)
    }

    fn get_ptr<T>(&self, key: ffi::GhosttyRenderStateRowCellsData, out: *mut T) -> Result<()> {
        // SAFETY: `self.raw` is live and `out` points at storage matching the
        // key's documented output type, sized by the caller.
        let code = unsafe { ffi::ghostty_render_state_row_cells_get(self.raw, key, out.cast()) };
        GhosttyError::from_result(code)
    }

    fn get_bool(&self, key: ffi::GhosttyRenderStateRowCellsData) -> Result<bool> {
        let mut out: u8 = 0;
        self.get_into(key, &mut out)?;
        Ok(out != 0)
    }

    /// Read a colour, mapping "no explicit colour" to `None`.
    ///
    /// The C contract reports `GHOSTTY_INVALID_VALUE` for a cell with no colour
    /// of its own, which is not a failure of the caller's request.
    fn get_color(&self, key: ffi::GhosttyRenderStateRowCellsData) -> Result<Option<Color>> {
        let mut out = ffi::GhosttyColorRgb { r: 0, g: 0, b: 0 };
        match self.get_into(key, &mut out) {
            Ok(()) => Ok(Some(Color::from_ffi(out))),
            Err(GhosttyError::InvalidValue) => Ok(None),
            Err(err) => Err(err),
        }
    }
}

impl Drop for Cells {
    fn drop(&mut self) {
        if self.raw.is_null() {
            return;
        }
        // SAFETY: `self.raw` is a live handle owned solely by `self`.
        unsafe { ffi::ghostty_render_state_row_cells_free(self.raw) };
        self.raw = ptr::null_mut();
    }
}

/// A `GhosttyStyle` with its `size` field set, mirroring `GHOSTTY_INIT_SIZED`.
fn sized_style() -> ffi::GhosttyStyle {
    Style::default().to_ffi()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sized_style_declares_its_own_size() {
        let raw = sized_style();
        assert_eq!(raw.size, core::mem::size_of::<ffi::GhosttyStyle>());
    }
}
