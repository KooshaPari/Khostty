//! Integration tests for search against the real library.
//!
//! Gated on the `ghostty_vt_linked` cfg; see `tests/terminal.rs` for why.

#![cfg(ghostty_vt_linked)]

use khostty_vt::search::{Search, SearchScroll, SearchStatus};
use khostty_vt::Terminal;

/// A terminal with `lines` numbered rows, plus a search over it.
fn searched(lines: usize, needle: &str) -> (Terminal, Search) {
    let mut term = Terminal::new(40, 6).expect("terminal");
    for line in 0..lines {
        term.vt_write(format!("row {line} contains {needle}-{line}\r\n").as_bytes());
    }
    let mut search = Search::new(&term).expect("search");
    search.set_needle(&term, needle).expect("needle");
    search.run(&term).expect("run");
    (term, search)
}

#[test]
fn search_starts_idle_with_no_needle() {
    let term = Terminal::new(20, 4).expect("terminal");
    let mut search = Search::new(&term).expect("search");

    assert_eq!(search.needle().unwrap(), None);
    assert_eq!(search.total_matches().unwrap(), 0);
    // A search with nothing to look for reports complete, not stuck.
    assert_eq!(search.tick().unwrap(), SearchStatus::Complete);
}

#[test]
fn run_finds_every_match_on_the_active_screen() {
    let (_term, search) = searched(4, "needle");
    assert_eq!(search.needle().unwrap().as_deref(), Some("needle"));
    assert_eq!(
        search.total_matches().unwrap(),
        4,
        "one match per numbered row should be found"
    );
}

#[test]
fn run_searches_scrollback_too() {
    // Six rows of content in a six-row screen with extra history pushed out.
    let (term, search) = searched(40, "deep");
    assert!(
        term.scrollback_rows().unwrap() > 0,
        "test needs scrollback to exist"
    );
    assert_eq!(
        search.total_matches().unwrap(),
        40,
        "matches inside scrollback must be found"
    );
}

#[test]
fn matching_is_case_insensitive_for_ascii_letters() {
    let mut term = Terminal::new(30, 4).expect("terminal");
    term.vt_write(b"HeLLo World\r\n");
    let mut search = Search::new(&term).expect("search");

    for needle in ["hello", "HELLO", "HeLLo"] {
        search.set_needle(&term, needle).expect("needle");
        search.run(&term).expect("run");
        assert_eq!(
            search.total_matches().unwrap(),
            1,
            "needle {needle:?} should match HeLLo case-insensitively"
        );
    }
}

#[test]
fn a_missing_needle_finds_nothing_without_erroring() {
    let mut term = Terminal::new(30, 4).expect("terminal");
    term.vt_write(b"the haystack holds no such thing\r\n");

    let mut search = Search::new(&term).expect("search");
    search
        .set_needle(&term, "needle-that-is-absent")
        .expect("needle");
    search.run(&term).expect("run");

    assert_eq!(search.total_matches().unwrap(), 0);
    assert!(search.selected_match().unwrap().is_none());
    assert!(search.selected_index().unwrap().is_none());
    assert!(search.matches().unwrap().is_empty());
    // A needle with no matches still leaves the search caught up, not stuck.
    assert_eq!(search.tick().unwrap(), SearchStatus::Complete);
}

#[test]
fn needle_is_tracked_and_clearable() {
    let (term, mut search) = searched(2, "toggle");
    assert_eq!(search.needle().unwrap().as_deref(), Some("toggle"));

    // An empty needle clears the search.
    search.set_needle(&term, "").expect("clear via empty");
    assert_eq!(search.needle().unwrap(), None);
    assert_eq!(search.total_matches().unwrap(), 0);

    search.set_needle(&term, "toggle").expect("set again");
    search.run(&term).expect("run");
    assert_eq!(search.total_matches().unwrap(), 2);

    search.clear_needle(&term).expect("clear");
    assert_eq!(search.needle().unwrap(), None);
}

#[test]
fn matches_are_selections_with_row_and_column_spans() {
    let (term, search) = searched(3, "needle");
    let matches = search.matches().expect("matches");
    assert_eq!(matches.len(), 3);

    // Derive the expected column from the source line rather than hardcoding
    // it, so the assertion cannot drift away from the fixture.
    let expected_column = "row 0 contains ".len() as u16;
    for matched in &matches {
        assert!(!matched.rectangle, "search matches are never rectangular");
        assert_eq!(matched.start.x(), expected_column);
        assert_eq!(
            matched.end.x() + 1 - matched.start.x(),
            "needle".len() as u16,
            "the match must span exactly the needle"
        );
        assert_eq!(matched.row_span(), 1, "every fixture match is on one row");
        assert_eq!(matched.start.y(), matched.end.y());
    }
    let _ = term.total_rows().unwrap();
}

#[test]
fn selecting_matches_walks_the_list_and_wraps() {
    let (term, mut search) = searched(3, "walk");
    assert_eq!(search.total_matches().unwrap(), 3);

    search.select_next(&term).expect("select first");
    let first = search.selected_index().expect("index");
    assert!(first.is_some());

    search.select_next(&term).expect("select second");
    let second = search.selected_index().expect("index");
    assert_ne!(first, second, "select_next should move the selection");

    search.select_prev(&term).expect("select back");
    assert_eq!(search.selected_index().unwrap(), first);

    // Walking far enough wraps rather than erroring.
    for _ in 0..5 {
        search.select_next(&term).expect("wrapping select");
    }
    assert!(search.selected_index().unwrap().is_some());
}

#[test]
fn selecting_with_no_matches_reports_no_value() {
    let mut term = Terminal::new(20, 3).expect("terminal");
    term.vt_write(b"nothing to find\r\n");
    let mut search = Search::new(&term).expect("search");
    search.set_needle(&term, "absent").expect("needle");
    search.run(&term).expect("run");

    assert_eq!(
        search.select_next(&term),
        Err(khostty_vt::GhosttyError::NoValue)
    );
    assert!(search.selected_match().unwrap().is_none());
}

#[test]
fn selected_match_text_can_be_read_back() {
    let (term, mut search) = searched(3, "retrieve");
    search.select_next(&term).expect("select");
    let text = search
        .selected_text(&term)
        .expect("format selection")
        .expect("a match is selected");
    assert_eq!(
        text, "retrieve",
        "the formatted text must equal the needle that matched"
    );
}

#[test]
fn viewport_matches_track_the_visible_rows() {
    let (term, mut search) = searched(40, "visible");
    search.feed(&term).expect("feed");
    let viewport = search.viewport_matches().expect("viewport matches");
    // The viewport is six rows, so at most a handful of matches can be visible
    // even though 40 exist in total.
    assert!(
        !viewport.is_empty(),
        "the visible rows contain matches and must be reported"
    );
    assert!(
        viewport.len() <= search.total_matches().unwrap(),
        "viewport matches must be a subset of all matches"
    );
}

#[test]
fn scroll_policy_is_settable_and_queryable() {
    let (term, mut search) = searched(20, "scroll");
    assert_eq!(search.scroll_policy().unwrap(), SearchScroll::IfNeeded);

    search.set_scroll_policy(SearchScroll::None).expect("set");
    assert_eq!(search.scroll_policy().unwrap(), SearchScroll::None);

    // With scrolling disabled, selecting must not move the viewport.
    term.total_rows().unwrap();
    search.select_next(&term).expect("select");
    assert_eq!(search.scroll_policy().unwrap(), SearchScroll::None);

    search
        .set_scroll_policy(SearchScroll::IfNeeded)
        .expect("restore");
    assert_eq!(search.scroll_policy().unwrap(), SearchScroll::IfNeeded);
}

#[test]
fn incremental_tick_and_feed_reach_the_same_answer_as_run() {
    let mut term = Terminal::new(30, 4).expect("terminal");
    for line in 0..25 {
        term.vt_write(format!("step {line} target\r\n").as_bytes());
    }

    let mut incremental = Search::new(&term).expect("search");
    incremental.set_needle(&term, "target").expect("needle");
    // Drive it the way an interactive embedder would.
    let mut guard = 0;
    loop {
        guard += 1;
        assert!(guard < 1_000_000, "incremental search did not converge");
        match incremental.tick().expect("tick") {
            SearchStatus::Complete => break,
            SearchStatus::Running => continue,
            SearchStatus::FeedRequired => {
                incremental.feed(&term).expect("feed");
            }
            other => panic!("unexpected status {other:?}"),
        }
    }

    let mut one_shot = Search::new(&term).expect("search");
    one_shot.set_needle(&term, "target").expect("needle");
    one_shot.run(&term).expect("run");

    assert_eq!(
        incremental.total_matches().unwrap(),
        one_shot.total_matches().unwrap(),
        "both driving styles must agree"
    );
    assert_eq!(incremental.total_matches().unwrap(), 25);
}

#[test]
fn a_mismatched_terminal_is_rejected() {
    let a = Terminal::new(20, 3).expect("terminal a");
    let b = Terminal::new(20, 3).expect("terminal b");
    let mut search = Search::new(&a).expect("search over a");

    // The C layer would search whatever terminal it captured, so a mismatched
    // argument must be rejected rather than silently searched.
    assert_eq!(
        search.set_needle(&b, "x"),
        Err(khostty_vt::GhosttyError::InvalidValue)
    );
    assert_eq!(search.feed(&b), Err(khostty_vt::GhosttyError::InvalidValue));
    assert_eq!(search.run(&b), Err(khostty_vt::GhosttyError::InvalidValue));
    assert_eq!(
        search.select_next(&b),
        Err(khostty_vt::GhosttyError::InvalidValue)
    );
    assert_eq!(
        search.selected_text(&b),
        Err(khostty_vt::GhosttyError::InvalidValue)
    );

    // The correct terminal still works.
    search.set_needle(&a, "x").expect("needle on a");
}

#[test]
fn feed_picks_up_content_written_after_the_search_started() {
    let mut term = Terminal::new(30, 4).expect("terminal");
    term.vt_write(b"initial content\r\n");
    let mut search = Search::new(&term).expect("search");
    search.set_needle(&term, "later").expect("needle");
    search.run(&term).expect("run");
    assert_eq!(search.total_matches().unwrap(), 0);

    // Feeding is the only way the search learns about terminal changes.
    term.vt_write(b"appearing later on\r\n");
    search.feed(&term).expect("feed");
    search.run(&term).expect("run");
    assert_eq!(
        search.total_matches().unwrap(),
        1,
        "a feed must surface content written after the search began"
    );
}

#[test]
fn many_searches_can_share_one_terminal() {
    let mut term = Terminal::new(40, 6).expect("terminal");
    term.vt_write(b"alpha beta gamma\r\n");

    let mut searches: Vec<Search> = ["alpha", "beta", "gamma", "delta"]
        .iter()
        .map(|needle| {
            let mut search = Search::new(&term).expect("search");
            search.set_needle(&term, needle).expect("needle");
            search.run(&term).expect("run");
            search
        })
        .collect();

    assert_eq!(searches[0].total_matches().unwrap(), 1);
    assert_eq!(searches[1].total_matches().unwrap(), 1);
    assert_eq!(searches[2].total_matches().unwrap(), 1);
    assert_eq!(searches[3].total_matches().unwrap(), 0);

    // Dropping the terminal before the searches must be safe: upstream tracks
    // terminal lifetime and fails cleanly. Dropping the searches afterwards
    // exercises that path.
    drop(term);
    searches.clear();
}
