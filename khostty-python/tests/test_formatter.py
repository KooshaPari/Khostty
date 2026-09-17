"""Tests for formatter output across the three encodings."""

from __future__ import annotations

import pytest

from khostty_vt import (
    Format,
    Formatter,
    FormatterExtras,
    FormatterOptions,
    GhosttyError,
)


def test_plain_format_strips_escape_sequences(make_terminal: object) -> None:
    term = make_terminal(20, 3)
    term.write("\x1b[1mBold\x1b[0m\r\n")

    with term.formatter(format=Format.PLAIN, trim=True) as fmt:
        assert fmt.text() == "Bold"


def test_vt_format_preserves_sequences(make_terminal: object) -> None:
    term = make_terminal(20, 3)
    term.write("\x1b[1mBold\x1b[0m\r\n")

    with term.formatter(format=Format.VT, trim=True) as fmt:
        out = fmt.format()

    assert b"\x1b[1m" in out
    assert b"Bold" in out


def test_html_format_emits_markup(make_terminal: object) -> None:
    term = make_terminal(20, 3)
    term.write("\x1b[1mBold\x1b[0m\r\n")

    with term.formatter(format=Format.HTML, trim=True) as fmt:
        out = fmt.text()

    assert "monospace" in out
    assert "Bold" in out


@pytest.mark.parametrize("fmt", [Format.PLAIN, Format.VT, Format.HTML])
def test_every_format_returns_something(fmt: Format, make_terminal: object) -> None:
    term = make_terminal(20, 3)
    term.write("content\r\n")

    assert term.formatter(format=fmt, trim=True).format()


def test_empty_screen_renders_empty(make_terminal: object) -> None:
    term = make_terminal(20, 3)

    with term.formatter(format=Format.PLAIN, trim=True) as fmt:
        assert fmt.format() == b""
        assert fmt.text() == ""


def test_trim_controls_trailing_whitespace(make_terminal: object) -> None:
    """The formatter emits the written row, not the full grid width."""
    term = make_terminal(20, 3)
    term.write("pad       \r\n")

    untrimmed = term.formatter(format=Format.PLAIN, trim=False).text()
    trimmed = term.formatter(format=Format.PLAIN, trim=True).text()

    assert untrimmed == "pad" + " " * 7
    assert trimmed == "pad"
    assert len(trimmed) < len(untrimmed)


def test_unwrap_joins_soft_wrapped_lines(make_terminal: object) -> None:
    term = make_terminal(10, 6)
    term.write("0123456789ABCDEFGHIJ\r\n")

    wrapped = term.formatter(format=Format.PLAIN, trim=True, unwrap=False).text()
    unwrapped = term.formatter(format=Format.PLAIN, trim=True, unwrap=True).text()

    assert "\n" in wrapped
    assert "0123456789ABCDEFGHIJ" in unwrapped.replace("\n", "")


def test_formatter_reuses_terminal_state(make_terminal: object) -> None:
    """One formatter reflects terminal changes on each call."""
    term = make_terminal(40, 4)
    with term.formatter(format=Format.PLAIN, trim=True) as fmt:
        term.write("first\r\n")
        first = fmt.text()
        term.write("second\r\n")
        second = fmt.text()

    assert first != second
    assert "second" in second


def test_options_can_be_passed_as_a_dataclass(make_terminal: object) -> None:
    term = make_terminal(20, 3)
    term.write("hi\r\n")

    with term.formatter(FormatterOptions(format=Format.PLAIN, trim=True)) as fmt:
        assert fmt.text() == "hi"
        assert fmt.options.format == Format.PLAIN
        assert fmt.options.trim is True


def test_keywords_override_dataclass_options(make_terminal: object) -> None:
    term = make_terminal(20, 3)
    term.write("hi   \r\n")

    with term.formatter(FormatterOptions(format=Format.PLAIN, trim=False), trim=True) as fmt:
        assert fmt.text() == "hi"


def test_extras_do_not_break_styled_output(make_terminal: object) -> None:
    term = make_terminal(40, 4)
    term.write("\x1b[1mBold\x1b[0m\r\n")

    extras = FormatterExtras(cursor=True, style=True, hyperlink=True, modes=True)
    with term.formatter(format=Format.VT, trim=True, extras=extras) as fmt:
        out = fmt.text(errors="replace")

    assert "Bold" in out
    assert "\x1b" in out


def test_formatter_requires_a_live_terminal(make_terminal: object) -> None:
    term = make_terminal(20, 3)
    term.close()

    with pytest.raises(GhosttyError):
        Formatter(term, library=term.library_path)


def test_formatter_close_is_idempotent(make_terminal: object) -> None:
    term = make_terminal(20, 3)
    fmt = Formatter(term, library=term.library_path)

    assert fmt.close() is None
    assert fmt.close() is None
    assert fmt.closed is True

    with pytest.raises(GhosttyError):
        fmt.format()


def test_terminal_text_and_formatted_helpers(make_terminal: object) -> None:
    term = make_terminal(40, 4)
    term.write("value\r\n")

    assert term.text() == "value"
    assert "value" in term.formatted(format=Format.VT)
    assert "value" in term.formatted(format=Format.HTML)
