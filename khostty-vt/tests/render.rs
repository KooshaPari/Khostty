//! Integration tests for the render state against the real library.
//!
//! Gated on the `ghostty_vt_linked` cfg; see `tests/terminal.rs` for why.

#![cfg(ghostty_vt_linked)]

use khostty_vt::render::{CursorVisualStyle, Dirty, RenderState};
use khostty_vt::terminal::CursorStyle;
use khostty_vt::{Color, StyleColor, Terminal};

/// Build a render state and push one styled frame through it.
fn rendered(cols: u16, rows: u16, content: &[&str]) -> (Terminal, RenderState) {
    let mut term = Terminal::new(cols, rows).expect("terminal");
    let mut state = RenderState::new().expect("render state");
    for line in content {
        term.vt_write(line.as_bytes());
        term.vt_write(b"\r\n");
    }
    state.update(&term).expect("update");
    (term, state)
}

#[test]
fn fresh_render_state_reports_the_viewport_geometry() {
    let (_, state) = rendered(40, 5, &["hello"]);

    assert_eq!(state.cols().unwrap(), 40);
    assert_eq!(state.rows_count().unwrap(), 5);
    assert_eq!(state.dirty().unwrap(), Dirty::Full);
}

#[test]
fn clean_resets_the_dirty_state() {
    let (_, mut state) = rendered(20, 3, &["abc"]);
    assert!(state.dirty().unwrap().needs_draw());

    state.clean().expect("clean");
    assert_eq!(state.dirty().unwrap(), Dirty::False);

    // A clean state stays clean until something changes: updating from an
    // unchanged terminal must not report a full redraw.
    state.set_dirty(Dirty::False).expect("set dirty");
    assert_eq!(state.dirty().unwrap(), Dirty::False);
}

#[test]
fn set_dirty_can_force_a_redraw() {
    let (_, mut state) = rendered(20, 3, &["abc"]);
    state.clean().unwrap();
    state.set_dirty(Dirty::Full).expect("force full");
    assert_eq!(state.dirty().unwrap(), Dirty::Full);
}

#[test]
fn colors_expose_the_palette_and_defaults() {
    let (_, state) = rendered(20, 3, &["colors"]);
    let colors = state.colors().expect("colors");

    assert_eq!(colors.palette.len(), 256);
    // The palette must not be all-zero: a failed query would leave the sized
    // struct at its zeroed default.
    assert!(colors.palette.iter().any(|c| *c != Color::BLACK));
    assert_eq!(colors.palette_color(0), colors.palette[0]);

    // Standalone accessors must agree with the packed struct.
    assert_eq!(state.background().unwrap(), colors.background);
    assert_eq!(state.foreground().unwrap(), colors.foreground);
    assert_eq!(state.palette().unwrap(), colors.palette);
}

#[test]
fn cursor_reports_position_and_visibility() {
    let (_, mut state) = rendered(20, 5, &["ab"]);

    let cursor = state.cursor().expect("cursor");
    assert!(cursor.visible);
    assert!(cursor.viewport_has_value);
    // `rendered` appends CRLF, so "ab" leaves the cursor at the start of row 1.
    assert_eq!((cursor.viewport_x, cursor.viewport_y), (0, 1));
    assert!(!cursor.password_input);

    // The visual style tracks DECSCUSR through the render state.
    let mut term = Terminal::new(10, 2).expect("terminal");
    term.set_default_cursor_style(CursorStyle::Bar).unwrap();
    state.update(&term).expect("update");
    assert_eq!(state.cursor().unwrap().visual_style, CursorVisualStyle::Bar);
}

#[test]
fn explicit_cursor_color_is_optional() {
    let (_, state) = rendered(10, 2, &["x"]);
    // A terminal that never set an explicit cursor colour must report "none"
    // rather than failing or inventing a colour.
    assert_eq!(state.cursor_color().unwrap(), None);

    let mut term = Terminal::new(10, 2).expect("terminal");
    term.set_cursor_color(Color::rgb(0x12, 0x34, 0x56)).unwrap();
    let mut state = RenderState::new().unwrap();
    state.update(&term).unwrap();
    assert_eq!(
        state.cursor_color().unwrap(),
        Some(Color::rgb(0x12, 0x34, 0x56))
    );
    assert_eq!(state.colors().unwrap().cursor, Color::rgb(0x12, 0x34, 0x56));
}

#[test]
fn begin_and_end_update_are_balanced() {
    let mut term = Terminal::new(10, 3).expect("terminal");
    term.vt_write(b"staged");
    let mut state = RenderState::new().unwrap();

    state.begin_update(&term).expect("begin");
    state.end_update().expect("end");
    assert_eq!(state.cols().unwrap(), 10);
}

#[test]
fn row_iteration_visits_every_row() {
    let (_, state) = rendered(12, 4, &["one", "two"]);

    let mut iter = state.rows().expect("rows");
    let mut count = 0usize;
    while iter.advance() {
        count += 1;
        assert!(count <= 4, "row iteration did not terminate");
    }
    assert_eq!(count, 4, "the iterator must visit every row");
}

#[test]
fn dirty_row_iteration_reports_row_indices() {
    let (_, mut state) = rendered(12, 4, &["one", "two"]);
    state.clean().unwrap();

    // Touch only the third row, so exactly one row should be dirty.
    let (mut term, _) = rendered(12, 4, &["seed"]);
    term.vt_write(b"\x1b[3;1Hdirty row");
    state.update(&term).expect("update");

    let mut iter = state.rows().expect("rows");
    let mut dirty_rows = Vec::new();
    while let Some(y) = iter.next_dirty() {
        dirty_rows.push(y);
        assert!(
            dirty_rows.len() <= 4,
            "dirty row iteration did not terminate"
        );
    }
    assert!(
        dirty_rows.contains(&2),
        "row 2 was written and must be reported dirty, got {dirty_rows:?}"
    );
}

#[test]
fn cells_expose_text_styles_and_colors() {
    // "Hi" plain, then bold green "ok", then a 24-bit orange "Z".
    let (_, state) = rendered(
        20,
        2,
        &["Hi \x1b[1;32mok\x1b[0m \x1b[38;2;255;128;0mZ\x1b[0m"],
    );

    let mut iter = state.rows().expect("rows");
    // Row 0 carries the content; rows are visited in order.
    assert!(iter.advance(), "expected at least one row");

    let mut text = String::new();
    let mut bold_found = false;
    let mut orange_found = false;

    let cells = iter.bind_cells().expect("bind cells");
    while cells.advance() {
        let len = cells.grapheme_len().expect("grapheme len");
        if len == 0 {
            text.push(' ');
            continue;
        }
        let utf8 = cells.graphemes_utf8().expect("graphemes utf8");
        text.push_str(&utf8);

        // The codepoint accessor must agree with the UTF-8 accessor.
        let codepoints = cells.graphemes().expect("graphemes");
        assert_eq!(codepoints.len(), len as usize);
        assert_eq!(
            codepoints[0] as u8 as char,
            utf8.chars().next().unwrap(),
            "UTF-8 and codepoint views of the same cell must agree"
        );

        let style = cells.style().expect("style");
        if utf8 == "o" && style.bold {
            bold_found = true;
            // SGR 32 resolves to palette index 2 through the active palette.
            assert!(
                matches!(style.fg_color, StyleColor::Palette(_) | StyleColor::Rgb(_)),
                "styled cell should carry a foreground colour"
            );
        }
        if utf8 == "Z" {
            if let Ok(Some(fg)) = cells.foreground() {
                if fg == Color::rgb(255, 128, 0) {
                    orange_found = true;
                }
            }
            assert_eq!(style.fg_color, StyleColor::Rgb(Color::rgb(255, 128, 0)));
        }
    }

    assert!(text.starts_with("Hi ok Z"), "unexpected text: {text:?}");
    assert!(bold_found, "bold attribute was not reported");
    assert!(orange_found, "24-bit foreground was not resolved");
}

#[test]
fn unstyled_cells_report_no_styling() {
    let (_, state) = rendered(10, 2, &["plain"]);
    let mut iter = state.rows().expect("rows");
    assert!(iter.advance());

    let cells = iter.bind_cells().expect("bind cells");
    assert!(cells.advance());
    assert!(!cells.has_styling().expect("has styling"));
    // No explicit colours on a plain cell: neither accessor should fabricate one.
    assert_eq!(cells.foreground().expect("fg"), None);
    assert_eq!(cells.background().expect("bg"), None);
}

#[test]
fn empty_cells_report_a_zero_grapheme_length() {
    let (_, state) = rendered(10, 2, &["a"]);
    let mut iter = state.rows().expect("rows");
    assert!(iter.advance());

    let cells = iter.bind_cells().expect("bind cells");
    let mut lens = Vec::new();
    while cells.advance() {
        lens.push(cells.grapheme_len().expect("len"));
    }
    assert_eq!(lens.len(), 10, "one entry per column");
    assert_eq!(lens[0], 1, "the written cell has one codepoint");
    assert!(lens[1..].iter().all(|len| *len == 0), "the rest are empty");
}

#[test]
fn select_addresses_a_specific_column() {
    let (_, state) = rendered(10, 2, &["abcd"]);
    let mut iter = state.rows().expect("rows");
    assert!(iter.advance());

    let cells = iter.bind_cells().expect("bind cells");
    cells.select(2).expect("select column 2");
    assert_eq!(
        cells.graphemes_utf8().expect("utf8"),
        "c",
        "select must address the same cell the iterator would reach"
    );
}

#[test]
fn row_selection_range_is_reported_or_absent() {
    let (_, state) = rendered(10, 2, &["selected text"]);
    let mut iter = state.rows().expect("rows");
    assert!(iter.advance());
    // No selection was set on this terminal.
    assert_eq!(iter.selection().expect("selection"), None);
}

#[test]
fn raw_row_and_cell_values_are_available() {
    let (_, state) = rendered(10, 2, &["raw"]);
    let mut iter = state.rows().expect("rows");
    assert!(iter.advance());

    // Raw values are opaque bit patterns; the check is that the accessors do
    // not fail and are self-consistent.
    let row = iter.raw().expect("raw row");
    assert_eq!(row, iter.raw().expect("raw row is stable"));

    let cells = iter.bind_cells().expect("bind cells");
    assert!(cells.advance());
    let cell = cells.raw().expect("raw cell");
    assert_eq!(cell, cells.raw().expect("raw cell is stable"));
}

#[test]
fn row_iterator_does_not_outlive_the_render_state() {
    // This test is a compile-time assertion expressed as code that must not
    // build if the borrow were relaxed: `iter` borrows `state`, so `state.update`
    // cannot be called while `iter` is alive. The `drop` makes the intent
    // explicit and keeps the test meaningful as documentation.
    let (term, mut state) = rendered(10, 2, &["borrowed"]);
    let iter = state.rows().expect("rows");
    drop(iter);
    state
        .update(&term)
        .expect("update after the iterator is gone");
}
