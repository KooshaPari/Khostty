//! An 8-bit-per-channel RGB colour, mirroring `GhosttyColorRgb`.
//!
//! `GhosttyColorRgb` is the value type used by the terminal colour options and
//! queries, by `ghostty_render_state_*` colours, and by the colour parser in
//! `color.h`. It is a three-byte POD struct, so a distinct Rust newtype keeps
//! the FFI boundary explicit without any layout cost.

use crate::ffi;

/// An opaque RGB colour.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Hash, PartialOrd, Ord)]
pub struct Color {
    /// Red channel.
    pub r: u8,
    /// Green channel.
    pub g: u8,
    /// Blue channel.
    pub b: u8,
}

impl Color {
    /// Construct a colour from its channels.
    pub const fn rgb(r: u8, g: u8, b: u8) -> Self {
        Color { r, g, b }
    }

    /// Black, the zero value of `GhosttyColorRgb`.
    pub const BLACK: Color = Color::rgb(0, 0, 0);

    /// Convert from the C representation.
    pub const fn from_ffi(raw: ffi::GhosttyColorRgb) -> Self {
        Color {
            r: raw.r,
            g: raw.g,
            b: raw.b,
        }
    }

    /// Convert to the C representation.
    pub const fn to_ffi(self) -> ffi::GhosttyColorRgb {
        ffi::GhosttyColorRgb {
            r: self.r,
            g: self.g,
            b: self.b,
        }
    }

    /// The six-digit `RRGGBB` form, without a leading `#`.
    pub fn to_hex(self) -> String {
        format!("{:02x}{:02x}{:02x}", self.r, self.g, self.b)
    }
}

impl core::fmt::Display for Color {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        write!(f, "#{:02x}{:02x}{:02x}", self.r, self.g, self.b)
    }
}

impl From<ffi::GhosttyColorRgb> for Color {
    fn from(raw: ffi::GhosttyColorRgb) -> Self {
        Color::from_ffi(raw)
    }
}

impl From<Color> for ffi::GhosttyColorRgb {
    fn from(color: Color) -> Self {
        color.to_ffi()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ffi_round_trip_preserves_channels() {
        let c = Color::rgb(0x12, 0x34, 0x56);
        assert_eq!(Color::from_ffi(c.to_ffi()), c);
    }

    #[test]
    fn layout_matches_the_c_struct() {
        // Three u8 fields, no padding, align 1.
        assert_eq!(
            core::mem::size_of::<Color>(),
            core::mem::size_of::<ffi::GhosttyColorRgb>()
        );
        assert_eq!(core::mem::size_of::<Color>(), 3);
    }

    #[test]
    fn hex_and_display_agree() {
        let c = Color::rgb(0x0a, 0xff, 0x00);
        assert_eq!(c.to_hex(), "0aff00");
        assert_eq!(c.to_string(), "#0aff00");
    }

    #[test]
    fn default_is_black() {
        assert_eq!(Color::default(), Color::BLACK);
    }
}
