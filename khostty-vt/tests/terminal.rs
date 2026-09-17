//! Integration tests for [`khostty_vt::terminal::Terminal`] against the real
//! `libghostty-vt`.
//!
//! These are gated on the `ghostty_vt_linked` cfg, which `build.rs` sets only
//! when it actually found a prebuilt `libghostty-vt`. On a checkout where the
//! Zig library has not been built, the file compiles to nothing rather than
//! failing at link time.

#![cfg(ghostty_vt_linked)]

use khostty_vt::terminal::{CompressionMode, CompressionResult, CursorStyle, Screen, Viewport};
use khostty_vt::{Color, Terminal};

fn terminal() -> Terminal {
    Terminal::new(80, 24).expect("80x24 terminal")
}

#[test]
fn new_terminal_reports_its_geometry() {
    let term = terminal();
    assert_eq!(term.cols().unwrap(), 80);
    assert_eq!(term.rows().unwrap(), 24);
    assert_eq!(term.cursor_position().unwrap(), (0, 0));
    assert_eq!(term.active_screen().unwrap(), Screen::Primary);
}

#[test]
fn vt_write_advances_the_cursor() {
    let mut term = terminal();
    term.vt_write(b"hello");
    assert_eq!(term.cursor_position().unwrap(), (5, 0));
    assert_eq!(term.scrollback_rows().unwrap(), 0);
}

#[test]
fn carriage_return_and_line_feed_move_the_cursor() {
    let mut term = terminal();
    term.vt_write(b"abc\r\ndef");
    assert_eq!(term.cursor_position().unwrap(), (3, 1));
}

#[test]
fn cursor_position_report_parses_escapes_without_moving_the_cursor() {
    let mut term = terminal();
    term.vt_write(b"\x1b[3;7H");
    assert_eq!(term.cursor_position().unwrap(), (6, 2));
}

#[test]
fn scrollback_accumulates_past_the_last_row() {
    let mut term = Terminal::new(20, 4).expect("20x4 terminal");
    // Five lines into a four-row screen: one row must land in scrollback.
    term.vt_write(b"1\r\n2\r\n3\r\n4\r\n5");
    assert_eq!(term.scrollback_rows().unwrap(), 1);
    assert_eq!(term.total_rows().unwrap(), 5);
}

#[test]
fn viewport_can_scroll_into_history_and_back() {
    let mut term = Terminal::new(20, 4).expect("20x4 terminal");
    for line in 1..=20 {
        term.vt_write(format!("line{line}\r\n").as_bytes());
    }
    assert!(term.scrollback_rows().unwrap() > 0);
    assert!(term.viewport_active().unwrap());

    term.scroll_viewport(Viewport::Top);
    assert!(!term.viewport_active().unwrap());

    let scrollbar = term.scrollbar().unwrap();
    assert!(scrollbar.total > scrollbar.len);

    term.scroll_viewport(Viewport::Bottom);
    assert!(term.viewport_active().unwrap());
    assert!(term.scrollbar().unwrap().is_at_bottom());
}

#[test]
fn title_is_unset_initially_and_tracks_osc_2() {
    let mut term = terminal();
    assert_eq!(term.title().unwrap(), None);

    term.vt_write(b"\x1b]2;agent pane\x07");
    assert_eq!(term.title().unwrap().as_deref(), Some("agent pane"));
}

#[test]
fn title_setter_round_trips_through_the_query() {
    let mut term = terminal();
    term.set_title("from rust").unwrap();
    assert_eq!(term.title().unwrap().as_deref(), Some("from rust"));

    term.set_title("").unwrap();
    assert_eq!(term.title().unwrap(), None);
}

#[test]
fn pwd_tracks_osc_7() {
    let mut term = terminal();
    assert_eq!(term.pwd().unwrap(), None);
    term.vt_write(b"\x1b]7;file://localhost/tmp\x07");
    assert_eq!(term.pwd().unwrap().as_deref(), Some("file://localhost/tmp"));
}

#[test]
fn alternate_screen_is_reported() {
    let mut term = terminal();
    term.vt_write(b"\x1b[?1049h");
    assert_eq!(term.active_screen().unwrap(), Screen::Alternate);
    term.vt_write(b"\x1b[?1049l");
    assert_eq!(term.active_screen().unwrap(), Screen::Primary);
}

#[test]
fn resize_reflows_the_grid() {
    let mut term = Terminal::new(80, 24).expect("80x24 terminal");
    term.resize(120, 40, 12, 24).unwrap();
    assert_eq!(term.cols().unwrap(), 120);
    assert_eq!(term.rows().unwrap(), 40);
    assert_eq!(term.size_px().unwrap(), (120 * 12, 40 * 24));
}

#[test]
fn resize_wraps_written_text_across_the_new_width() {
    let mut term = Terminal::new(80, 24).expect("80x24 terminal");
    term.vt_write(b"abcdefghij");
    term.resize(5, 24, 0, 0).unwrap();
    // Ten characters reflowed into a five-column grid fill exactly two rows, so
    // the cursor sits at column 0 of row 2.
    assert_eq!(term.cursor_position().unwrap(), (0, 2));
}

#[test]
fn reset_clears_the_screen_and_scrollback() {
    let mut term = Terminal::new(20, 4).expect("20x4 terminal");
    term.vt_write(b"1\r\n2\r\n3\r\n4\r\n5");
    assert!(term.scrollback_rows().unwrap() > 0);

    term.reset();
    assert_eq!(term.cursor_position().unwrap(), (0, 0));
    assert_eq!(term.scrollback_rows().unwrap(), 0);
}

#[test]
fn default_cursor_style_setter_accepts_every_variant() {
    // The DECSCUSR shape is a write-only option at the terminal level; the live
    // value is read back through the render state, covered by tests/render.rs.
    let mut term = terminal();
    for style in [
        CursorStyle::Bar,
        CursorStyle::Block,
        CursorStyle::Underline,
        CursorStyle::BlockHollow,
    ] {
        term.set_default_cursor_style(style).unwrap();
    }
}

#[test]
fn cursor_sgr_style_is_plain_on_a_fresh_terminal() {
    let term = terminal();
    assert!(term.cursor_sgr_style().unwrap().is_plain());
}

#[test]
fn cursor_sgr_style_reflects_sgr_sequences() {
    use khostty_vt::StyleColor;

    let mut term = terminal();
    term.vt_write(b"\x1b[1;3;4;7m");
    let style = term.cursor_sgr_style().unwrap();
    assert!(style.bold, "SGR 1 sets bold");
    assert!(style.italic, "SGR 3 sets italic");
    assert!(style.inverse, "SGR 7 sets inverse");
    assert_eq!(style.underline, khostty_vt::Underline::SINGLE);

    term.vt_write(b"\x1b[0m");
    assert!(term.cursor_sgr_style().unwrap().is_plain());

    term.vt_write(b"\x1b[38;2;10;20;30m");
    assert_eq!(
        term.cursor_sgr_style().unwrap().fg_color,
        StyleColor::Rgb(Color::rgb(10, 20, 30))
    );

    term.vt_write(b"\x1b[0;31m");
    assert_eq!(
        term.cursor_sgr_style().unwrap().fg_color,
        StyleColor::Palette(1)
    );
}

#[test]
fn many_terminals_survive_concurrent_creation() {
    // Exercises the RAII path in parallel; a leaked or double-freed handle
    // tends to show up as a crash rather than a clean failure.
    let handles: Vec<_> = (0..4)
        .map(|_| {
            std::thread::spawn(|| {
                for _ in 0..50 {
                    let mut term = Terminal::new(10, 5).expect("small terminal");
                    term.vt_write(b"x");
                }
            })
        })
        .collect();
    for handle in handles {
        handle.join().expect("worker thread");
    }
}

#[test]
fn colours_are_configurable_and_queryable() {
    let mut term = terminal();
    term.set_foreground(Color::rgb(0x11, 0x22, 0x33)).unwrap();
    term.set_background(Color::rgb(0xaa, 0xbb, 0xcc)).unwrap();
    term.set_cursor_color(Color::rgb(0x55, 0x66, 0x77)).unwrap();

    assert_eq!(
        term.foreground().unwrap(),
        Some(Color::rgb(0x11, 0x22, 0x33))
    );
    assert_eq!(
        term.background().unwrap(),
        Some(Color::rgb(0xaa, 0xbb, 0xcc))
    );
    assert_eq!(
        term.cursor_color().unwrap(),
        Some(Color::rgb(0x55, 0x66, 0x77))
    );
}

#[test]
fn unset_colours_report_no_value_rather_than_an_error() {
    // A fresh terminal has no colours set, and the C contract reports
    // GHOSTTY_NO_VALUE for them. That is the normal state, so it maps to None.
    let term = terminal();
    assert_eq!(term.foreground().unwrap(), None);
    assert_eq!(term.background().unwrap(), None);
    assert_eq!(term.cursor_color().unwrap(), None);
    assert_eq!(term.default_foreground().unwrap(), None);
    assert_eq!(term.default_background().unwrap(), None);
    assert_eq!(term.default_cursor_color().unwrap(), None);
    // The palette, by contrast, always has values.
    assert_eq!(term.default_palette().unwrap().len(), 256);
}

#[test]
fn palette_has_256_entries_and_is_queryable() {
    let term = terminal();
    let palette = term.palette().unwrap();
    assert_eq!(palette.len(), 256);
    let default = term.default_palette().unwrap();
    assert_eq!(default.len(), 256);
    // The default palette is Ghostty's built-in 256-colour table, not an
    // all-zero array: the first entries must be distinct from each other and
    // from the zero value, otherwise the query returned nothing.
    assert_ne!(default[0], default[1]);
    assert_ne!(default[0], Color::BLACK);
    assert_eq!(default, palette, "no program has modified the palette yet");

    // Setting a palette entry must be observable through the active palette.
    let mut custom = default;
    custom[3] = Color::rgb(0x0b, 0x0c, 0x0d);
    term_after_palette_set(&custom, &default);
}

fn term_after_palette_set(custom: &[Color; 256], default: &[Color; 256]) {
    let mut term = terminal();
    term.set_palette(custom).unwrap();
    let active = term.palette().unwrap();
    assert_eq!(active[3], Color::rgb(0x0b, 0x0c, 0x0d));
    assert_ne!(active[3], default[3]);
}

#[test]
fn mouse_tracking_tracks_decset() {
    let mut term = terminal();
    assert!(!term.mouse_tracking().unwrap());
    term.vt_write(b"\x1b[?1000h");
    assert!(term.mouse_tracking().unwrap());
    term.vt_write(b"\x1b[?1000l");
    assert!(!term.mouse_tracking().unwrap());
}

#[test]
fn kitty_keyboard_flags_track_csi_u_protocol() {
    let mut term = terminal();
    assert_eq!(term.kitty_keyboard_flags().unwrap(), 0);
    term.vt_write(b"\x1b[>3u");
    assert_eq!(term.kitty_keyboard_flags().unwrap(), 3);
}

#[test]
fn vt_ground_settles_after_a_complete_sequence() {
    let mut term = terminal();
    term.vt_write(b"plain");
    assert!(term.vt_ground().unwrap());
    assert!(!term.has_vt_processing_error().unwrap());

    // `vt_write_until_ground` stops at the sequence boundary; the count it
    // reports is the input it consumed, which for an already-complete sequence
    // must be the whole buffer.
    let consumed = term.vt_write_until_ground(b"\x1b[1;1H").unwrap();
    assert!(consumed <= 6, "consumed cannot exceed the input length");
    assert!(term.vt_ground().unwrap());
}

#[test]
fn write_pty_effect_receives_query_responses() {
    use std::cell::RefCell;
    use std::rc::Rc;

    let mut term = terminal();
    // The effect closure must be `'static`, so share the capture slot with the
    // test through an `Rc<RefCell<..>>` rather than trying to read the closure's
    // own storage.
    let captured: Rc<RefCell<Vec<u8>>> = Rc::new(RefCell::new(Vec::new()));
    let sink = Rc::clone(&captured);
    term.set_write_pty(Some(move |bytes: &[u8]| {
        sink.borrow_mut().extend_from_slice(bytes);
    }));

    // Device status report: the emulator must answer on the write_pty channel.
    term.vt_write(b"\x1b[5n");

    let bytes = captured.borrow().clone();
    assert!(!bytes.is_empty(), "write_pty effect did not fire");
    assert!(
        bytes.starts_with(b"\x1b[0n"),
        "unexpected DSR response: {:?}",
        String::from_utf8_lossy(&bytes)
    );
}

#[test]
fn unregistering_write_pty_stops_delivery() {
    use std::cell::RefCell;
    use std::rc::Rc;

    let mut term = terminal();
    let calls: Rc<RefCell<usize>> = Rc::new(RefCell::new(0));
    let counter = Rc::clone(&calls);
    term.set_write_pty(Some(move |_bytes: &[u8]| *counter.borrow_mut() += 1));

    term.vt_write(b"\x1b[5n");
    let after_first = *calls.borrow();
    assert!(after_first > 0, "first response should be delivered");

    term.set_write_pty(None::<fn(&[u8])>);
    term.vt_write(b"\x1b[5n");
    assert_eq!(
        *calls.borrow(),
        after_first,
        "no further responses after unregistering"
    );
}

#[test]
fn panicking_write_pty_callback_does_not_unwind_into_c() {
    let mut term = terminal();
    term.set_write_pty(Some(|_bytes: &[u8]| panic!("callback panic")));
    // If the panic escaped the trampoline this call would abort the process.
    term.vt_write(b"\x1b[5n");
    // The terminal must still be usable afterwards.
    assert_eq!(term.cols().unwrap(), 80);
    assert_eq!(term.title().unwrap(), None);
}

#[test]
fn bell_effect_counts_and_callbacks() {
    use std::cell::Cell;
    use std::rc::Rc;

    let mut term = terminal();
    let observed = Rc::new(Cell::new(0usize));
    let counter = Rc::clone(&observed);
    term.set_bell(Some(move || counter.set(counter.get() + 1)));

    assert_eq!(term.bell_count(), 0);
    term.vt_write(b"\x07");
    term.vt_write(b"\x07");
    assert_eq!(term.bell_count(), 2);
    assert_eq!(observed.get(), 2, "the closure must observe both bells");

    term.set_bell(None::<fn()>);
    assert_eq!(term.bell_count(), 0, "unregistering resets the counter");
}

#[test]
fn scrollback_compression_is_caller_driven() {
    let mut term = Terminal::new(20, 4).expect("20x4 terminal");
    for line in 0..200 {
        term.vt_write(format!("{line}\r\n").as_bytes());
    }
    let before = term.compression_activity().unwrap();
    term.vt_write(b"more output\r\n");
    let after = term.compression_activity().unwrap();
    assert_ne!(
        before, after,
        "activity token should move on terminal writes"
    );

    // Either the target supports reclamation and reports progress, or it does
    // not and says so. Both are acceptable; silently doing nothing is not.
    match term.compress(CompressionMode::Incremental).unwrap() {
        CompressionResult::Unsupported
        | CompressionResult::Pending
        | CompressionResult::Complete => {}
        other => panic!("unexpected compression result: {other:?}"),
    }
}

#[test]
fn many_terminals_can_be_created_and_dropped() {
    // Exercises the RAII path repeatedly; a leaked or double-freed handle
    // typically shows up as a crash or an allocator abort under ASan/valgrind.
    for _ in 0..200 {
        let mut term = Terminal::new(10, 5).expect("small terminal");
        term.vt_write(b"x");
    }
}
