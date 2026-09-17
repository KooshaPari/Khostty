"""Tests for scrollback search."""

from __future__ import annotations

import pytest

from khostty_vt import GhosttyError, Result, Search, SearchScroll, SearchStatus, Terminal


def test_finds_matches_case_insensitively(make_terminal: object, transcript: str) -> None:
    term = make_terminal(80, 24, transcript)

    with term.search("error") as found:
        found.run()

        assert found.total_matches() == 3
        assert found.status() == SearchStatus.COMPLETE


def test_a_fresh_search_is_idle(make_terminal: object) -> None:
    term = make_terminal(80, 24, "anything\r\n")

    with term.search() as found:
        assert found.needle is None
        assert found.status() == SearchStatus.COMPLETE
        assert found.total_matches() == 0
        assert found.selected_index() is None


def test_needle_round_trips(make_terminal: object) -> None:
    term = make_terminal(80, 24, "findme\r\n")

    with term.search() as found:
        found.set_needle("findme")
        assert found.needle == "findme"

        found.set_needle("")
        assert found.needle is None
        assert found.status() == SearchStatus.COMPLETE


def test_needle_can_be_passed_to_the_constructor(make_terminal: object) -> None:
    term = make_terminal(80, 24, "alpha\r\nbeta\r\n")

    with term.search("beta") as found:
        found.run()
        assert found.needle == "beta"
        assert found.total_matches() == 1


def test_needs_a_feed_to_see_the_terminal(make_terminal: object) -> None:
    """A needle alone is not enough; the search only learns on feed."""
    term = make_terminal(80, 24, "payload\r\n")

    with term.search("payload") as found:
        assert found.total_matches() == 0
        assert found.status() != SearchStatus.RUNNING

        found.feed()

        assert found.total_matches() == 1


def test_select_next_walks_newest_to_oldest_and_wraps(make_terminal: object) -> None:
    term = make_terminal(80, 24, "error one\r\nerror two\r\nerror three\r\n")

    with term.search("error") as found:
        found.set_scroll_policy(SearchScroll.NONE)
        found.run()
        assert found.total_matches() == 3
        assert found.selected_index() is None

        assert [found.select_next() for _ in range(4)] == [0, 1, 2, 0]


def test_select_prev_walks_the_other_way(make_terminal: object) -> None:
    term = make_terminal(80, 24, "hit one\r\nhit two\r\nhit three\r\n")

    with term.search("hit") as found:
        found.set_scroll_policy(SearchScroll.NONE)
        found.run()
        found.select_next()
        found.select_next()

        assert found.selected_index() == 1
        assert found.select_prev() == 0
        # Wrapping backwards lands on the oldest match.
        assert found.select_prev() == 2


def test_no_matches_yields_none_and_no_selection(make_terminal: object) -> None:
    term = make_terminal(80, 24, "nothing to see\r\n")

    with term.search("absent-needle") as found:
        found.run()

        assert found.total_matches() == 0
        assert found.select_next() is None
        assert found.select_prev() is None
        assert found.selected_index() is None


def test_viewport_matches_are_bounded_by_the_total(make_terminal: object) -> None:
    term = make_terminal(80, 24, "error one\r\nerror two\r\n")

    with term.search("error") as found:
        found.run()
        total, viewport = found.counts()

    assert total == 2
    assert 1 <= viewport <= total


def test_scroll_policy_round_trips(make_terminal: object) -> None:
    term = make_terminal(80, 24, "x\r\n")

    with term.search("x") as found:
        default = found.scroll_policy()
        found.set_scroll_policy(SearchScroll.NONE)
        assert found.scroll_policy() == SearchScroll.NONE
        found.set_scroll_policy(SearchScroll.IF_NEEDED)
        assert found.scroll_policy() == SearchScroll.IF_NEEDED

    assert default in (SearchScroll.NONE, SearchScroll.IF_NEEDED)


def test_find_helper_runs_the_search(make_terminal: object) -> None:
    term = make_terminal(80, 24, "one\r\ntwo\r\n")

    with term.find("two") as found:
        assert found.total_matches() == 1


def test_tick_is_safe_and_gives_a_status(make_terminal: object) -> None:
    term = make_terminal(80, 24, "line\r\n")

    with term.search("line") as found:
        status = found.tick()

    assert isinstance(status, SearchStatus)


def test_search_survives_the_terminal_being_closed(library: str) -> None:
    """The library allows the two to be freed in either order."""
    term = Terminal(cols=80, rows=24, library=library)
    found = Search(term, "payload", library=library)
    try:
        term.write("payload\r\n")
        found.run()
        assert found.total_matches() == 1

        term.close()

        # Search-owned data still reads; it never touches the terminal.
        assert found.total_matches() == 1
        assert found.close() is None
    finally:
        found.close()
        term.close()


def test_search_close_is_idempotent(make_terminal: object) -> None:
    term = make_terminal(80, 24, "x\r\n")
    found = Search(term, "x", library=term.library_path)

    assert found.close() is None
    assert found.close() is None
    assert found.closed is True

    with pytest.raises(GhosttyError) as excinfo:
        found.run()

    assert excinfo.value.code == int(Result.INVALID_VALUE)


def test_search_requires_a_live_terminal(make_terminal: object) -> None:
    term = make_terminal(80, 24)
    term.close()

    with pytest.raises(GhosttyError):
        Search(term, "x", library=term.library_path)


def test_search_tracks_new_output(make_terminal: object) -> None:
    """Re-feeding must pick up writes that happened after the first run."""
    term = make_terminal(80, 24, "first hit\r\n")

    with term.search("hit") as found:
        found.run()
        assert found.total_matches() == 1

        term.write("second hit\r\n")
        found.feed()

        assert found.total_matches() == 2
