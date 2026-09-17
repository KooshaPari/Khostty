"""Tests for mouse event encoding."""

from __future__ import annotations

import pytest

from khostty_vt import (
    EncoderSize,
    GhosttyError,
    Mods,
    MouseAction,
    MouseButton,
    MouseEncoder,
    MouseEvent,
    MouseFormat,
    MousePosition,
    MouseTrackingMode,
    Result,
    Terminal,
    cell_for,
    encode_mouse,
)

# 800x600 surface, 10x20 cells. Pixel (50,40) is cell (6,3) one-based.
SIZE = EncoderSize(screen_width=800, screen_height=600, cell_width=10, cell_height=20)
POSITION = MousePosition(x=50, y=40)


@pytest.mark.parametrize(
    "fmt,want",
    [
        (MouseFormat.X10, b"\x1b[M &#"),
        (MouseFormat.UTF8, b"\x1b[M &#"),
        (MouseFormat.SGR, b"\x1b[<0;6;3M"),
        (MouseFormat.URXVT, b"\x1b[32;6;3M"),
        (MouseFormat.SGR_PIXELS, b"\x1b[<0;50;40M"),
    ],
)
def test_formats(fmt: MouseFormat, want: bytes, library: str) -> None:
    got = encode_mouse(POSITION, MouseButton.LEFT, format=fmt, size=SIZE, library=library)

    assert got == want


def test_sgr_press_and_release(library: str) -> None:
    press = encode_mouse(POSITION, MouseButton.LEFT, size=SIZE, library=library)
    release = encode_mouse(
        POSITION,
        MouseButton.LEFT,
        MouseAction.RELEASE,
        size=SIZE,
        library=library,
    )

    assert press == b"\x1b[<0;6;3M"
    # SGR distinguishes release with a lowercase final byte.
    assert release == b"\x1b[<0;6;3m"


@pytest.mark.parametrize(
    "mode,want",
    [
        # Presses and releases only: bare motion is not reportable.
        (MouseTrackingMode.NORMAL, b""),
        (MouseTrackingMode.BUTTON, b""),
        (MouseTrackingMode.ANY, b"\x1b[<35;6;3M"),
    ],
)
def test_motion_depends_on_tracking_mode(
    mode: MouseTrackingMode, want: bytes, library: str
) -> None:
    """An empty result is a valid outcome, not a failure."""
    got = encode_mouse(POSITION, None, MouseAction.MOTION, mode=mode, size=SIZE, library=library)

    assert got == want


def test_drag_is_reported_in_button_mode(library: str) -> None:
    got = encode_mouse(
        POSITION,
        MouseButton.LEFT,
        MouseAction.MOTION,
        mode=MouseTrackingMode.BUTTON,
        any_button_pressed=True,
        size=SIZE,
        library=library,
    )

    assert got == b"\x1b[<32;6;3M"


@pytest.mark.parametrize(
    "mods,want",
    [
        (Mods.NONE, b"\x1b[<0;6;3M"),
        (Mods.SHIFT, b"\x1b[<4;6;3M"),
        (Mods.ALT, b"\x1b[<8;6;3M"),
        (Mods.CTRL, b"\x1b[<16;6;3M"),
        (Mods.SHIFT | Mods.CTRL, b"\x1b[<20;6;3M"),
    ],
)
def test_modifiers_shift_the_button_code(mods: Mods, want: bytes, library: str) -> None:
    got = encode_mouse(POSITION, MouseButton.LEFT, mods=int(mods), size=SIZE, library=library)

    assert got == want


def test_buttons_are_distinct(library: str) -> None:
    codes = {}
    for button in (MouseButton.LEFT, MouseButton.MIDDLE, MouseButton.RIGHT):
        codes[button] = encode_mouse(POSITION, button, size=SIZE, library=library)

    assert len(set(codes.values())) == 3


def test_pixel_to_cell_mapping(library: str) -> None:
    assert encode_mouse(POSITION, MouseButton.LEFT, size=SIZE, library=library) == (b"\x1b[<0;6;3M")

    # Padding shifts the origin, so the same pixel is one column and one row
    # lower.
    padded = EncoderSize(
        screen_width=800,
        screen_height=600,
        cell_width=10,
        cell_height=20,
        padding_left=10,
        padding_top=20,
    )
    assert encode_mouse(POSITION, MouseButton.LEFT, size=padded, library=library) == (
        b"\x1b[<0;5;2M"
    )


def test_zero_screen_size_makes_events_unreportable(library: str) -> None:
    """Documented trap: the surface size is required, not just the cell size.

    This looks identical to the tracking-mode empty result, so it is pinned
    here rather than left to be rediscovered.
    """
    cells_only = EncoderSize(cell_width=10, cell_height=20)

    got = encode_mouse(POSITION, MouseButton.LEFT, size=cells_only, library=library)

    assert got == b""

    with_surface = EncoderSize(screen_width=800, screen_height=600, cell_width=10, cell_height=20)
    assert (
        encode_mouse(POSITION, MouseButton.LEFT, size=with_surface, library=library)
        == b"\x1b[<0;6;3M"
    )


def test_cell_for_matches_the_encoder() -> None:
    assert cell_for(POSITION, SIZE) == (6, 3)
    assert cell_for(
        POSITION,
        EncoderSize(cell_width=10, cell_height=20, padding_left=10, padding_top=20),
    ) == (5, 2)

    # A zero cell size means the geometry is unknown, so nothing is mapped.
    assert cell_for(POSITION, EncoderSize()) == (0, 0)


def test_event_state_round_trip(library: str) -> None:
    with MouseEvent(library=library) as event:
        event.set_action(MouseAction.MOTION)
        event.set_button(MouseButton.MIDDLE)
        event.set_mods(int(Mods.SHIFT))
        event.set_position(MousePosition(x=12.5, y=34.25))

        assert event.action() == MouseAction.MOTION
        assert event.button() == MouseButton.MIDDLE
        assert event.mods() == int(Mods.SHIFT)
        assert event.position() == MousePosition(x=12.5, y=34.25)

        # Clearing must be distinguishable from the UNKNOWN button.
        event.clear_button()
        assert event.button() is None

        assert event.set_action(MouseAction.PRESS) is event


def test_encoder_reuses_one_event(library: str) -> None:
    with MouseEncoder(library=library) as encoder, MouseEvent(library=library) as event:
        encoder.set_tracking_mode(MouseTrackingMode.NORMAL)
        encoder.set_format(MouseFormat.SGR)
        encoder.set_size(SIZE)

        event.set_action(MouseAction.PRESS).set_button(MouseButton.LEFT)

        first = encoder.encode(event.set_position(MousePosition(x=10, y=20)))
        second = encoder.encode(event.set_position(MousePosition(x=30, y=60)))

        assert first == b"\x1b[<0;2;2M"
        assert second == b"\x1b[<0;4;4M"


def test_tracking_last_cell_and_reset(library: str) -> None:
    with MouseEncoder(library=library) as encoder:
        encoder.set_tracking_mode(MouseTrackingMode.ANY)
        encoder.set_format(MouseFormat.SGR)
        encoder.set_size(SIZE)
        encoder.set_track_last_cell(True)
        encoder.set_any_button_pressed(True)

        assert encoder.reset() is encoder


def test_sync_from_terminal(library: str) -> None:
    with Terminal(cols=80, rows=24, library=library) as term:
        term.write("\x1b[?1000h\x1b[?1006h")

        with MouseEncoder(library=library) as encoder, MouseEvent(library=library) as event:
            encoder.sync_from_terminal(term)
            encoder.set_size(SIZE)

            event.set_action(MouseAction.PRESS)
            event.set_button(MouseButton.LEFT)
            event.set_position(POSITION)

            assert encoder.encode(event) == b"\x1b[<0;6;3M"


def test_sync_from_a_terminal_without_tracking(library: str) -> None:
    """Nothing to report when the application never enabled mouse modes."""
    with Terminal(cols=80, rows=24, library=library) as term:
        with MouseEncoder(library=library) as encoder, MouseEvent(library=library) as event:
            encoder.sync_from_terminal(term)
            encoder.set_size(SIZE)
            event.set_action(MouseAction.PRESS)
            event.set_button(MouseButton.LEFT)
            event.set_position(POSITION)

            assert encoder.encode(event) == b""


def test_encoded_sequence_is_consumed_by_the_terminal(library: str) -> None:
    """Closes the loop: a synced encoder's sequence must be well-formed.

    A valid SGR report is consumed rather than printed, so the screen stays
    empty. Both the tracking mode and the wire format have to match what the
    terminal was told, which is why the encoder is synced and then fed back.
    """
    with Terminal(cols=80, rows=24, library=library) as term:
        term.write("\x1b[?1000h\x1b[?1006h")
        assert term.mouse_tracking is True

        with MouseEncoder(library=library) as encoder, MouseEvent(library=library) as event:
            encoder.sync_from_terminal(term)
            encoder.set_size(SIZE)

            event.set_action(MouseAction.PRESS)
            event.set_button(MouseButton.LEFT)
            event.set_position(POSITION)
            before = term.cursor_y

            sequence = encoder.encode(event)
            assert sequence == b"\x1b[<0;6;3M"

            term.write(sequence)

        assert term.text() == ""
        assert term.cursor_y == before
        assert term.vt_ground is True


def test_sync_from_terminal_rejects_a_closed_terminal(library: str) -> None:
    term = Terminal(cols=80, rows=24, library=library)
    term.close()

    with MouseEncoder(library=library) as encoder:
        with pytest.raises(GhosttyError) as excinfo:
            encoder.sync_from_terminal(term)

    assert excinfo.value.code == int(Result.INVALID_VALUE)


def test_closed_handles_are_refused(library: str) -> None:
    encoder = MouseEncoder(library=library)
    assert encoder.close() is None
    assert encoder.close() is None
    assert encoder.closed is True

    with pytest.raises(GhosttyError):
        encoder.encode(MouseEvent(library=library))
    with pytest.raises(GhosttyError):
        encoder.set_format(MouseFormat.SGR)
    with pytest.raises(GhosttyError):
        encoder.reset()

    event = MouseEvent(library=library)
    assert event.close() is None
    assert event.close() is None
    assert event.closed is True

    with pytest.raises(GhosttyError):
        event.set_button(MouseButton.LEFT)
    with pytest.raises(GhosttyError):
        event.position()

    with MouseEncoder(library=library) as open_encoder:
        with pytest.raises(GhosttyError):
            open_encoder.encode(event)


def test_repr_is_informative(library: str) -> None:
    encoder = MouseEncoder(library=library)
    assert "open" in repr(encoder)
    encoder.close()
    assert "closed" in repr(encoder)

    event = MouseEvent(library=library)
    assert "open" in repr(event)
    event.close()
    assert "closed" in repr(event)


def test_encoder_size_defaults_are_zero() -> None:
    size = EncoderSize()

    assert size.cell_width == 0
    assert size.padding_top == 0
