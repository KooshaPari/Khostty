//! Enumerations and value types used by [`crate::terminal::Terminal`].
//!
//! Every C enum in this ABI is backed by `int`, so the raw values are
//! representable in full. Unknown values are preserved through explicit
//! `Unknown(..)` arms instead of being collapsed to a default, because upstream
//! declares the C API unstable and a newer library may report a case this
//! binding predates.

use crate::ffi;

/// Which screen is active.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[non_exhaustive]
pub enum Screen {
    /// The primary (normal) screen.
    Primary,
    /// The alternate screen.
    Alternate,
    /// A screen value this binding does not know.
    Unknown(ffi::GhosttyTerminalScreen),
}

impl Screen {
    /// Map a raw `GhosttyTerminalScreen` onto the Rust enum.
    pub fn from_raw(raw: ffi::GhosttyTerminalScreen) -> Self {
        match raw {
            ffi::GHOSTTY_TERMINAL_SCREEN_PRIMARY => Screen::Primary,
            ffi::GHOSTTY_TERMINAL_SCREEN_ALTERNATE => Screen::Alternate,
            other => Screen::Unknown(other),
        }
    }
}

/// Visual style of the terminal cursor (`DECSCUSR`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[non_exhaustive]
pub enum CursorStyle {
    /// Bar cursor (`DECSCUSR` 5, 6).
    Bar,
    /// Block cursor (`DECSCUSR` 1, 2).
    Block,
    /// Underline cursor (`DECSCUSR` 3, 4).
    Underline,
    /// Hollow block cursor.
    BlockHollow,
    /// A style value this binding does not know.
    Unknown(ffi::GhosttyTerminalCursorStyle),
}

impl CursorStyle {
    /// Map a raw `GhosttyTerminalCursorStyle` onto the Rust enum.
    pub fn from_raw(raw: ffi::GhosttyTerminalCursorStyle) -> Self {
        match raw {
            ffi::GHOSTTY_TERMINAL_CURSOR_STYLE_BAR => CursorStyle::Bar,
            ffi::GHOSTTY_TERMINAL_CURSOR_STYLE_BLOCK => CursorStyle::Block,
            ffi::GHOSTTY_TERMINAL_CURSOR_STYLE_UNDERLINE => CursorStyle::Underline,
            ffi::GHOSTTY_TERMINAL_CURSOR_STYLE_BLOCK_HOLLOW => CursorStyle::BlockHollow,
            other => CursorStyle::Unknown(other),
        }
    }

    /// Raw value for handing back to the C API.
    pub fn to_raw(self) -> ffi::GhosttyTerminalCursorStyle {
        match self {
            CursorStyle::Bar => ffi::GHOSTTY_TERMINAL_CURSOR_STYLE_BAR,
            CursorStyle::Block => ffi::GHOSTTY_TERMINAL_CURSOR_STYLE_BLOCK,
            CursorStyle::Underline => ffi::GHOSTTY_TERMINAL_CURSOR_STYLE_UNDERLINE,
            CursorStyle::BlockHollow => ffi::GHOSTTY_TERMINAL_CURSOR_STYLE_BLOCK_HOLLOW,
            CursorStyle::Unknown(raw) => raw,
        }
    }
}

/// Requested viewport position, for [`crate::terminal::Terminal::scroll_viewport`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Viewport {
    /// Scroll to the top of the scrollback.
    Top,
    /// Scroll to the bottom, i.e. follow the active area.
    Bottom,
    /// Scroll by a relative amount; negative scrolls up into history.
    Delta(isize),
    /// Scroll to an absolute row offset from the top of the scrollable area.
    ///
    /// Uses the same row space as [`Scrollbar::offset`], so a scrollbar
    /// position round-trips. The value is clamped so the viewport never passes
    /// the top of the active area, and a terminal without scrollback (for
    /// example on the alternate screen) stays on the active area.
    Row(usize),
}

impl Viewport {
    /// Build the C tagged union.
    pub fn to_raw(self) -> ffi::GhosttyTerminalScrollViewport {
        let (tag, value) = match self {
            Viewport::Top => (
                ffi::GHOSTTY_SCROLL_VIEWPORT_TOP,
                ffi::GhosttyTerminalScrollViewportValue { delta: 0 },
            ),
            Viewport::Bottom => (
                ffi::GHOSTTY_SCROLL_VIEWPORT_BOTTOM,
                ffi::GhosttyTerminalScrollViewportValue { delta: 0 },
            ),
            Viewport::Delta(delta) => (
                ffi::GHOSTTY_SCROLL_VIEWPORT_DELTA,
                ffi::GhosttyTerminalScrollViewportValue { delta },
            ),
            Viewport::Row(row) => (
                ffi::GHOSTTY_SCROLL_VIEWPORT_ROW,
                ffi::GhosttyTerminalScrollViewportValue { row },
            ),
        };
        ffi::GhosttyTerminalScrollViewport { tag, value }
    }
}

/// Scrollback geometry, mirroring `GhosttyTerminalScrollbar`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Scrollbar {
    /// Total size of the scrollable area, in rows.
    pub total: u64,
    /// Offset of the viewport into the total area.
    pub offset: u64,
    /// Length of the visible area, in rows.
    pub len: u64,
}

impl Scrollbar {
    /// Whether the viewport already shows the bottom of the scrollable area.
    pub fn is_at_bottom(&self) -> bool {
        self.offset.saturating_add(self.len) >= self.total
    }
}

/// Result of a scrollback compression pass.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum CompressionResult {
    /// Retained-mapping reclamation is unavailable on this target.
    Unsupported,
    /// More incremental compression work remains; call again when idle.
    Pending,
    /// The pass has no continuation to schedule.
    Complete,
    /// A result value this binding does not know.
    Unknown(ffi::GhosttyTerminalCompressionResult),
}

impl CompressionResult {
    /// Map a raw `GhosttyTerminalCompressionResult` onto the Rust enum.
    pub fn from_raw(raw: ffi::GhosttyTerminalCompressionResult) -> Self {
        match raw {
            ffi::GHOSTTY_TERMINAL_COMPRESSION_RESULT_UNSUPPORTED => CompressionResult::Unsupported,
            ffi::GHOSTTY_TERMINAL_COMPRESSION_RESULT_PENDING => CompressionResult::Pending,
            ffi::GHOSTTY_TERMINAL_COMPRESSION_RESULT_COMPLETE => CompressionResult::Complete,
            other => CompressionResult::Unknown(other),
        }
    }
}

/// How much scrollback compression work to attempt per call.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CompressionMode {
    /// One bounded step, suitable for idle scheduling.
    Incremental,
    /// Synchronously inspect every currently eligible page.
    Full,
}

impl CompressionMode {
    /// Raw value for handing back to the C API.
    pub fn to_raw(self) -> ffi::GhosttyTerminalCompressionMode {
        match self {
            CompressionMode::Incremental => ffi::GHOSTTY_TERMINAL_COMPRESSION_MODE_INCREMENTAL,
            CompressionMode::Full => ffi::GHOSTTY_TERMINAL_COMPRESSION_MODE_FULL,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn viewport_top_and_bottom_carry_a_zero_payload() {
        for behavior in [Viewport::Top, Viewport::Bottom] {
            let raw = behavior.to_raw();
            // SAFETY: `to_raw` selects the payload arm for this variant.
            assert_eq!(unsafe { raw.value.delta }, 0);
        }
    }

    #[test]
    fn viewport_delta_and_row_select_their_union_arms() {
        let delta = Viewport::Delta(-7).to_raw();
        assert_eq!(delta.tag, ffi::GHOSTTY_SCROLL_VIEWPORT_DELTA);
        // SAFETY: the delta arm was just selected by `to_raw`.
        assert_eq!(unsafe { delta.value.delta }, -7);

        let row = Viewport::Row(42).to_raw();
        assert_eq!(row.tag, ffi::GHOSTTY_SCROLL_VIEWPORT_ROW);
        // SAFETY: the row arm was just selected by `to_raw`.
        assert_eq!(unsafe { row.value.row }, 42);
    }

    #[test]
    fn unknown_enum_values_survive_the_round_trip() {
        assert_eq!(Screen::from_raw(99), Screen::Unknown(99));
        assert_eq!(CursorStyle::from_raw(77), CursorStyle::Unknown(77));
        assert_eq!(CursorStyle::Unknown(77).to_raw(), 77);
        assert_eq!(
            CompressionResult::from_raw(31),
            CompressionResult::Unknown(31)
        );
    }

    #[test]
    fn known_enum_values_map_both_ways() {
        assert_eq!(
            Screen::from_raw(ffi::GHOSTTY_TERMINAL_SCREEN_PRIMARY),
            Screen::Primary
        );
        assert_eq!(
            Screen::from_raw(ffi::GHOSTTY_TERMINAL_SCREEN_ALTERNATE),
            Screen::Alternate
        );
        for style in [
            CursorStyle::Bar,
            CursorStyle::Block,
            CursorStyle::Underline,
            CursorStyle::BlockHollow,
        ] {
            assert_eq!(CursorStyle::from_raw(style.to_raw()), style);
        }
        assert_eq!(
            CompressionResult::from_raw(ffi::GHOSTTY_TERMINAL_COMPRESSION_RESULT_PENDING),
            CompressionResult::Pending
        );
    }

    #[test]
    fn scrollbar_bottom_detection() {
        let at_bottom = Scrollbar {
            total: 100,
            offset: 60,
            len: 40,
        };
        assert!(at_bottom.is_at_bottom());
        let scrolled_up = Scrollbar {
            total: 100,
            offset: 10,
            len: 40,
        };
        assert!(!scrolled_up.is_at_bottom());
    }
}
