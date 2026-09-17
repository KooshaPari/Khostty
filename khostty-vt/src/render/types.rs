//! Value types for the render state.
//!
//! These mirror the C enums and sized structs the render-state queries return.
//! As elsewhere in this crate, unknown enum values are preserved rather than
//! collapsed to a default, because upstream declares the C API unstable.

use crate::color::Color;
use crate::ffi;

/// How much of the frame needs redrawing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum Dirty {
    /// Not dirty at all; rendering can be skipped.
    False,
    /// Some rows changed; the renderer can redraw incrementally.
    Partial,
    /// Global state changed; the renderer should redraw everything.
    Full,
    /// A dirty value this binding does not know.
    Unknown(ffi::GhosttyRenderStateDirty),
}

impl Dirty {
    /// Map a raw `GhosttyRenderStateDirty`.
    pub fn from_raw(raw: ffi::GhosttyRenderStateDirty) -> Self {
        match raw {
            ffi::GHOSTTY_RENDER_STATE_DIRTY_FALSE => Dirty::False,
            ffi::GHOSTTY_RENDER_STATE_DIRTY_PARTIAL => Dirty::Partial,
            ffi::GHOSTTY_RENDER_STATE_DIRTY_FULL => Dirty::Full,
            other => Dirty::Unknown(other),
        }
    }

    /// Raw value for handing back to the C API.
    pub fn to_raw(self) -> ffi::GhosttyRenderStateDirty {
        match self {
            Dirty::False => ffi::GHOSTTY_RENDER_STATE_DIRTY_FALSE,
            Dirty::Partial => ffi::GHOSTTY_RENDER_STATE_DIRTY_PARTIAL,
            Dirty::Full => ffi::GHOSTTY_RENDER_STATE_DIRTY_FULL,
            Dirty::Unknown(raw) => raw,
        }
    }

    /// Whether anything needs drawing.
    pub fn needs_draw(self) -> bool {
        !matches!(self, Dirty::False)
    }
}

/// Visual shape of the cursor, mirroring `GhosttyRenderStateCursorVisualStyle`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum CursorVisualStyle {
    /// Bar cursor (`DECSCUSR` 5, 6).
    Bar,
    /// Block cursor (`DECSCUSR` 1, 2).
    Block,
    /// Underline cursor (`DECSCUSR` 3, 4).
    Underline,
    /// Hollow block cursor.
    BlockHollow,
    /// A style value this binding does not know.
    Unknown(ffi::GhosttyRenderStateCursorVisualStyle),
}

impl CursorVisualStyle {
    /// Map a raw `GhosttyRenderStateCursorVisualStyle`.
    pub fn from_raw(raw: ffi::GhosttyRenderStateCursorVisualStyle) -> Self {
        match raw {
            ffi::GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BAR => CursorVisualStyle::Bar,
            ffi::GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK => CursorVisualStyle::Block,
            ffi::GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_UNDERLINE => CursorVisualStyle::Underline,
            ffi::GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK_HOLLOW => {
                CursorVisualStyle::BlockHollow
            }
            other => CursorVisualStyle::Unknown(other),
        }
    }
}

/// Cursor state for a frame, mirroring `GhosttyRenderStateCursor`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Cursor {
    /// Whether the cursor is visible inside the viewport.
    ///
    /// When false, the viewport position fields are undefined.
    pub viewport_has_value: bool,
    /// Cursor column in cells.
    pub viewport_x: u16,
    /// Cursor row in cells.
    pub viewport_y: u16,
    /// Whether the cursor sits on the tail of a wide character.
    pub wide_tail: bool,
    /// Whether the cursor is visible given the terminal modes.
    pub visible: bool,
    /// Whether the cursor should blink given the terminal modes.
    pub blinking: bool,
    /// Whether the cursor is at a password input field, which renderers should
    /// not echo.
    pub password_input: bool,
    /// Visual shape of the cursor.
    pub visual_style: CursorVisualStyle,
}

/// Frame colours, mirroring `GhosttyRenderStateColors`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Colors {
    /// Default/current background colour.
    pub background: Color,
    /// Default/current foreground colour.
    pub foreground: Color,
    /// Cursor colour when the terminal set one explicitly.
    ///
    /// Ignore it unless [`Colors::cursor_has_value`] is set: the field holds
    /// undefined data otherwise.
    pub cursor: Color,
    /// Whether [`Colors::cursor`] is meaningful.
    pub cursor_has_value: bool,
    /// The active 256-entry palette, for resolving palette-indexed cell colours.
    pub palette: [Color; 256],
}

impl Colors {
    /// Resolve a palette index, saturating at the end of the table.
    pub fn palette_color(&self, index: u8) -> Color {
        self.palette[index as usize]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dirty_round_trips_every_variant() {
        for dirty in [Dirty::False, Dirty::Partial, Dirty::Full, Dirty::Unknown(9)] {
            assert_eq!(Dirty::from_raw(dirty.to_raw()), dirty);
        }
        assert!(!Dirty::False.needs_draw());
        assert!(Dirty::Partial.needs_draw());
        assert!(Dirty::Full.needs_draw());
    }

    #[test]
    fn cursor_visual_style_maps_known_and_unknown_values() {
        assert_eq!(
            CursorVisualStyle::from_raw(ffi::GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BAR),
            CursorVisualStyle::Bar
        );
        assert_eq!(
            CursorVisualStyle::from_raw(ffi::GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK_HOLLOW),
            CursorVisualStyle::BlockHollow
        );
        assert_eq!(
            CursorVisualStyle::from_raw(42),
            CursorVisualStyle::Unknown(42)
        );
    }

    #[test]
    fn palette_lookup_is_indexed_by_u8() {
        let mut palette = [Color::BLACK; 256];
        palette[7] = Color::rgb(1, 2, 3);
        let colors = Colors {
            background: Color::default(),
            foreground: Color::default(),
            cursor: Color::default(),
            cursor_has_value: false,
            palette,
        };
        assert_eq!(colors.palette_color(7), Color::rgb(1, 2, 3));
        assert_eq!(colors.palette_color(255), Color::BLACK);
    }
}
