//! End-to-end tests that compose the wrappers the way a real consumer does.
//!
//! The per-module integration suites (`tests/terminal.rs`, `tests/render.rs`,
//! `tests/snapshot.rs`, `tests/search.rs`, `tests/key_encoding.rs`,
//! `tests/mouse_encoding.rs`) each prove their own surface against the real
//! library. This file proves the surfaces *compose*: parse bytes, read the screen
//! back through the render state, persist and restore through a snapshot, search
//! what was written, and answer a program's queries on the write-pty channel.
//!
//! The central helper is [`screen_text`], a small renderer built entirely from
//! public API. It is the honest end-to-end check: if terminal parsing, render
//! state, row iteration, cell iteration, grapheme decoding, or the style and
//! colour accessors were wrong, the extracted text would not match.
//!
//! Gated on the `ghostty_vt_linked` cfg; see `tests/terminal.rs` for why.

#![cfg(ghostty_vt_linked)]

use khostty_vt::key::{Key, KeyAction, KeyEncoder, KeyEvent, Mods};
use khostty_vt::render::RenderState;
use khostty_vt::search::Search;
use khostty_vt::snapshot::{encode, SnapshotDecoder};
use khostty_vt::{Color, Terminal};

/// Extract the visible text of a terminal's active screen.
///
/// Built only from the public API: refresh a render state, walk its rows, bind
/// the reusable cell cursor per row, and decode each cell's grapheme cluster as
/// UTF-8. Trailing whitespace on each row is trimmed and trailing blank rows are
/// dropped, which is what a caller copying a screen out would want.
fn screen_text(term: &Terminal) -> String {
    let mut state = RenderState::new().expect("render state");
    state.update(term).expect("update");

    let mut lines: Vec<String> = Vec::new();
    let mut iter = state.rows().expect("rows");
    while iter.advance() {
        let mut row = String::new();
        {
            let cells = iter.bind_cells().expect("bind cells");
            while cells.advance() {
                if cells.grapheme_len().expect("grapheme len") == 0 {
                    continue;
                }
                row.push_str(&cells.graphemes_utf8().expect("graphemes"));
            }
        }
        lines.push(row.trim_end().to_string());
    }
    while lines.last().is_some_and(|line| line.is_empty()) {
        lines.pop();
    }
    lines.join("\n")
}

#[test]
fn parse_then_read_the_screen() {
    let mut term = Terminal::new(40, 4).expect("terminal");
    term.vt_write(b"$ echo hello\r\nhello\r\n$ ");

    assert_eq!(screen_text(&term), "$ echo hello\nhello\n$");
}

#[test]
fn csi_positioning_and_erasing_are_reflected_in_the_extracted_text() {
    let mut term = Terminal::new(30, 4).expect("terminal");
    term.vt_write(b"first line\r\nsecond line\r\nthird line");
    // Move to row 2 and clear the whole line, then write elsewhere.
    term.vt_write(b"\x1b[2;1H\x1b[2K\x1b[4;1Hbottom");

    assert_eq!(screen_text(&term), "first line\n\nthird line\nbottom");
}

#[test]
fn styled_output_is_readable_and_its_attributes_survive_the_round_trip() {
    let mut term = Terminal::new(40, 3).expect("terminal");
    term.vt_write(b"plain \x1b[1;4;31mstyled\x1b[0m end");

    assert_eq!(screen_text(&term), "plain styled end");

    // The same screen, read through the style accessors.
    let mut state = RenderState::new().expect("render state");
    state.update(&term).expect("update");
    let mut iter = state.rows().expect("rows");
    assert!(iter.advance());

    let mut bold_underlined = 0usize;
    let mut palette_red = 0usize;
    {
        let cells = iter.bind_cells().expect("bind cells");
        while cells.advance() {
            let style = cells.style().expect("style");
            if style.bold && !style.underline.is_none() {
                bold_underlined += 1;
            }
            if matches!(
                style.fg_color,
                khostty_vt::StyleColor::Palette(index) if index == 1
            ) {
                palette_red += 1;
            }
        }
    }
    assert_eq!(
        bold_underlined,
        "styled".len(),
        "every character of the styled run must report bold+underline"
    );
    assert_eq!(
        palette_red,
        "styled".len(),
        "SGR 31 must resolve to palette index 1 on every styled cell"
    );
}

#[test]
fn wide_and_multibyte_text_extracts_correctly() {
    let mut term = Terminal::new(30, 3).expect("terminal");
    term.vt_write("café ".as_bytes());
    term.vt_write("日本".as_bytes());
    term.vt_write(" done".as_bytes());

    assert_eq!(screen_text(&term), "café 日本 done");
    // Wide characters occupy two columns each, so the cursor advanced by the
    // display width, not the byte or char count.
    let cursor_x = term.cursor_x().unwrap();
    assert_eq!(cursor_x, 5 + 4 + 5);
}

#[test]
fn combining_characters_stay_in_one_cell() {
    let mut term = Terminal::new(20, 2).expect("terminal");
    // "e" followed by COMBINING ACUTE ACCENT forms one grapheme cluster.
    term.vt_write("e\u{301}x".as_bytes());

    assert_eq!(screen_text(&term), "e\u{301}x");
    assert_eq!(
        term.cursor_x().unwrap(),
        2,
        "a base plus its combining mark occupies one cell"
    );
}

#[test]
fn scrollback_content_is_reachable_by_scrolling_the_viewport() {
    let mut term = Terminal::new(20, 4).expect("terminal");
    for line in 1..=10 {
        term.vt_write(format!("line{line}\r\n").as_bytes());
    }
    // The last rows are visible; the early ones are in scrollback.
    assert!(term.scrollback_rows().unwrap() > 0);
    let visible = screen_text(&term);
    assert!(visible.contains("line10"), "newest rows should be visible");

    term.scroll_viewport(khostty_vt::Viewport::Top);
    let top = screen_text(&term);
    assert!(
        top.contains("line1"),
        "after scrolling to the top, the oldest rows should be visible, got {top:?}"
    );
}

#[test]
fn snapshot_round_trip_preserves_the_rendered_screen() {
    let mut source = Terminal::new(40, 5).expect("terminal");
    source.vt_write(b"\x1b[2J\x1b[H$ ls -l\r\n");
    source.vt_write(b"\x1b[1;34mdir/\x1b[0m  file.txt\r\n$ ");
    source.set_title("agent pane").unwrap();

    let before = screen_text(&source);
    let bytes = encode(&source).expect("encode");

    let restored = SnapshotDecoder::from_bytes(&bytes)
        .expect("decoder")
        .decode()
        .expect("decode");

    assert_eq!(
        screen_text(&restored),
        before,
        "the rendered screen must survive a snapshot round trip"
    );
    assert_eq!(restored.title().unwrap().as_deref(), Some("agent pane"));
    assert_eq!(
        restored.cursor_position().unwrap(),
        source.cursor_position().unwrap()
    );
}

#[test]
fn snapshot_round_trip_preserves_scrollback_reads() {
    let mut source = Terminal::new(24, 4).expect("terminal");
    for line in 1..=20 {
        source.vt_write(format!("history {line}\r\n").as_bytes());
    }
    let bytes = encode(&source).expect("encode");
    let restored = SnapshotDecoder::from_bytes(&bytes)
        .expect("decoder")
        .decode()
        .expect("decode");

    assert_eq!(
        restored.scrollback_rows().unwrap(),
        source.scrollback_rows().unwrap()
    );

    // Scroll both terminals to the top and compare what a reader would see.
    let mut source = source;
    source.scroll_viewport(khostty_vt::Viewport::Top);
    let mut restored = restored;
    restored.scroll_viewport(khostty_vt::Viewport::Top);
    assert_eq!(screen_text(&restored), screen_text(&source));
}

#[test]
fn search_finds_text_written_through_the_parser_and_reads_it_back() {
    let mut term = Terminal::new(40, 6).expect("terminal");
    term.vt_write(b"error: build failed\r\nwarning: unused import\r\n");
    for line in 0..20 {
        term.vt_write(format!("log line {line}\r\n").as_bytes());
    }
    term.vt_write(b"error: test failed\r\n");

    let mut search = Search::new(&term).expect("search");
    search.set_needle(&term, "error:").expect("needle");
    search.run(&term).expect("run");

    assert_eq!(
        search.total_matches().unwrap(),
        2,
        "both errors should be found, including the one in scrollback"
    );

    search.select_next(&term).expect("select");
    let text = search.selected_text(&term).expect("text").expect("match");
    assert_eq!(text, "error:");
    assert!(search.selected_match().unwrap().is_some());
    assert!(search.selected_index().unwrap().is_some());
    assert_eq!(search.matches().unwrap().len(), 2);
}

#[test]
fn search_and_render_agree_on_scrollback_after_a_snapshot_restore() {
    let mut source = Terminal::new(30, 4).expect("terminal");
    for line in 0..30 {
        source.vt_write(format!("row {line} marker\r\n").as_bytes());
    }

    let bytes = encode(&source).expect("encode");
    let restored = SnapshotDecoder::from_bytes(&bytes)
        .expect("decoder")
        .decode()
        .expect("decode");

    let mut search = Search::new(&restored).expect("search");
    search.set_needle(&restored, "marker").expect("needle");
    search.run(&restored).expect("run");
    assert_eq!(
        search.total_matches().unwrap(),
        30,
        "search must see the restored scrollback"
    );
}

#[test]
fn program_queries_are_answered_on_the_write_pty_channel_and_the_answer_parses_back() {
    use std::cell::RefCell;
    use std::rc::Rc;

    let mut term = Terminal::new(40, 4).expect("terminal");
    let responses: Rc<RefCell<Vec<u8>>> = Rc::new(RefCell::new(Vec::new()));
    let sink = Rc::clone(&responses);
    term.set_write_pty(Some(move |bytes: &[u8]| {
        sink.borrow_mut().extend_from_slice(bytes);
    }));

    // Primary device attributes, then a cursor position report.
    term.vt_write(b"\x1b[c");
    term.vt_write(b"\x1b[3;5H");
    term.vt_write(b"\x1b[6n");

    let bytes = responses.borrow().clone();
    assert!(!bytes.is_empty(), "the terminal must answer DA and CPR");
    assert!(
        bytes.starts_with(b"\x1b["),
        "responses are CSI sequences, got {:?}",
        String::from_utf8_lossy(&bytes)
    );
    assert!(
        bytes.windows(4).any(|window| window == b"[3;5"),
        "the cursor position report should name the row and column just set, got {:?}",
        String::from_utf8_lossy(&bytes)
    );

    // The terminal that produced those answers is unaffected by them.
    assert_eq!(term.cursor_position().unwrap(), (4, 2));
    assert!(screen_text(&term).is_empty(), "no text was printed");
}

#[test]
fn key_encoding_feeds_a_terminal_that_answers_like_a_shell() {
    // Compose key encoding with terminal parsing: encode a key, then feed the
    // encoded bytes to a fresh terminal as if they came from the pty, and read
    // the effect back through the parser.
    let encoder = KeyEncoder::new().expect("encoder");
    let mut event = KeyEvent::new().expect("event");
    event.set_action(KeyAction::Press);
    event.set_key(Key::C);
    event.set_mods(Mods::CTRL);
    event.set_utf8("c");
    let encoded = encoder.encode(&event).expect("encode");
    assert_eq!(encoded, b"\x03");

    let mut term = Terminal::new(40, 3).expect("terminal");
    term.vt_write(b"$ sleep 100");
    // A terminal receiving ETX shows it with caret notation in some modes; the
    // parser records it either way without corrupting the line.
    term.vt_write(&encoded);
    assert!(
        screen_text(&term).starts_with("$ sleep 100"),
        "the control byte must not disturb the existing line"
    );
}

#[test]
fn an_agent_style_session_composes_every_wrapper_once() {
    // One pass through the whole surface, in the order an agent tool would use
    // it: drive a program, read the screen, snapshot it, search it, and turn a
    // desired key into bytes for the pty.
    let mut term = Terminal::new(60, 8).expect("terminal");

    // 1. Program output arrives.
    term.set_title("build").unwrap();
    term.vt_write(b"\x1b[32mPASS\x1b[0m src/lib.rs\r\n");
    term.vt_write(b"\x1b[31mFAIL\x1b[0m src/main.rs\r\n");
    term.vt_write(b"2 tests, 1 failed\r\n$ ");

    // 2. Read the screen.
    let screen = screen_text(&term);
    assert_eq!(
        screen,
        "PASS src/lib.rs\nFAIL src/main.rs\n2 tests, 1 failed\n$"
    );

    // 3. Read colours independently of the text.
    let mut state = RenderState::new().expect("render state");
    state.update(&term).expect("update");
    let colors = state.colors().expect("colors");
    assert_eq!(colors.palette.len(), 256);
    assert_eq!(state.cols().unwrap(), 60);

    // 4. Find the failure. The needle carries a trailing space because matching
    // is a case-insensitive substring search, so bare "FAIL" would also match the
    // "failed" in the summary line.
    let mut search = Search::new(&term).expect("search");
    search.set_needle(&term, "FAIL ").expect("needle");
    search.run(&term).expect("run");
    assert_eq!(
        search.total_matches().unwrap(),
        1,
        "only the failure line should match, not the summary"
    );

    let mut loose = Search::new(&term).expect("search");
    loose.set_needle(&term, "FAIL").expect("needle");
    loose.run(&term).expect("run");
    assert_eq!(
        loose.total_matches().unwrap(),
        2,
        "a bare FAIL also matches the 'failed' in the summary line"
    );

    search.select_next(&term).expect("select");
    assert_eq!(
        search.selected_text(&term).expect("text").as_deref(),
        Some("FAIL ")
    );

    // 5. Persist and restore the whole session.
    let bytes = encode(&term).expect("encode");
    let restored = SnapshotDecoder::from_bytes(&bytes)
        .expect("decoder")
        .decode()
        .expect("decode");
    assert_eq!(screen_text(&restored), screen);

    // 6. Turn a keypress into pty bytes.
    let encoder = KeyEncoder::new().expect("encoder");
    let mut quit = KeyEvent::new().expect("event");
    quit.set_action(KeyAction::Press);
    quit.set_key(Key::C);
    quit.set_mods(Mods::CTRL);
    quit.set_utf8("c");
    assert_eq!(encoder.encode(&quit).expect("encode"), b"\x03");

    // 7. Colours are queryable, and an unset colour is None rather than an
    // error, which is what lets a renderer fall back to its own theme.
    assert_eq!(restored.background().unwrap(), None);
    assert_eq!(restored.foreground().unwrap(), None);
    let mut themed = Terminal::new(20, 3).expect("terminal");
    themed.set_background(Color::rgb(0x10, 0x14, 0x18)).unwrap();
    assert_eq!(
        themed.background().unwrap(),
        Some(Color::rgb(0x10, 0x14, 0x18)),
        "the option sets the program-visible background"
    );

    // An OSC 11 override changes only the current colour, leaving the default
    // untouched, which is how a renderer tells "the program restyled my theme"
    // from "this is my theme".
    let mut overridden = Terminal::new(20, 3).expect("terminal");
    overridden.vt_write(b"\x1b]11;#102030\x07");
    assert_eq!(
        overridden.background().unwrap(),
        Some(Color::rgb(0x10, 0x20, 0x30))
    );
    assert_eq!(
        overridden.default_background().unwrap(),
        None,
        "an OSC override must not touch the default"
    );

    // The render state's theme colours are renderer-supplied: they were observed
    // not to follow either of the above, so this asserts only that the palette
    // needed to resolve cell colours is present.
    let mut state = RenderState::new().expect("render state");
    state.update(&overridden).expect("update");
    assert_eq!(state.colors().unwrap().palette.len(), 256);
}
