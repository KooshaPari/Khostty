//! Grid references and selections.
//!
//! A [`GridRef`] is a handle to one cell in a terminal's grid. A [`Selection`]
//! is a rectangle-free span between two grid references, and it is also how the
//! search API reports matches: `include/ghostty/vt/search.h` states that "every
//! match is returned as a `GhosttySelection` snapshot with `rectangle` set to
//! false, so the existing selection APIs all work on matches".
//!
//! # Lifetime
//!
//! Grid references and selections are snapshots tied to a terminal's current
//! content. Upstream's rule: they are valid only until the next operation that
//! modifies the terminal, including `ghostty_terminal_vt_write`, resize, reset,
//! and free. Nothing here can enforce that on its own, because the reference is
//! produced by one call and consumed by another; the modules that hand these out
//! ([`crate::search`]) carry the rules in their own documentation and re-read
//! rather than cache.

use crate::ffi;

/// A handle to one cell in a terminal grid.
///
/// The `node` field is a library-internal pointer, so equality and hashing are
/// not exposed: two references to the same cell can carry different node values
/// after reflow.
#[derive(Clone, Copy)]
pub struct GridRef {
    raw: ffi::GhosttyGridRef,
}

impl GridRef {
    /// Column of the referenced cell.
    pub fn x(&self) -> u16 {
        self.raw.x
    }

    /// Row of the referenced cell.
    pub fn y(&self) -> u16 {
        self.raw.y
    }

    /// Build a sized `GhosttyGridRef`, the way `GHOSTTY_INIT_SIZED` does.
    pub(crate) fn sized() -> Self {
        let mut raw: ffi::GhosttyGridRef = sized_zeroed();
        raw.size = core::mem::size_of::<ffi::GhosttyGridRef>();
        GridRef { raw }
    }

    pub(crate) fn from_ffi(raw: ffi::GhosttyGridRef) -> Self {
        GridRef { raw }
    }

    pub(crate) fn to_ffi(self) -> ffi::GhosttyGridRef {
        self.raw
    }
}

impl PartialEq for GridRef {
    /// Compares the cell coordinates only.
    ///
    /// `node` is a library-internal pointer that legitimately changes across
    /// reflow while still referring to the same logical cell, so comparing it
    /// would produce false negatives. Equality here means "same row and column".
    fn eq(&self, other: &Self) -> bool {
        self.raw.x == other.raw.x && self.raw.y == other.raw.y
    }
}

impl Eq for GridRef {}

impl core::fmt::Debug for GridRef {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        // Deliberately omits `node`: it is an internal pointer whose value is not
        // meaningful outside the library and changes across reflow.
        write!(f, "GridRef({}, {})", self.raw.x, self.raw.y)
    }
}

/// A span between two grid references.
///
/// Equality compares the endpoints (by coordinate, see [`GridRef`]'s `PartialEq`)
/// and the rectangle flag, which is what callers can observe.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Selection {
    /// Start of the span.
    pub start: GridRef,
    /// End of the span, inclusive.
    pub end: GridRef,
    /// Whether the span is a rectangle rather than a linear run.
    ///
    /// Search matches always set this to `false`.
    pub rectangle: bool,
}

impl Selection {
    /// Build a sized `GhosttySelection`, the way `GHOSTTY_INIT_SIZED` does.
    ///
    /// Several queries require the `size` field to be pre-set, because the
    /// library uses it to detect the caller's ABI version.
    pub fn sized() -> Self {
        Selection {
            start: GridRef::sized(),
            end: GridRef::sized(),
            rectangle: false,
        }
    }

    /// Read a C selection snapshot.
    pub fn from_ffi(raw: ffi::GhosttySelection) -> Self {
        Selection {
            start: GridRef::from_ffi(raw.start),
            end: GridRef::from_ffi(raw.end),
            rectangle: raw.rectangle,
        }
    }

    /// Build the C representation, with the size field set.
    pub fn to_ffi(self) -> ffi::GhosttySelection {
        ffi::GhosttySelection {
            size: core::mem::size_of::<ffi::GhosttySelection>(),
            start: self.start.to_ffi(),
            end: self.end.to_ffi(),
            rectangle: self.rectangle,
        }
    }

    /// Number of rows the span covers, inclusive.
    pub fn row_span(&self) -> u32 {
        u32::from(self.end.y().saturating_sub(self.start.y())) + 1
    }
}

/// A zeroed value of a sized C struct.
///
/// Used only for structs whose fields are all integers or POD, where an all-zero
/// bit pattern is valid.
fn sized_zeroed<T: Copy>() -> T {
    // SAFETY: the caller is one of the sized selection structs, whose fields are
    // integers, bools, and raw pointers; all of those admit zero.
    unsafe { core::mem::zeroed() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sized_selection_declares_the_c_size() {
        let selection = Selection::sized();
        let raw = selection.to_ffi();
        assert_eq!(raw.size, core::mem::size_of::<ffi::GhosttySelection>());
        assert!(!raw.rectangle);
        assert_eq!(Selection::from_ffi(raw).row_span(), 1);
    }

    #[test]
    fn grid_ref_sized_sets_the_size_field() {
        let raw = GridRef::sized().to_ffi();
        assert_eq!(raw.size, core::mem::size_of::<ffi::GhosttyGridRef>());
    }

    #[test]
    fn equality_ignores_the_internal_node_pointer() {
        let mut a: ffi::GhosttyGridRef = sized_zeroed();
        a.size = core::mem::size_of::<ffi::GhosttyGridRef>();
        a.x = 1;
        a.y = 2;
        let mut b = a;
        // Same cell, different internal pointer: still equal.
        b.node = core::ptr::null_mut::<core::ffi::c_void>().wrapping_add(8);
        assert_eq!(GridRef::from_ffi(a), GridRef::from_ffi(b));

        b.x = 9;
        assert_ne!(GridRef::from_ffi(a), GridRef::from_ffi(b));
    }

    #[test]
    fn debug_omits_the_internal_node_pointer() {
        let mut raw: ffi::GhosttyGridRef = sized_zeroed();
        raw.size = core::mem::size_of::<ffi::GhosttyGridRef>();
        raw.x = 3;
        raw.y = 4;
        assert_eq!(format!("{:?}", GridRef::from_ffi(raw)), "GridRef(3, 4)");
    }

    #[test]
    fn row_span_counts_inclusively() {
        let mut base = Selection::sized().to_ffi();
        base.start.y = 2;
        base.end.y = 5;
        assert_eq!(Selection::from_ffi(base).row_span(), 4);

        // A reversed span must not underflow.
        base.start.y = 7;
        base.end.y = 1;
        assert_eq!(Selection::from_ffi(base).row_span(), 1);
    }
}
