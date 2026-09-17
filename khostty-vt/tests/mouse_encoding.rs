//! Integration tests for mouse encoding against the real library.
//!
//! Kept separate from `tests/key_encoding.rs` because key and mouse encoding are
//! distinct concerns with distinct option surfaces, and because a single file
//! covering both exceeded the repository's file-size budget.
//!
//! Gated on the `ghostty_vt_linked` cfg; see `tests/terminal.rs` for why.

#![cfg(ghostty_vt_linked)]

use khostty_vt::key::Mods;
use khostty_vt::mouse::{
    MouseAction, MouseButton, MouseEncoder, MouseEncoderSize, MouseEvent, MouseFormat,
    MousePosition, MouseTrackingMode,
};
use khostty_vt::Terminal;

#[test]
fn mouse_event_properties_round_trip() {
    let mut event = MouseEvent::new().expect("mouse event");

    // A fresh event has no button set.
    assert_eq!(event.button().expect("button"), None);

    event.set_action(MouseAction::Press);
    event.set_button(MouseButton::Left);
    event.set_mods(Mods::CTRL);
    event.set_position(MousePosition::new(40.5, 120.25));

    assert_eq!(event.action(), MouseAction::Press);
    assert_eq!(event.button().expect("button"), Some(MouseButton::Left));
    assert_eq!(event.mods(), Mods::CTRL);
    assert_eq!(event.position(), MousePosition::new(40.5, 120.25));

    event.clear_button();
    assert_eq!(event.button().expect("button"), None);
}

#[test]
fn mouse_motion_without_a_button_is_representable() {
    let mut event = MouseEvent::new().expect("mouse event");
    event.set_action(MouseAction::Motion);
    event.clear_button();
    event.set_position(MousePosition::new(1.0, 2.0));

    assert_eq!(event.action(), MouseAction::Motion);
    assert_eq!(event.button().expect("button"), None);
}

fn sized_encoder(format: MouseFormat) -> MouseEncoder {
    let mut encoder = MouseEncoder::new().expect("encoder");
    encoder.set_format(format);
    encoder.set_tracking_mode(MouseTrackingMode::Any);
    encoder.set_size(MouseEncoderSize {
        screen_width: 800,
        screen_height: 480,
        cell_width: 8,
        cell_height: 16,
        ..MouseEncoderSize::default()
    });
    encoder
}

#[test]
fn sgr_encoding_is_a_csi_sequence_with_one_based_cells() {
    let encoder = sized_encoder(MouseFormat::Sgr);
    let mut event = MouseEvent::new().expect("event");
    event.set_action(MouseAction::Press);
    event.set_button(MouseButton::Left);
    event.set_position(MousePosition::new(0.0, 0.0));

    let encoded = encoder.encode(&event).expect("encode");
    assert_eq!(
        encoded, b"\x1b[<0;1;1M",
        "left press at pixel (0,0) is cell (1,1) in SGR format"
    );
}

#[test]
fn sgr_release_uses_lowercase_m() {
    let encoder = sized_encoder(MouseFormat::Sgr);
    let mut event = MouseEvent::new().expect("event");
    event.set_action(MouseAction::Release);
    event.set_button(MouseButton::Left);
    event.set_position(MousePosition::new(0.0, 0.0));

    let encoded = encoder.encode(&event).expect("encode");
    assert_eq!(encoded, b"\x1b[<0;1;1m");
}

#[test]
fn cell_coordinates_follow_the_configured_cell_size() {
    let encoder = sized_encoder(MouseFormat::Sgr);
    let mut event = MouseEvent::new().expect("event");
    event.set_action(MouseAction::Press);
    event.set_button(MouseButton::Left);

    // Cell 8 is 8 pixels wide and 16 tall, so pixel (24, 32) is cell (4, 3),
    // reported one-based as (4, 3).
    event.set_position(MousePosition::new(24.0, 32.0));
    assert_eq!(encoder.encode(&event).expect("encode"), b"\x1b[<0;4;3M");
}

#[test]
fn right_and_middle_buttons_encode_different_button_codes() {
    let encoder = sized_encoder(MouseFormat::Sgr);
    let mut event = MouseEvent::new().expect("event");
    event.set_action(MouseAction::Press);
    event.set_position(MousePosition::new(0.0, 0.0));

    event.set_button(MouseButton::Left);
    let left = encoder.encode(&event).expect("left");
    event.set_button(MouseButton::Middle);
    let middle = encoder.encode(&event).expect("middle");
    event.set_button(MouseButton::Right);
    let right = encoder.encode(&event).expect("right");

    assert_ne!(left, middle);
    assert_ne!(middle, right);
    assert_ne!(left, right);
}

#[test]
fn modifiers_appear_in_the_encoded_sequence() {
    let encoder = sized_encoder(MouseFormat::Sgr);
    let mut event = MouseEvent::new().expect("event");
    event.set_action(MouseAction::Press);
    event.set_button(MouseButton::Left);
    event.set_position(MousePosition::new(0.0, 0.0));

    let plain = encoder.encode(&event).expect("plain");
    event.set_mods(Mods::CTRL);
    let with_ctrl = encoder.encode(&event).expect("ctrl");
    assert_ne!(
        plain, with_ctrl,
        "holding Ctrl must change the reported button code"
    );
}

#[test]
fn sync_from_terminal_picks_up_both_the_tracking_mode_and_the_format() {
    // A real embedder sets both halves with DECSET: the tracking mode decides
    // what is reported, and 1006 selects SGR so coordinates past column 223 stay
    // expressible.
    let mut term = Terminal::new(40, 6).expect("terminal");
    // The full screen size is required, not just the cell size: the encoder
    // silently drops reports outside the configured screen, so a zero screen
    // would make everything but the origin vanish.
    let mut encoder = MouseEncoder::new().expect("encoder");
    encoder.set_size(MouseEncoderSize {
        screen_width: 800,
        screen_height: 480,
        cell_width: 8,
        cell_height: 16,
        ..MouseEncoderSize::default()
    });

    let mut press = MouseEvent::new().expect("event");
    press.set_action(MouseAction::Press);
    press.set_button(MouseButton::Left);
    press.set_position(MousePosition::new(0.0, 0.0));

    let mut motion = MouseEvent::new().expect("event");
    motion.set_action(MouseAction::Motion);
    motion.clear_button();
    motion.set_position(MousePosition::new(8.0, 16.0));

    // Before any terminal mode is enabled the encoder reports nothing at all.
    assert!(
        encoder.encode(&press).expect("nothing").is_empty(),
        "with tracking disabled nothing should be encoded"
    );

    // Button-event tracking plus SGR: presses and drags, no empty motion.
    term.vt_write(b"\x1b[?1002h\x1b[?1006h");
    assert!(term.mouse_tracking().unwrap());
    encoder.sync_from_terminal(&term);
    assert_eq!(
        encoder.encode(&press).expect("press"),
        b"\x1b[<0;1;1M",
        "1006h plus 1002h must produce an SGR press"
    );
    assert!(
        encoder.encode(&motion).expect("motion").is_empty(),
        "1002h alone does not report motion with no button held"
    );

    // Any-event tracking: empty motion is reported too. The tracking modes are
    // alternatives, so a real program clears 1002 before setting 1003; the
    // emulator treats a still-set 1002 as the active mode otherwise.
    term.vt_write(b"\x1b[?1002l\x1b[?1003h");
    encoder.sync_from_terminal(&term);
    let reported = encoder.encode(&motion).expect("motion");
    assert_eq!(
        reported, b"\x1b[<35;2;2M",
        "button code 35 is the motion bit with no button, at cell (2,2)"
    );

    // Turning tracking off again silences the encoder.
    term.vt_write(b"\x1b[?1003l\x1b[?1002l");
    encoder.sync_from_terminal(&term);
    assert!(
        encoder.encode(&press).expect("off").is_empty(),
        "with tracking off nothing should be encoded"
    );
}

#[test]
fn a_zero_screen_size_silently_suppresses_away_from_the_origin() {
    // Documents the trap described on MouseEncoderSize: the encoder drops
    // reports outside the configured screen instead of erroring, so a caller who
    // sets only the cell size gets a press at (0,0) and nothing anywhere else.
    let mut term = Terminal::new(40, 6).expect("terminal");
    term.vt_write(b"\x1b[?1003h\x1b[?1006h");

    let mut encoder = MouseEncoder::new().expect("encoder");
    encoder.set_size(MouseEncoderSize {
        screen_width: 0,
        screen_height: 0,
        cell_width: 8,
        cell_height: 16,
        ..MouseEncoderSize::default()
    });
    encoder.sync_from_terminal(&term);

    let mut motion = MouseEvent::new().expect("event");
    motion.set_action(MouseAction::Motion);
    motion.clear_button();

    motion.set_position(MousePosition::new(0.0, 0.0));
    assert!(
        !encoder.encode(&motion).expect("origin").is_empty(),
        "the origin is inside a zero-sized screen"
    );
    motion.set_position(MousePosition::new(8.0, 16.0));
    assert!(
        encoder.encode(&motion).expect("cell 2,2").is_empty(),
        "anything off the origin is outside a zero-sized screen and is dropped"
    );

    // With the real screen size the same event is reported.
    encoder.set_size(MouseEncoderSize {
        screen_width: 800,
        screen_height: 480,
        cell_width: 8,
        cell_height: 16,
        ..MouseEncoderSize::default()
    });
    assert_eq!(
        encoder.encode(&motion).expect("with bounds"),
        b"\x1b[<35;2;2M"
    );
}

#[test]
fn x10_format_encodes_legacy_sequences() {
    let encoder = sized_encoder(MouseFormat::X10);
    let mut event = MouseEvent::new().expect("event");
    event.set_action(MouseAction::Press);
    event.set_button(MouseButton::Left);
    event.set_position(MousePosition::new(0.0, 0.0));

    let encoded = encoder.encode(&event).expect("encode");
    // X10 is the oldest format: CSI M followed by three bytes offset by 32.
    assert_eq!(encoded, b"\x1b[M\x20\x21\x21");
}

#[test]
fn utf8_format_is_available_and_distinct_from_sgr() {
    let mut event = MouseEvent::new().expect("event");
    event.set_action(MouseAction::Press);
    event.set_button(MouseButton::Left);
    event.set_position(MousePosition::new(0.0, 0.0));

    let sgr = sized_encoder(MouseFormat::Sgr).encode(&event).expect("sgr");
    let utf8 = sized_encoder(MouseFormat::Utf8)
        .encode(&event)
        .expect("utf8");
    assert_ne!(sgr, utf8, "the formats must produce different sequences");
}

#[test]
fn reset_clears_between_event_state() {
    let mut encoder = sized_encoder(MouseFormat::Sgr);
    // Motion deduplication is on by default for some configurations; enabling it
    // explicitly makes the reset observable.
    encoder.set_track_last_cell(true);

    let mut event = MouseEvent::new().expect("event");
    event.set_action(MouseAction::Motion);
    event.clear_button();
    event.set_position(MousePosition::new(0.0, 0.0));

    let first = encoder.encode(&event).expect("first");
    // The same cell again may be deduplicated.
    let second = encoder.encode(&event).expect("second");
    encoder.reset();
    let after_reset = encoder.encode(&event).expect("after reset");
    assert_eq!(
        first, after_reset,
        "after a reset the encoder must report the cell again"
    );
    let _ = second;
}

#[test]
fn tracking_mode_decides_whether_motion_is_reported() {
    // Observed library behaviour in SGR format:
    //   X10 and Normal report nothing for motion;
    //   Button (DECSET 1002) reports a drag but not motion with no button;
    //   Any (DECSET 1003) reports both.
    let mut drag = MouseEvent::new().expect("event");
    drag.set_action(MouseAction::Motion);
    drag.set_button(MouseButton::Left);
    drag.set_position(MousePosition::new(8.0, 16.0));

    let mut empty = MouseEvent::new().expect("event");
    empty.set_action(MouseAction::Motion);
    empty.clear_button();
    empty.set_position(MousePosition::new(8.0, 16.0));

    for (mode, expect_drag, expect_empty) in [
        (MouseTrackingMode::X10, false, false),
        (MouseTrackingMode::Normal, false, false),
        (MouseTrackingMode::Button, true, false),
        (MouseTrackingMode::Any, true, true),
    ] {
        let mut encoder = sized_encoder(MouseFormat::Sgr);
        encoder.set_tracking_mode(mode);
        assert_eq!(
            !encoder.encode(&drag).expect("drag").is_empty(),
            expect_drag,
            "drag reporting under {mode:?}"
        );
        assert_eq!(
            !encoder.encode(&empty).expect("motion").is_empty(),
            expect_empty,
            "empty-motion reporting under {mode:?}"
        );
    }
}

#[test]
fn a_drag_is_reported_with_the_button_and_motion_bits_set() {
    let mut encoder = sized_encoder(MouseFormat::Sgr);
    encoder.set_tracking_mode(MouseTrackingMode::Button);
    let mut drag = MouseEvent::new().expect("event");
    drag.set_action(MouseAction::Motion);
    drag.set_button(MouseButton::Left);
    drag.set_position(MousePosition::new(8.0, 16.0));

    assert_eq!(
        encoder.encode(&drag).expect("drag"),
        b"\x1b[<32;2;2M",
        "button code 32 is the motion bit plus button 0, at cell (2,2)"
    );
}

#[test]
fn any_button_pressed_flag_is_accepted_but_has_no_observed_effect() {
    // Probing the linked library across every format showed this flag does not
    // change the encoded bytes; the tracking mode decides whether motion is
    // reported. The setter is still exercised so the option path is covered, and
    // the assertion documents the observation rather than assuming an effect.
    let mut encoder = sized_encoder(MouseFormat::Sgr);
    encoder.set_tracking_mode(MouseTrackingMode::Any);

    let mut motion = MouseEvent::new().expect("event");
    motion.set_action(MouseAction::Motion);
    motion.clear_button();
    motion.set_position(MousePosition::new(8.0, 16.0));

    let without = encoder.encode(&motion).expect("without");
    encoder.set_any_button_pressed(true);
    let with = encoder.encode(&motion).expect("with");
    assert_eq!(
        without, with,
        "observed: the flag does not affect SGR motion output"
    );
    assert!(!without.is_empty(), "Any mode must still report the motion");
}

#[test]
fn mouse_encoders_and_events_can_be_created_and_dropped_repeatedly() {
    for _ in 0..100 {
        let encoder = sized_encoder(MouseFormat::Sgr);
        let event = MouseEvent::new().expect("event");
        let _ = encoder.encode(&event);
    }
}
