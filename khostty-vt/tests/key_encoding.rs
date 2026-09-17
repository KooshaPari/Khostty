//! Integration tests for key encoding against the real library.
//!
//! Gated on the `ghostty_vt_linked` cfg; see `tests/terminal.rs` for why.

#![cfg(ghostty_vt_linked)]

use khostty_vt::key::{Key, KeyAction, KeyEncoder, KeyEvent, Mods, OptionAsAlt};
use khostty_vt::Terminal;

fn key_event(action: KeyAction, key: Key, mods: Mods) -> KeyEvent {
    let mut event = KeyEvent::new().expect("key event");
    event.set_action(action);
    event.set_key(key);
    event.set_mods(mods);
    event
}

#[test]
fn key_event_properties_round_trip() {
    let mut event = KeyEvent::new().expect("key event");

    // Defaults for a fresh event.
    assert_eq!(event.key(), Key::UNIDENTIFIED);
    assert_eq!(event.utf8(), None);
    assert_eq!(event.unshifted_codepoint(), 0);
    assert!(!event.composing());

    event.set_action(KeyAction::Repeat);
    event.set_key(Key::A);
    event.set_mods(Mods::CTRL | Mods::SHIFT);
    event.set_consumed_mods(Mods::SHIFT);
    event.set_utf8("a");
    event.set_unshifted_codepoint('a' as u32);
    event.set_composing(true);

    assert_eq!(event.action(), KeyAction::Repeat);
    assert_eq!(event.key(), Key::A);
    assert_eq!(event.mods(), Mods::CTRL | Mods::SHIFT);
    assert!(event.mods().contains(Mods::CTRL));
    assert_eq!(event.consumed_mods(), Mods::SHIFT);
    assert_eq!(event.utf8().as_deref(), Some("a"));
    assert_eq!(event.unshifted_codepoint(), 'a' as u32);
    assert!(event.composing());
}

#[test]
fn encode_plain_ascii_produces_the_literal_byte() {
    let encoder = KeyEncoder::new().expect("encoder");
    let mut event = KeyEvent::new().expect("event");
    event.set_action(KeyAction::Press);
    event.set_key(Key::A);
    event.set_utf8("a");

    assert_eq!(encoder.encode(&event).expect("encode"), b"a");
}

#[test]
fn encode_control_key_produces_the_control_byte() {
    let encoder = KeyEncoder::new().expect("encoder");
    let mut event = key_event(KeyAction::Press, Key::C, Mods::CTRL);
    event.set_utf8("c");

    assert_eq!(
        encoder.encode(&event).expect("encode"),
        b"\x03",
        "Ctrl+C must encode as ETX"
    );
}

#[test]
fn encode_enter_and_tab_produce_their_control_characters() {
    let encoder = KeyEncoder::new().expect("encoder");
    assert_eq!(
        encoder
            .encode(&key_event(KeyAction::Press, Key::ENTER, Mods::NONE))
            .unwrap(),
        b"\r"
    );
    assert_eq!(
        encoder
            .encode(&key_event(KeyAction::Press, Key::TAB, Mods::NONE))
            .unwrap(),
        b"\t"
    );
    assert_eq!(
        encoder
            .encode(&key_event(KeyAction::Press, Key::ESCAPE, Mods::NONE))
            .unwrap(),
        b"\x1b"
    );
    assert_eq!(
        encoder
            .encode(&key_event(KeyAction::Press, Key::BACKSPACE, Mods::NONE))
            .unwrap(),
        b"\x7f",
        "Backspace must encode as DEL by default"
    );
}

#[test]
fn arrow_keys_switch_between_normal_and_application_mode() {
    let mut encoder = KeyEncoder::new().expect("encoder");
    let up = key_event(KeyAction::Press, Key::ARROW_UP, Mods::NONE);

    // Normal mode: CSI A.
    assert_eq!(encoder.encode(&up).expect("normal"), b"\x1b[A");

    // Application mode: SS3 A, which is what DEC mode 1 selects.
    encoder.set_cursor_key_application(true);
    assert_eq!(encoder.encode(&up).expect("application"), b"\x1bOA");

    encoder.set_cursor_key_application(false);
    assert_eq!(encoder.encode(&up).expect("back to normal"), b"\x1b[A");
}

#[test]
fn alt_escape_prefix_needs_both_the_prefix_option_and_option_as_alt() {
    // Probing the linked library showed this is a two-part condition: with the
    // prefix option alone the text passes through unchanged, with option-as-alt
    // alone it also passes through unchanged, and only both together produce
    // ESC followed by the key. Both halves are asserted so a future library
    // change in either direction is visible.
    let mut event = key_event(KeyAction::Press, Key::A, Mods::ALT);
    event.set_utf8("a");

    let plain = KeyEncoder::new().expect("encoder");
    assert_eq!(
        plain.encode(&event).expect("no options"),
        b"a",
        "by default Alt+a carries no ESC prefix"
    );

    let mut prefix_only = KeyEncoder::new().expect("encoder");
    prefix_only.set_alt_esc_prefix(true);
    assert_eq!(
        prefix_only.encode(&event).expect("prefix only"),
        b"a",
        "the prefix option alone is not enough on this platform"
    );

    let mut option_only = KeyEncoder::new().expect("encoder");
    option_only.set_option_as_alt(OptionAsAlt::True);
    assert_eq!(
        option_only.encode(&event).expect("option only"),
        b"a",
        "option-as-alt alone is not enough either"
    );

    let mut both = KeyEncoder::new().expect("encoder");
    both.set_alt_esc_prefix(true);
    both.set_option_as_alt(OptionAsAlt::True);
    assert_eq!(
        both.encode(&event).expect("both"),
        b"\x1ba",
        "with both enabled, Alt+a must encode as ESC followed by a"
    );
}

#[test]
fn alt_reaches_special_keys_as_a_modifier_regardless_of_the_prefix_options() {
    // Escape-prefixing is about text-producing keys. A special key reports Alt
    // through the CSI modifier parameter instead, so its encoding is unchanged
    // by the prefix options.
    let up = key_event(KeyAction::Press, Key::ARROW_UP, Mods::ALT);
    let plain = KeyEncoder::new().expect("encoder");
    let mut prefixed = KeyEncoder::new().expect("encoder");
    prefixed.set_alt_esc_prefix(true);
    prefixed.set_option_as_alt(OptionAsAlt::True);

    let straight = plain.encode(&up).expect("plain");
    assert_eq!(
        straight, b"\x1b[1;3A",
        "Alt+Up reports modifier 3 in the CSI parameter"
    );
    assert_eq!(prefixed.encode(&up).expect("prefixed"), straight);
}

#[test]
fn kitty_flags_change_the_encoding_of_an_ambiguous_key() {
    let mut encoder = KeyEncoder::new().expect("encoder");
    let mut event = key_event(KeyAction::Press, Key::ESCAPE, Mods::CTRL);
    event.set_utf8("");

    let legacy = encoder.encode(&event).expect("legacy");
    encoder.set_kitty_flags(1);
    let kitty = encoder.encode(&event).expect("kitty");
    assert_ne!(
        legacy, kitty,
        "enabling the Kitty disambiguate flag must change the encoding"
    );
    assert!(
        kitty.windows(2).any(|pair| pair == b"[>") || kitty.starts_with(b"\x1b["),
        "Kitty encoding should use a CSI sequence, got {kitty:?}"
    );
}

#[test]
fn encoder_syncs_options_from_terminal_modes() {
    let mut term = Terminal::new(20, 4).expect("terminal");
    let mut encoder = KeyEncoder::new().expect("encoder");
    let up = key_event(KeyAction::Press, Key::ARROW_UP, Mods::NONE);

    // DECSET 1 enables cursor key application mode.
    term.vt_write(b"\x1b[?1h");
    encoder.sync_from_terminal(&term);
    assert_eq!(
        encoder.encode(&up).expect("encode"),
        b"\x1bOA",
        "the terminal's application-mode flag must reach the encoder"
    );

    term.vt_write(b"\x1b[?1l");
    encoder.sync_from_terminal(&term);
    assert_eq!(encoder.encode(&up).expect("encode"), b"\x1b[A");
}

#[test]
fn encoder_syncs_kitty_flags_from_terminal() {
    let mut term = Terminal::new(20, 4).expect("terminal");
    let mut encoder = KeyEncoder::new().expect("encoder");
    let mut event = key_event(KeyAction::Press, Key::ESCAPE, Mods::CTRL);
    event.set_utf8("");

    let legacy = encoder.encode(&event).expect("legacy");

    // CSI > 1 u enables the Kitty disambiguate flag.
    term.vt_write(b"\x1b[>1u");
    assert_eq!(term.kitty_keyboard_flags().unwrap(), 1);
    encoder.sync_from_terminal(&term);

    let kitty = encoder.encode(&event).expect("kitty");
    assert_ne!(
        legacy, kitty,
        "the terminal's Kitty flags must reach the encoder"
    );
}

#[test]
fn option_as_alt_is_settable() {
    let mut encoder = KeyEncoder::new().expect("encoder");
    for setting in [
        OptionAsAlt::False,
        OptionAsAlt::True,
        OptionAsAlt::Left,
        OptionAsAlt::Right,
    ] {
        encoder.set_option_as_alt(setting);
    }
}

#[test]
fn backarrow_key_mode_switches_backspace_between_del_and_bs() {
    let mut encoder = KeyEncoder::new().expect("encoder");
    let backspace = key_event(KeyAction::Press, Key::BACKSPACE, Mods::NONE);

    assert_eq!(encoder.encode(&backspace).unwrap(), b"\x7f");
    encoder.set_backarrow_key_mode(true);
    assert_eq!(
        encoder.encode(&backspace).unwrap(),
        b"\x08",
        "enabling backarrow mode must make Backspace send BS"
    );
}

#[test]
fn one_event_can_be_reused_across_encodes() {
    let encoder = KeyEncoder::new().expect("encoder");
    let mut event = key_event(KeyAction::Press, Key::A, Mods::NONE);

    event.set_utf8("a");
    assert_eq!(encoder.encode(&event).unwrap(), b"a");
    event.set_utf8("b");
    assert_eq!(encoder.encode(&event).unwrap(), b"b");
    event.set_key(Key::ENTER);
    event.set_utf8("");
    assert_eq!(encoder.encode(&event).unwrap(), b"\r");
}

#[test]
fn many_key_encoders_and_events_can_be_created_and_dropped() {
    for _ in 0..100 {
        let encoder = KeyEncoder::new().expect("encoder");
        let event = key_event(KeyAction::Press, Key::A, Mods::NONE);
        let _ = encoder.encode(&event);
    }
}
