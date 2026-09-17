//! Value types for key encoding.
//!
//! The C API types these as bare integers and macros: `GhosttyMods` is a
//! `uint16_t` bitmask, `GhosttyKey` is an `int`-backed enum of 177 codes, and the
//! modifier flags are `#define`d bit positions. This module gives them names,
//! bit operations, and exhaustiveness without inventing values the header does not
//! define.

use crate::ffi;

/// Keyboard modifier bitflags, mirroring `GhosttyMods`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Hash)]
pub struct Mods(pub ffi::GhosttyMods);

impl Mods {
    /// No modifiers held.
    pub const NONE: Mods = Mods(0);
    /// Shift, either side.
    pub const SHIFT: Mods = Mods(ffi::GHOSTTY_MODS_SHIFT as ffi::GhosttyMods);
    /// Control, either side.
    pub const CTRL: Mods = Mods(ffi::GHOSTTY_MODS_CTRL as ffi::GhosttyMods);
    /// Alt/Option, either side.
    pub const ALT: Mods = Mods(ffi::GHOSTTY_MODS_ALT as ffi::GhosttyMods);
    /// Super/Command/Windows, either side.
    pub const SUPER: Mods = Mods(ffi::GHOSTTY_MODS_SUPER as ffi::GhosttyMods);
    /// Caps Lock engaged.
    pub const CAPS_LOCK: Mods = Mods(ffi::GHOSTTY_MODS_CAPS_LOCK as ffi::GhosttyMods);
    /// Num Lock engaged.
    pub const NUM_LOCK: Mods = Mods(ffi::GHOSTTY_MODS_NUM_LOCK as ffi::GhosttyMods);
    /// The right-hand Shift key specifically.
    pub const SHIFT_SIDE: Mods = Mods(ffi::GHOSTTY_MODS_SHIFT_SIDE as ffi::GhosttyMods);
    /// The right-hand Control key specifically.
    pub const CTRL_SIDE: Mods = Mods(ffi::GHOSTTY_MODS_CTRL_SIDE as ffi::GhosttyMods);
    /// The right-hand Alt/Option key specifically.
    pub const ALT_SIDE: Mods = Mods(ffi::GHOSTTY_MODS_ALT_SIDE as ffi::GhosttyMods);
    /// The right-hand Super/Command key specifically.
    pub const SUPER_SIDE: Mods = Mods(ffi::GHOSTTY_MODS_SUPER_SIDE as ffi::GhosttyMods);

    /// Whether every flag in `other` is set here.
    pub const fn contains(self, other: Mods) -> bool {
        self.0 & other.0 == other.0
    }

    /// Combine two flag sets.
    pub const fn union(self, other: Mods) -> Mods {
        Mods(self.0 | other.0)
    }

    /// The raw bitmask.
    pub const fn bits(self) -> ffi::GhosttyMods {
        self.0
    }

    /// Build from a raw bitmask.
    pub const fn from_bits(bits: ffi::GhosttyMods) -> Mods {
        Mods(bits)
    }

    /// Whether no modifier is held.
    pub const fn is_empty(self) -> bool {
        self.0 == 0
    }
}

impl core::ops::BitOr for Mods {
    type Output = Mods;
    fn bitor(self, rhs: Mods) -> Mods {
        self.union(rhs)
    }
}

/// A key code, mirroring `GhosttyKey`.
///
/// The full set of codes lives in `crate::ffi`; this wrapper exists so the common
/// ones can be named ergonomically and so a raw code from anywhere else can be
/// passed without an unchecked cast.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[non_exhaustive]
pub struct Key(pub ffi::GhosttyKey);

impl Key {
    /// The key the platform could not identify.
    pub const UNIDENTIFIED: Key = Key(ffi::GHOSTTY_KEY_UNIDENTIFIED);
    /// Return/Enter.
    pub const ENTER: Key = Key(ffi::GHOSTTY_KEY_ENTER);
    /// Tab.
    pub const TAB: Key = Key(ffi::GHOSTTY_KEY_TAB);
    /// Backspace.
    pub const BACKSPACE: Key = Key(ffi::GHOSTTY_KEY_BACKSPACE);
    /// Escape.
    pub const ESCAPE: Key = Key(ffi::GHOSTTY_KEY_ESCAPE);
    /// Space.
    pub const SPACE: Key = Key(ffi::GHOSTTY_KEY_SPACE);
    /// Delete.
    pub const DELETE: Key = Key(ffi::GHOSTTY_KEY_DELETE);
    /// Home.
    pub const HOME: Key = Key(ffi::GHOSTTY_KEY_HOME);
    /// End.
    pub const END: Key = Key(ffi::GHOSTTY_KEY_END);
    /// Page Up.
    pub const PAGE_UP: Key = Key(ffi::GHOSTTY_KEY_PAGE_UP);
    /// Page Down.
    pub const PAGE_DOWN: Key = Key(ffi::GHOSTTY_KEY_PAGE_DOWN);
    /// Up arrow.
    pub const ARROW_UP: Key = Key(ffi::GHOSTTY_KEY_ARROW_UP);
    /// Down arrow.
    pub const ARROW_DOWN: Key = Key(ffi::GHOSTTY_KEY_ARROW_DOWN);
    /// Left arrow.
    pub const ARROW_LEFT: Key = Key(ffi::GHOSTTY_KEY_ARROW_LEFT);
    /// Right arrow.
    pub const ARROW_RIGHT: Key = Key(ffi::GHOSTTY_KEY_ARROW_RIGHT);
    /// The `a` key.
    pub const A: Key = Key(ffi::GHOSTTY_KEY_A);
    /// The `c` key.
    pub const C: Key = Key(ffi::GHOSTTY_KEY_C);
    /// The `d` key.
    pub const D: Key = Key(ffi::GHOSTTY_KEY_D);
    /// The `v` key.
    pub const V: Key = Key(ffi::GHOSTTY_KEY_V);
    /// The `x` key.
    pub const X: Key = Key(ffi::GHOSTTY_KEY_X);
    /// Left Control.
    pub const CONTROL_LEFT: Key = Key(ffi::GHOSTTY_KEY_CONTROL_LEFT);
    /// Left Shift.
    pub const SHIFT_LEFT: Key = Key(ffi::GHOSTTY_KEY_SHIFT_LEFT);
    /// Left Alt/Option.
    pub const ALT_LEFT: Key = Key(ffi::GHOSTTY_KEY_ALT_LEFT);

    /// Build from a raw code.
    pub const fn from_raw(raw: ffi::GhosttyKey) -> Key {
        Key(raw)
    }

    /// The raw code.
    pub const fn raw(self) -> ffi::GhosttyKey {
        self.0
    }
}

impl From<ffi::GhosttyKey> for Key {
    fn from(raw: ffi::GhosttyKey) -> Key {
        Key(raw)
    }
}

impl From<Key> for ffi::GhosttyKey {
    fn from(key: Key) -> ffi::GhosttyKey {
        key.0
    }
}

/// What the user did with the key.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum KeyAction {
    /// The key was released.
    Release,
    /// The key was pressed.
    Press,
    /// The key is being repeated because it is held down.
    Repeat,
    /// An action this binding does not know.
    Unknown(ffi::GhosttyKeyAction),
}

impl KeyAction {
    /// Map a raw `GhosttyKeyAction`.
    pub fn from_raw(raw: ffi::GhosttyKeyAction) -> Self {
        match raw {
            ffi::GHOSTTY_KEY_ACTION_RELEASE => KeyAction::Release,
            ffi::GHOSTTY_KEY_ACTION_PRESS => KeyAction::Press,
            ffi::GHOSTTY_KEY_ACTION_REPEAT => KeyAction::Repeat,
            other => KeyAction::Unknown(other),
        }
    }

    /// Raw value for the C API.
    pub fn to_raw(self) -> ffi::GhosttyKeyAction {
        match self {
            KeyAction::Release => ffi::GHOSTTY_KEY_ACTION_RELEASE,
            KeyAction::Press => ffi::GHOSTTY_KEY_ACTION_PRESS,
            KeyAction::Repeat => ffi::GHOSTTY_KEY_ACTION_REPEAT,
            KeyAction::Unknown(raw) => raw,
        }
    }
}

/// How the macOS Option key is treated, mirroring `GhosttyOptionAsAlt`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum OptionAsAlt {
    /// Option is not treated as Alt. Terminal input shows the composed glyph.
    False,
    /// Option is always treated as Alt.
    True,
    /// Only the left Option key is treated as Alt.
    Left,
    /// Only the right Option key is treated as Alt.
    Right,
    /// A setting this binding does not know.
    Unknown(ffi::GhosttyOptionAsAlt),
}

impl OptionAsAlt {
    /// Map a raw `GhosttyOptionAsAlt`.
    pub fn from_raw(raw: ffi::GhosttyOptionAsAlt) -> Self {
        match raw {
            ffi::GHOSTTY_OPTION_AS_ALT_FALSE => OptionAsAlt::False,
            ffi::GHOSTTY_OPTION_AS_ALT_TRUE => OptionAsAlt::True,
            ffi::GHOSTTY_OPTION_AS_ALT_LEFT => OptionAsAlt::Left,
            ffi::GHOSTTY_OPTION_AS_ALT_RIGHT => OptionAsAlt::Right,
            other => OptionAsAlt::Unknown(other),
        }
    }

    /// Raw value for the C API.
    pub fn to_raw(self) -> ffi::GhosttyOptionAsAlt {
        match self {
            OptionAsAlt::False => ffi::GHOSTTY_OPTION_AS_ALT_FALSE,
            OptionAsAlt::True => ffi::GHOSTTY_OPTION_AS_ALT_TRUE,
            OptionAsAlt::Left => ffi::GHOSTTY_OPTION_AS_ALT_LEFT,
            OptionAsAlt::Right => ffi::GHOSTTY_OPTION_AS_ALT_RIGHT,
            OptionAsAlt::Unknown(raw) => raw,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mods_combine_and_test_membership() {
        let mods = Mods::CTRL | Mods::SHIFT;
        assert!(mods.contains(Mods::CTRL));
        assert!(mods.contains(Mods::SHIFT));
        assert!(!mods.contains(Mods::ALT));
        assert!(!mods.is_empty());
        assert!(Mods::NONE.is_empty());
        assert_eq!(mods.bits(), Mods::CTRL.bits() | Mods::SHIFT.bits());
    }

    #[test]
    fn mods_match_the_c_flag_values() {
        assert_eq!(Mods::SHIFT.bits(), 1 << 0);
        assert_eq!(Mods::CTRL.bits(), 1 << 1);
        assert_eq!(Mods::ALT.bits(), 1 << 2);
        assert_eq!(Mods::SUPER.bits(), 1 << 3);
        assert_eq!(Mods::CAPS_LOCK.bits(), 1 << 4);
        assert_eq!(Mods::NUM_LOCK.bits(), 1 << 5);
        assert_eq!(Mods::SHIFT_SIDE.bits(), 1 << 6);
        assert_eq!(Mods::CTRL_SIDE.bits(), 1 << 7);
        assert_eq!(Mods::ALT_SIDE.bits(), 1 << 8);
        assert_eq!(Mods::SUPER_SIDE.bits(), 1 << 9);
    }

    #[test]
    fn key_round_trips_through_raw_and_from() {
        for key in [Key::ENTER, Key::A, Key::ARROW_UP, Key::ESCAPE] {
            assert_eq!(Key::from(key.raw()), key);
            assert_eq!(Key::from_raw(key.raw()), key);
            assert_eq!(ffi::GhosttyKey::from(key), key.raw());
        }
        assert_eq!(Key::UNIDENTIFIED.raw(), ffi::GHOSTTY_KEY_UNIDENTIFIED);
    }

    #[test]
    fn key_action_maps_known_values_and_preserves_unknown_ones() {
        for action in [KeyAction::Press, KeyAction::Release, KeyAction::Repeat] {
            assert_eq!(KeyAction::from_raw(action.to_raw()), action);
        }
        assert_eq!(KeyAction::from_raw(77), KeyAction::Unknown(77));
    }

    #[test]
    fn option_as_alt_maps_known_values_and_preserves_unknown_ones() {
        for setting in [
            OptionAsAlt::False,
            OptionAsAlt::True,
            OptionAsAlt::Left,
            OptionAsAlt::Right,
        ] {
            assert_eq!(OptionAsAlt::from_raw(setting.to_raw()), setting);
        }
        assert_eq!(OptionAsAlt::from_raw(42), OptionAsAlt::Unknown(42));
    }
}
