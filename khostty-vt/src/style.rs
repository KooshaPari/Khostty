//! SGR text style, mirroring `GhosttyStyle` from `include/ghostty/vt/style.h`.
//!
//! `GhosttyStyle` is the value the terminal reports for
//! `GHOSTTY_TERMINAL_DATA_CURSOR_STYLE` ("the style that will be applied to
//! newly printed characters") and the unit that grid references and render-state
//! cells expose. It is a plain-old-data struct: a size field, three tagged
//! colours, eight attribute flags, and an underline code.
//!
//! This module exists because getting the size wrong here is a memory-safety
//! bug, not a cosmetic one: the terminal writes a *whole* `GhosttyStyle` into
//! whatever pointer the caller supplies, so the caller must supply
//! `size_of::<GhosttyStyle>()` bytes. `tests/abi_layout.rs` asserts that the C
//! compiler and this crate agree on that size.

use crate::color::Color;
use crate::ffi;

/// A colour slot in a [`Style`].
///
/// The C representation is a tagged union: no colour, a palette index, or an
/// explicit RGB value.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum StyleColor {
    /// No colour is set for this slot.
    #[default]
    None,
    /// An index into the terminal's 256-entry palette.
    Palette(u8),
    /// An explicit RGB value.
    Rgb(Color),
}

impl StyleColor {
    /// Read the C tagged union.
    pub fn from_ffi(raw: ffi::GhosttyStyleColor) -> Self {
        match raw.tag {
            ffi::GHOSTTY_STYLE_COLOR_PALETTE => {
                // SAFETY: the tag selects the palette arm.
                StyleColor::Palette(unsafe { raw.value.palette })
            }
            ffi::GHOSTTY_STYLE_COLOR_RGB => {
                // SAFETY: the tag selects the RGB arm.
                StyleColor::Rgb(Color::from_ffi(unsafe { raw.value.rgb }))
            }
            _ => StyleColor::None,
        }
    }

    /// Build the C tagged union.
    pub fn to_ffi(self) -> ffi::GhosttyStyleColor {
        match self {
            StyleColor::None => ffi::GhosttyStyleColor {
                tag: ffi::GHOSTTY_STYLE_COLOR_NONE,
                value: ffi::GhosttyStyleColorValue { _padding: 0 },
            },
            StyleColor::Palette(palette) => ffi::GhosttyStyleColor {
                tag: ffi::GHOSTTY_STYLE_COLOR_PALETTE,
                value: ffi::GhosttyStyleColorValue { palette },
            },
            StyleColor::Rgb(rgb) => ffi::GhosttyStyleColor {
                tag: ffi::GHOSTTY_STYLE_COLOR_RGB,
                value: ffi::GhosttyStyleColorValue { rgb: rgb.to_ffi() },
            },
        }
    }
}

/// Underline style code, as carried by [`Style::underline`].
///
/// The C field is a plain `int` whose values follow the SGR 4:x parameter
/// space, so unknown codes are preserved rather than rejected.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Underline(pub i32);

impl Underline {
    /// No underline.
    pub const NONE: Underline = Underline(0);
    /// Single underline (SGR 4).
    pub const SINGLE: Underline = Underline(1);
    /// Double underline (SGR 21).
    pub const DOUBLE: Underline = Underline(2);
    /// Curly underline (SGR 4:3).
    pub const CURLY: Underline = Underline(3);
    /// Dotted underline (SGR 4:4).
    pub const DOTTED: Underline = Underline(4);
    /// Dashed underline (SGR 4:5).
    pub const DASHED: Underline = Underline(5);

    /// Whether the style has no underline at all.
    pub fn is_none(self) -> bool {
        self.0 == 0
    }
}

/// An SGR text style.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Style {
    /// Foreground colour.
    pub fg_color: StyleColor,
    /// Background colour.
    pub bg_color: StyleColor,
    /// Underline colour.
    pub underline_color: StyleColor,
    /// Bold (`SGR 1`).
    pub bold: bool,
    /// Italic (`SGR 3`).
    pub italic: bool,
    /// Faint/dim (`SGR 2`).
    pub faint: bool,
    /// Blink (`SGR 5`).
    pub blink: bool,
    /// Inverse/reverse video (`SGR 7`).
    pub inverse: bool,
    /// Invisible/conceal (`SGR 8`).
    pub invisible: bool,
    /// Strikethrough (`SGR 9`).
    pub strikethrough: bool,
    /// Overline (`SGR 53`).
    pub overline: bool,
    /// Underline style.
    pub underline: Underline,
}

impl Default for Style {
    fn default() -> Self {
        Style {
            fg_color: StyleColor::None,
            bg_color: StyleColor::None,
            underline_color: StyleColor::None,
            bold: false,
            italic: false,
            faint: false,
            blink: false,
            inverse: false,
            invisible: false,
            strikethrough: false,
            overline: false,
            underline: Underline::NONE,
        }
    }
}

impl Style {
    /// Copy a C `GhosttyStyle` into Rust.
    ///
    /// The `size` field is read from the C struct rather than assumed; it is
    /// exposed through [`Style::declared_size`] so a caller can detect a
    /// mismatch with this crate's view of the struct.
    pub fn from_ffi(raw: ffi::GhosttyStyle) -> (Self, usize) {
        (
            Style {
                fg_color: StyleColor::from_ffi(raw.fg_color),
                bg_color: StyleColor::from_ffi(raw.bg_color),
                underline_color: StyleColor::from_ffi(raw.underline_color),
                bold: raw.bold,
                italic: raw.italic,
                faint: raw.faint,
                blink: raw.blink,
                inverse: raw.inverse,
                invisible: raw.invisible,
                strikethrough: raw.strikethrough,
                overline: raw.overline,
                underline: Underline(raw.underline),
            },
            raw.size,
        )
    }

    /// Build a C `GhosttyStyle` initialised the way `GHOSTTY_INIT_SIZED` does,
    /// with the `size` field set to the layout this crate was compiled against.
    pub fn to_ffi(self) -> ffi::GhosttyStyle {
        ffi::GhosttyStyle {
            size: core::mem::size_of::<ffi::GhosttyStyle>(),
            fg_color: self.fg_color.to_ffi(),
            bg_color: self.bg_color.to_ffi(),
            underline_color: self.underline_color.to_ffi(),
            bold: self.bold,
            italic: self.italic,
            faint: self.faint,
            blink: self.blink,
            inverse: self.inverse,
            invisible: self.invisible,
            strikethrough: self.strikethrough,
            overline: self.overline,
            underline: self.underline.0,
        }
    }

    /// Whether every attribute is off and every colour slot is empty.
    pub fn is_plain(&self) -> bool {
        *self == Style::default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn style_color_round_trips_every_arm() {
        for color in [
            StyleColor::None,
            StyleColor::Palette(0),
            StyleColor::Palette(255),
            StyleColor::Rgb(Color::rgb(1, 2, 3)),
        ] {
            assert_eq!(StyleColor::from_ffi(color.to_ffi()), color);
        }
    }

    #[test]
    fn none_arm_reads_back_as_none() {
        let raw = StyleColor::None.to_ffi();
        assert_eq!(raw.tag, ffi::GHOSTTY_STYLE_COLOR_NONE);
        assert_eq!(StyleColor::from_ffi(raw), StyleColor::None);
    }

    #[test]
    fn style_ffi_round_trip_sets_the_size_field() {
        let style = Style {
            fg_color: StyleColor::Rgb(Color::rgb(0xde, 0xad, 0xbe)),
            bold: true,
            underline: Underline::CURLY,
            ..Style::default()
        };
        let raw = style.to_ffi();
        assert_eq!(raw.size, core::mem::size_of::<ffi::GhosttyStyle>());

        let (back, declared) = Style::from_ffi(raw);
        assert_eq!(back, style);
        assert_eq!(declared, core::mem::size_of::<ffi::GhosttyStyle>());
    }

    #[test]
    fn unknown_underline_codes_are_preserved() {
        let raw = ffi::GhosttyStyle {
            underline: 42,
            ..Style::default().to_ffi()
        };
        assert_eq!(Style::from_ffi(raw).0.underline, Underline(42));
    }

    #[test]
    fn default_style_is_plain() {
        assert!(Style::default().is_plain());
        assert!(Underline::NONE.is_none());
        assert!(!Underline::DOUBLE.is_none());
    }

    #[test]
    fn ghostty_style_is_larger_than_a_single_int() {
        // Regression guard for the bug this module was written to fix: the
        // cursor-style data key returns a whole `GhosttyStyle`, not a 4-byte
        // enum, so marshalling it into a smaller slot would smash the stack.
        assert!(
            core::mem::size_of::<ffi::GhosttyStyle>() > core::mem::size_of::<i32>(),
            "GhosttyStyle must not be marshalled as a scalar"
        );
    }
}
