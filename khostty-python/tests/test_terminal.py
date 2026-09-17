"""Tests for the Terminal lifecycle, the write path, and the read accessors."""

from __future__ import annotations

import pytest

from khostty_vt import (
    CursorShape,
    GhosttyError,
    Result,
    Screen,
    StyleColorKind,
    Terminal,
    TerminalData,
    TerminalOption,
    Underline,
)


def test_new_terminal_reports_its_geometry(terminal: Terminal) -> None:
    assert terminal.cols == 80
    assert terminal.rows == 24
    assert terminal.cursor_position == (0, 0)
    assert terminal.active_screen == Screen.PRIMARY
    assert terminal.vt_ground is True
    assert terminal.closed is False


@pytest.mark.parametrize("cols,rows", [(0, 24), (80, 0), (-1, 24), (80, -1)])
def test_invalid_geometry_is_rejected(cols: int, rows: int, library: str) -> None:
    with pytest.raises(ValueError):
        Terminal(cols=cols, rows=rows, library=library)


def test_write_and_read_screen(make_terminal: object) -> None:
    term = make_terminal(80, 24)
    term.write("Line 1: Hello World!\r\n")
    term.write("Line 2: \x1b[1mBold\x1b[0m and \x1b[4mUnderline\x1b[0m\r\n")
    term.write("Line 3\r\n")

    text = term.text()

    assert "Line 1: Hello World!" in text
    assert "Line 2: Bold and Underline" in text
    assert "Line 3" in text
    # Styling must not leak into the plain-text form.
    assert "\x1b" not in text


def test_write_accepts_str_bytes_and_iterables(make_terminal: object) -> None:
    term = make_terminal(40, 4)

    assert term.write("a") == 1
    assert term.write(b"b") == 1
    assert term.write(bytearray(b"c")) == 1
    assert term.write(memoryview(b"d")) == 1
    assert term.write(["e", b"f"]) == 2
    assert term.write("") == 0
    assert term.bytes_written == 6
    assert term.text() == "abcdef"


def test_write_rejects_unsupported_types(make_terminal: object) -> None:
    term = make_terminal(40, 4)

    with pytest.raises(TypeError):
        term.write(123)
    with pytest.raises(TypeError):
        term.write(["a", 2])


def test_write_splits_multibyte_sequences_across_chunks(make_terminal: object) -> None:
    """A pty can split a UTF-8 sequence anywhere; the parser must still cope."""
    term = make_terminal(40, 4)
    encoded = "héllo".encode()

    term.write([encoded[:1], encoded[1:3], encoded[3:]])

    assert term.text() == "héllo"


def test_cursor_tracking(make_terminal: object) -> None:
    term = make_terminal(80, 24)
    term.write("hello\r\nworld")

    assert term.cursor_position == (5, 1)
    assert term.pending_wrap is False

    term.write("\x1b[10;20H")
    assert term.cursor_position == (19, 9)
    assert term.vt_ground is True


def test_pending_wrap_at_the_last_column(make_terminal: object) -> None:
    term = make_terminal(5, 3)
    term.write("abcde")

    assert term.cursor_x == 4
    assert term.pending_wrap is True


def test_reset_clears_content_and_keeps_geometry(make_terminal: object) -> None:
    term = make_terminal(80, 24)
    term.write("hello\r\nworld")

    term.reset()

    assert term.text() == ""
    assert term.cursor_position == (0, 0)
    assert (term.cols, term.rows) == (80, 24)


def test_resize_reflows_and_updates_pixels(make_terminal: object) -> None:
    term = make_terminal(80, 24)
    term.write("hello\r\n")

    term.resize(100, 30, 8, 16)

    assert (term.cols, term.rows) == (100, 30)
    assert term.size_px == (800, 480)
    assert term.text().startswith("hello")


def test_resize_rejects_invalid_geometry(make_terminal: object) -> None:
    term = make_terminal(80, 24)

    with pytest.raises(ValueError):
        term.resize(0, 24)


def test_alternate_screen_switching(make_terminal: object) -> None:
    term = make_terminal(80, 24)

    assert term.active_screen == Screen.PRIMARY
    term.write("\x1b[?1049h")
    assert term.active_screen == Screen.ALTERNATE
    term.write("\x1b[?1049l")
    assert term.active_screen == Screen.PRIMARY


def test_osc_title_and_pwd(make_terminal: object) -> None:
    term = make_terminal(80, 24)

    term.write("\x1b]0;my-title\x07")
    term.write("\x1b]7;file://localhost/tmp/proj\x07")

    assert term.title == "my-title"
    assert "/tmp/proj" in term.pwd


def test_mouse_tracking_reflects_the_application(make_terminal: object) -> None:
    term = make_terminal(80, 24)
    assert term.mouse_tracking is False

    term.write("\x1b[?1000h")

    assert term.mouse_tracking is True


def test_cursor_at_prompt_uses_osc_133(make_terminal: object) -> None:
    term = make_terminal(80, 24)
    assert term.cursor_at_prompt is False

    term.write("\x1b]133;A\x07")

    assert term.cursor_at_prompt is True


def test_cursor_style_is_the_sgr_style_not_the_shape(make_terminal: object) -> None:
    term = make_terminal(80, 24)

    assert term.cursor_style.is_default

    term.write("\x1b[1;3;4;9;53m")
    style = term.cursor_style

    assert style.bold and style.italic and style.strikethrough and style.overline
    assert style.underline == Underline.SINGLE
    assert "bold" in style.decorations
    assert not style.is_default


def test_cursor_style_decodes_palette_and_truecolor(make_terminal: object) -> None:
    term = make_terminal(80, 24)

    term.write("\x1b[31m")
    style = term.cursor_style
    assert style.foreground.kind == StyleColorKind.PALETTE
    assert style.foreground.palette == 1
    assert style.foreground.as_rgb() is None

    term.write("\x1b[38;2;17;34;51m")
    style = term.cursor_style
    assert style.foreground.kind == StyleColorKind.RGB
    assert style.foreground.rgb == (17, 34, 51)
    assert style.foreground.as_rgb() == (17, 34, 51)

    term.reset()
    term.write("\x1b[44m")
    style = term.cursor_style
    assert style.background.palette == 4
    assert style.foreground.kind == StyleColorKind.NONE

    term.write("\x1b[0m")
    assert term.cursor_style.is_default


def test_string_options_round_trip(make_terminal: object) -> None:
    term = make_terminal(40, 4)

    term.set_option(TerminalOption.TITLE, "set-title")
    assert term.title == "set-title"

    term.set_option(TerminalOption.PWD, "/tmp/proj")
    assert term.pwd == "/tmp/proj"

    term.set_option(TerminalOption.TERMINFO_NAME, "xterm-256color")


def test_size_options_round_trip(make_terminal: object) -> None:
    term = make_terminal(40, 4)

    term.set_option(TerminalOption.SCROLLBACK_MAX_LINES, 5000)

    assert term.get(TerminalData.SCROLLBACK_MAX_LINES) == 5000


def test_color_option_round_trip(make_terminal: object) -> None:
    term = make_terminal(40, 4)

    term.set_option(TerminalOption.COLOR_FOREGROUND, (1, 2, 3))

    assert term.get(TerminalData.COLOR_FOREGROUND) == (1, 2, 3)


def test_cursor_shape_option(make_terminal: object) -> None:
    term = make_terminal(40, 4)

    term.set_option(TerminalOption.DEFAULT_CURSOR_STYLE, CursorShape.BAR)
    term.set_option(TerminalOption.DEFAULT_CURSOR_BLINK, True)


def test_callback_options_are_refused(make_terminal: object) -> None:
    term = make_terminal(40, 4)

    with pytest.raises(GhosttyError) as excinfo:
        term.set_option(TerminalOption.BELL, 1)

    assert excinfo.value.code == int(Result.INVALID_VALUE)
    assert "BELL" in str(excinfo.value)


def test_unconvertible_data_fields_are_refused(make_terminal: object) -> None:
    term = make_terminal(40, 4)

    with pytest.raises(GhosttyError) as excinfo:
        term.get(TerminalData.KITTY_GRAPHICS)

    assert excinfo.value.code == int(Result.INVALID_VALUE)


def test_get_accepts_plain_ints(make_terminal: object) -> None:
    term = make_terminal(40, 4)
    term.write("x")

    assert term.get(int(TerminalData.CURSOR_X)) == 1


def test_write_until_ground(make_terminal: object) -> None:
    term = make_terminal(40, 4)

    # Already at ground: nothing consumed, and that is success.
    assert term.write_until_ground("plain text") == (0, True)
    assert term.vt_ground is True

    term.write("\x1b[3")
    assert term.vt_ground is False

    consumed, reached = term.write_until_ground("1m;hello")

    assert reached is True
    assert consumed == 2
    assert term.vt_ground is True

    assert term.write_until_ground(b"") == (0, True)


def test_close_is_idempotent_and_blocks_later_use(make_terminal: object) -> None:
    term = make_terminal(40, 4)

    assert term.close() is None
    assert term.close() is None
    assert term.closed is True

    for call in (
        lambda: term.cols,
        lambda: term.text(),
        lambda: term.write("x"),
        lambda: term.reset(),
        lambda: term.resize(40, 4),
        lambda: term.snapshot(),
        lambda: term.formatter(),
        lambda: term.search("x"),
        lambda: term.set_option(TerminalOption.TITLE, "x"),
    ):
        with pytest.raises(GhosttyError):
            call()


def test_context_manager_closes(library: str) -> None:
    with Terminal(cols=40, rows=4, library=library) as term:
        term.write("x")
        assert not term.closed
    assert term.closed


def test_repr_is_informative(make_terminal: object) -> None:
    term = make_terminal(40, 4)
    assert "40x4" in repr(term)

    term.close()
    assert "closed" in repr(term)


def test_scrollbar_geometry_is_consistent(make_terminal: object) -> None:
    term = make_terminal(40, 10)

    scrollbar = term.scrollbar

    assert scrollbar["total"] >= 10
    assert scrollbar["len"] >= 1
    assert scrollbar["offset"] >= 0


def test_total_and_scrollback_rows(make_terminal: object) -> None:
    term = make_terminal(40, 5)
    term.write("\r\n".join(f"line {n}" for n in range(50)))

    assert term.total_rows >= 5
    assert term.scrollback_rows >= 1
