//! Value types for mouse encoding.

use crate::ffi;

/// What the user did with the mouse.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum MouseAction {
    /// A button was pressed.
    Press,
    /// A button was released.
    Release,
    /// The mouse moved.
    Motion,
    /// An action this binding does not know.
    Unknown(ffi::GhosttyMouseAction),
}

impl MouseAction {
    /// Map a raw `GhosttyMouseAction`.
    pub fn from_raw(raw: ffi::GhosttyMouseAction) -> Self {
        match raw {
            ffi::GHOSTTY_MOUSE_ACTION_PRESS => MouseAction::Press,
            ffi::GHOSTTY_MOUSE_ACTION_RELEASE => MouseAction::Release,
            ffi::GHOSTTY_MOUSE_ACTION_MOTION => MouseAction::Motion,
            other => MouseAction::Unknown(other),
        }
    }

    /// Raw value for the C API.
    pub fn to_raw(self) -> ffi::GhosttyMouseAction {
        match self {
            MouseAction::Press => ffi::GHOSTTY_MOUSE_ACTION_PRESS,
            MouseAction::Release => ffi::GHOSTTY_MOUSE_ACTION_RELEASE,
            MouseAction::Motion => ffi::GHOSTTY_MOUSE_ACTION_MOTION,
            MouseAction::Unknown(raw) => raw,
        }
    }
}

/// Which mouse button.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum MouseButton {
    /// No button, or one the platform could not identify.
    Unknown,
    /// Left button.
    Left,
    /// Right button.
    Right,
    /// Middle button.
    Middle,
    /// Fourth button (typically back).
    Four,
    /// Fifth button (typically forward).
    Five,
    /// Sixth button.
    Six,
    /// Seventh button.
    Seven,
    /// Eighth button.
    Eight,
    /// Ninth button.
    Nine,
    /// Tenth button.
    Ten,
    /// Eleventh button.
    Eleven,
    /// A button index this binding does not know.
    Other(ffi::GhosttyMouseButton),
}

impl MouseButton {
    /// Map a raw `GhosttyMouseButton`.
    pub fn from_raw(raw: ffi::GhosttyMouseButton) -> Self {
        match raw {
            ffi::GHOSTTY_MOUSE_BUTTON_UNKNOWN => MouseButton::Unknown,
            ffi::GHOSTTY_MOUSE_BUTTON_LEFT => MouseButton::Left,
            ffi::GHOSTTY_MOUSE_BUTTON_RIGHT => MouseButton::Right,
            ffi::GHOSTTY_MOUSE_BUTTON_MIDDLE => MouseButton::Middle,
            ffi::GHOSTTY_MOUSE_BUTTON_FOUR => MouseButton::Four,
            ffi::GHOSTTY_MOUSE_BUTTON_FIVE => MouseButton::Five,
            ffi::GHOSTTY_MOUSE_BUTTON_SIX => MouseButton::Six,
            ffi::GHOSTTY_MOUSE_BUTTON_SEVEN => MouseButton::Seven,
            ffi::GHOSTTY_MOUSE_BUTTON_EIGHT => MouseButton::Eight,
            ffi::GHOSTTY_MOUSE_BUTTON_NINE => MouseButton::Nine,
            ffi::GHOSTTY_MOUSE_BUTTON_TEN => MouseButton::Ten,
            ffi::GHOSTTY_MOUSE_BUTTON_ELEVEN => MouseButton::Eleven,
            other => MouseButton::Other(other),
        }
    }

    /// Raw value for the C API.
    pub fn to_raw(self) -> ffi::GhosttyMouseButton {
        match self {
            MouseButton::Unknown => ffi::GHOSTTY_MOUSE_BUTTON_UNKNOWN,
            MouseButton::Left => ffi::GHOSTTY_MOUSE_BUTTON_LEFT,
            MouseButton::Right => ffi::GHOSTTY_MOUSE_BUTTON_RIGHT,
            MouseButton::Middle => ffi::GHOSTTY_MOUSE_BUTTON_MIDDLE,
            MouseButton::Four => ffi::GHOSTTY_MOUSE_BUTTON_FOUR,
            MouseButton::Five => ffi::GHOSTTY_MOUSE_BUTTON_FIVE,
            MouseButton::Six => ffi::GHOSTTY_MOUSE_BUTTON_SIX,
            MouseButton::Seven => ffi::GHOSTTY_MOUSE_BUTTON_SEVEN,
            MouseButton::Eight => ffi::GHOSTTY_MOUSE_BUTTON_EIGHT,
            MouseButton::Nine => ffi::GHOSTTY_MOUSE_BUTTON_NINE,
            MouseButton::Ten => ffi::GHOSTTY_MOUSE_BUTTON_TEN,
            MouseButton::Eleven => ffi::GHOSTTY_MOUSE_BUTTON_ELEVEN,
            MouseButton::Other(raw) => raw,
        }
    }
}

/// A mouse position in surface coordinates.
///
/// The C representation is a pair of `float`s; see
/// [`MouseEncoderSize`] for how surface coordinates become cell coordinates.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct MousePosition {
    /// X position.
    pub x: f32,
    /// Y position.
    pub y: f32,
}

impl MousePosition {
    /// Build a position.
    pub const fn new(x: f32, y: f32) -> Self {
        MousePosition { x, y }
    }

    /// Read the C representation.
    pub fn from_ffi(raw: ffi::GhosttyMousePosition) -> Self {
        MousePosition { x: raw.x, y: raw.y }
    }

    /// Build the C representation.
    pub fn to_ffi(self) -> ffi::GhosttyMousePosition {
        ffi::GhosttyMousePosition {
            x: self.x,
            y: self.y,
        }
    }
}

/// Which mouse tracking mode the terminal has enabled.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum MouseTrackingMode {
    /// Mouse reporting disabled.
    None,
    /// X10 compatibility mode: press only.
    X10,
    /// Normal mode: press and release only.
    Normal,
    /// Button-event tracking: press, release, and motion while a button is held.
    Button,
    /// Any-event tracking: all motion is reported.
    Any,
    /// A mode this binding does not know.
    Unknown(ffi::GhosttyMouseTrackingMode),
}

impl MouseTrackingMode {
    /// Map a raw `GhosttyMouseTrackingMode`.
    pub fn from_raw(raw: ffi::GhosttyMouseTrackingMode) -> Self {
        match raw {
            ffi::GHOSTTY_MOUSE_TRACKING_NONE => MouseTrackingMode::None,
            ffi::GHOSTTY_MOUSE_TRACKING_X10 => MouseTrackingMode::X10,
            ffi::GHOSTTY_MOUSE_TRACKING_NORMAL => MouseTrackingMode::Normal,
            ffi::GHOSTTY_MOUSE_TRACKING_BUTTON => MouseTrackingMode::Button,
            ffi::GHOSTTY_MOUSE_TRACKING_ANY => MouseTrackingMode::Any,
            other => MouseTrackingMode::Unknown(other),
        }
    }

    /// Raw value for the C API.
    pub fn to_raw(self) -> ffi::GhosttyMouseTrackingMode {
        match self {
            MouseTrackingMode::None => ffi::GHOSTTY_MOUSE_TRACKING_NONE,
            MouseTrackingMode::X10 => ffi::GHOSTTY_MOUSE_TRACKING_X10,
            MouseTrackingMode::Normal => ffi::GHOSTTY_MOUSE_TRACKING_NORMAL,
            MouseTrackingMode::Button => ffi::GHOSTTY_MOUSE_TRACKING_BUTTON,
            MouseTrackingMode::Any => ffi::GHOSTTY_MOUSE_TRACKING_ANY,
            MouseTrackingMode::Unknown(raw) => raw,
        }
    }
}

/// Which wire format the encoder emits.
///
/// [`MouseFormat::X10`] is the zero value of `GhosttyMouseFormat` and therefore
/// what an encoder reports before the format is configured or synced from a
/// terminal, which is what [`Default`] returns. It is *not* what a modern program
/// wants: SGR supersedes X10 because X10 cannot express coordinates past column
/// 223. Real programs select SGR with `DECSET 1006`, and
/// [`MouseEncoder::sync_from_terminal`](super::MouseEncoder::sync_from_terminal)
/// picks it up from there.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
#[non_exhaustive]
pub enum MouseFormat {
    /// X10 compatibility format. The library's default.
    #[default]
    X10,
    /// UTF-8 extended format.
    Utf8,
    /// SGR format (`CSI < ... M/m`). Selectable with `DECSET 1006`, and the only
    /// format that expresses coordinates beyond column 223.
    Sgr,
    /// URxvt format.
    Urxvt,
    /// SGR format with pixel coordinates.
    SgrPixels,
    /// A format this binding does not know.
    Unknown(ffi::GhosttyMouseFormat),
}

impl MouseFormat {
    /// Map a raw `GhosttyMouseFormat`.
    pub fn from_raw(raw: ffi::GhosttyMouseFormat) -> Self {
        match raw {
            ffi::GHOSTTY_MOUSE_FORMAT_X10 => MouseFormat::X10,
            ffi::GHOSTTY_MOUSE_FORMAT_UTF8 => MouseFormat::Utf8,
            ffi::GHOSTTY_MOUSE_FORMAT_SGR => MouseFormat::Sgr,
            ffi::GHOSTTY_MOUSE_FORMAT_URXVT => MouseFormat::Urxvt,
            ffi::GHOSTTY_MOUSE_FORMAT_SGR_PIXELS => MouseFormat::SgrPixels,
            other => MouseFormat::Unknown(other),
        }
    }

    /// Raw value for the C API.
    pub fn to_raw(self) -> ffi::GhosttyMouseFormat {
        match self {
            MouseFormat::X10 => ffi::GHOSTTY_MOUSE_FORMAT_X10,
            MouseFormat::Utf8 => ffi::GHOSTTY_MOUSE_FORMAT_UTF8,
            MouseFormat::Sgr => ffi::GHOSTTY_MOUSE_FORMAT_SGR,
            MouseFormat::Urxvt => ffi::GHOSTTY_MOUSE_FORMAT_URXVT,
            MouseFormat::SgrPixels => ffi::GHOSTTY_MOUSE_FORMAT_SGR_PIXELS,
            MouseFormat::Unknown(raw) => raw,
        }
    }
}

/// Renderer geometry the encoder needs to map surface coordinates to cells.
///
/// # Set the screen size, not just the cell size
///
/// The encoder treats the screen as the valid region and silently drops events
/// whose position falls outside it: [`Super::MouseEncoder::encode`] returns an
/// empty sequence rather than an error. A zero `screen_width`/`screen_height`
/// therefore makes every position except the origin out of bounds, so a caller
/// that sets only the cell size gets a working press at `(0, 0)` and silent
/// nothing everywhere else. That failure mode cost real debugging time when
/// writing this crate's tests, which is why it is called out here.
///
/// Cell width and height must also be non-zero, for the formats that convert
/// pixels to cells.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct MouseEncoderSize {
    /// Full screen width in pixels.
    ///
    /// Must be the real surface width; see the type-level note.
    pub screen_width: u32,
    /// Full screen height in pixels.
    ///
    /// Must be the real surface height; see the type-level note.
    pub screen_height: u32,
    /// Cell width in pixels.
    pub cell_width: u32,
    /// Cell height in pixels.
    pub cell_height: u32,
    /// Top padding in pixels.
    pub padding_top: u32,
    /// Bottom padding in pixels.
    pub padding_bottom: u32,
    /// Right padding in pixels.
    pub padding_right: u32,
    /// Left padding in pixels.
    pub padding_left: u32,
}

impl MouseEncoderSize {
    /// Read the C representation.
    pub fn from_ffi(raw: ffi::GhosttyMouseEncoderSize) -> Self {
        MouseEncoderSize {
            screen_width: raw.screen_width,
            screen_height: raw.screen_height,
            cell_width: raw.cell_width,
            cell_height: raw.cell_height,
            padding_top: raw.padding_top,
            padding_bottom: raw.padding_bottom,
            padding_right: raw.padding_right,
            padding_left: raw.padding_left,
        }
    }

    /// Build the C representation, with the `size` field set the way
    /// `GHOSTTY_INIT_SIZED` does.
    pub fn to_ffi(self) -> ffi::GhosttyMouseEncoderSize {
        ffi::GhosttyMouseEncoderSize {
            size: core::mem::size_of::<ffi::GhosttyMouseEncoderSize>(),
            screen_width: self.screen_width,
            screen_height: self.screen_height,
            cell_width: self.cell_width,
            cell_height: self.cell_height,
            padding_top: self.padding_top,
            padding_bottom: self.padding_bottom,
            padding_right: self.padding_right,
            padding_left: self.padding_left,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mouse_action_round_trips_and_preserves_unknown_values() {
        for action in [
            MouseAction::Press,
            MouseAction::Release,
            MouseAction::Motion,
        ] {
            assert_eq!(MouseAction::from_raw(action.to_raw()), action);
        }
        assert_eq!(MouseAction::from_raw(99), MouseAction::Unknown(99));
    }

    #[test]
    fn mouse_button_round_trips_every_named_button() {
        for button in [
            MouseButton::Unknown,
            MouseButton::Left,
            MouseButton::Right,
            MouseButton::Middle,
            MouseButton::Four,
            MouseButton::Five,
            MouseButton::Six,
            MouseButton::Seven,
            MouseButton::Eight,
            MouseButton::Nine,
            MouseButton::Ten,
            MouseButton::Eleven,
        ] {
            assert_eq!(MouseButton::from_raw(button.to_raw()), button);
        }
        assert_eq!(MouseButton::from_raw(200), MouseButton::Other(200));
    }

    #[test]
    fn tracking_mode_round_trips_and_preserves_unknown_values() {
        for mode in [
            MouseTrackingMode::None,
            MouseTrackingMode::X10,
            MouseTrackingMode::Normal,
            MouseTrackingMode::Button,
            MouseTrackingMode::Any,
        ] {
            assert_eq!(MouseTrackingMode::from_raw(mode.to_raw()), mode);
        }
        assert_eq!(
            MouseTrackingMode::from_raw(77),
            MouseTrackingMode::Unknown(77)
        );
    }

    #[test]
    fn mouse_format_round_trips_and_defaults_to_the_library_zero_value() {
        for format in [
            MouseFormat::X10,
            MouseFormat::Utf8,
            MouseFormat::Sgr,
            MouseFormat::Urxvt,
            MouseFormat::SgrPixels,
        ] {
            assert_eq!(MouseFormat::from_raw(format.to_raw()), format);
        }
        assert_eq!(
            MouseFormat::default(),
            MouseFormat::X10,
            "the default must match GhosttyMouseFormat's zero value"
        );
        assert_eq!(MouseFormat::from_raw(55), MouseFormat::Unknown(55));
    }

    #[test]
    fn position_round_trips_including_negatives() {
        for position in [
            MousePosition::new(0.0, 0.0),
            MousePosition::new(12.5, 300.25),
            MousePosition::new(-4.0, -0.5),
        ] {
            assert_eq!(MousePosition::from_ffi(position.to_ffi()), position);
        }
    }

    #[test]
    fn default_size_has_zero_bounds() {
        // The default is all zeros, which (per the type-level note) means only
        // the origin counts as inside the screen. Callers must fill this in.
        let size = MouseEncoderSize::default();
        assert_eq!(size.screen_width, 0);
        assert_eq!(size.screen_height, 0);
    }

    #[test]
    fn encoder_size_declares_its_own_size() {
        let size = MouseEncoderSize {
            cell_width: 8,
            cell_height: 16,
            ..MouseEncoderSize::default()
        };
        let raw = size.to_ffi();
        assert_eq!(
            raw.size,
            core::mem::size_of::<ffi::GhosttyMouseEncoderSize>()
        );
        assert_eq!(MouseEncoderSize::from_ffi(raw), size);
    }
}
