"""Tests for snapshot encoding, the two-call buffer pattern, and restore."""

from __future__ import annotations

import pytest

from khostty_vt import GhosttyError, Result, Terminal, restore, snapshot_size

ROUND_TRIP_CASES = [
    pytest.param(40, 6, ["alpha\r\n", "beta\r\n", "gamma"], id="simple-text"),
    pytest.param(
        60,
        8,
        ["\x1b[1;31mred bold\x1b[0m\r\n", "\x1b[4munder\x1b[0m\r\n", "\x1b]0;title\x07rest"],
        id="styled-text",
    ),
    pytest.param(80, 12, ["one\r\n", "two\r\n", "\x1b[5;10Hplaced"], id="cursor-repositioned"),
    pytest.param(10, 6, ["0123456789ABCDEFGHIJ\r\n"], id="wrapped-line"),
    pytest.param(80, 24, ["\x1b[?1049h", "alternate screen"], id="alternate-screen"),
]


@pytest.mark.parametrize("cols,rows,writes", ROUND_TRIP_CASES)
def test_snapshot_round_trip(cols: int, rows: int, writes: list[str], library: str) -> None:
    with Terminal(cols=cols, rows=rows, library=library) as term:
        for chunk in writes:
            term.write(chunk)
        want = term.text()

        snapshot = term.snapshot()
        assert snapshot

        restored = restore(snapshot, library=library)
        try:
            assert restored.text() == want
            assert (restored.cols, restored.rows) == (cols, rows)
        finally:
            restored.close()


def test_snapshot_size_matches_the_encoded_length(terminal: Terminal) -> None:
    terminal.write("some content here\r\nand more")

    snapshot = terminal.snapshot()

    assert terminal.snapshot_size() == len(snapshot)
    assert snapshot_size(terminal) == len(snapshot)


def test_snapshot_into_a_caller_buffer(terminal: Terminal) -> None:
    terminal.write("some content here\r\nand more")
    want = terminal.snapshot()

    buffer = terminal.snapshot_buffer(terminal.snapshot_size())
    written = terminal.snapshot_into(buffer)

    assert written == len(want)
    # cffi arrays require an explicit slice start.
    assert bytes(buffer[0:written]) == want

    restored = restore(bytes(buffer[0:written]))
    try:
        assert restored.text() == terminal.text()
    finally:
        restored.close()


def test_snapshot_into_a_small_buffer_reports_out_of_space(terminal: Terminal) -> None:
    terminal.write("some content here\r\nand more")

    too_small = terminal.snapshot_buffer(8)

    with pytest.raises(GhosttyError) as excinfo:
        terminal.snapshot_into(too_small)

    assert excinfo.value.code == int(Result.OUT_OF_SPACE)


def test_snapshot_carries_terminal_options(library: str) -> None:
    """A restored terminal must keep options that affect rendering."""
    with Terminal(cols=40, rows=4, library=library) as term:
        term.write("\x1b]0;persisted-title\x07content")

        restored = restore(term.snapshot(), library=library)
        try:
            assert restored.title == "persisted-title"
            assert restored.text() == term.text()
        finally:
            restored.close()


@pytest.mark.parametrize("payload", [b"", None])
def test_restore_rejects_empty_input(payload: object, library: str) -> None:
    with pytest.raises(GhosttyError) as excinfo:
        restore(payload, library=library)  # type: ignore[arg-type]

    assert excinfo.value.code == int(Result.INVALID_VALUE)


def test_restored_terminal_is_independent(terminal: Terminal, library: str) -> None:
    """Writing to the restored terminal must not touch the original."""
    terminal.write("original\r\n")
    restored = restore(terminal.snapshot(), library=library)
    try:
        before = terminal.text()

        restored.write("\x1b[2J\x1b[Hchanged\r\n")

        assert restored.text() != before
        assert terminal.text() == before
    finally:
        restored.close()


def test_restored_terminal_supports_search_and_render(library: str) -> None:
    with Terminal(cols=60, rows=8, library=library) as term:
        term.write("error one\r\nerror two\r\nok\r\n")
        snapshot = term.snapshot()

    restored = restore(snapshot, library=library)
    try:
        with restored.search("error") as found:
            found.run()
            assert found.total_matches() == 2

        assert "error" in restored.text()
        assert restored.formatter(trim=True).text()
    finally:
        restored.close()
