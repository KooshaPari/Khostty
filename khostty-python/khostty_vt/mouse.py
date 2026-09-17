"""Mouse event encoding.

Turns pointer events into the byte sequences a pty expects, under whichever
tracking mode and wire format the application selected.

Two facts about the C API are worth knowing:

* An empty result with no error is normal. It means the event is not reportable
  under the current tracking mode, for example motion with no button held while
  the application asked for :attr:`MouseTrackingMode.NORMAL`, which reports only
  presses and releases.
* The encoder works in surface-space **pixels**. The geometry set with
  :meth:`MouseEncoder.set_size` is what maps a position onto a cell, so
  forgetting it leaves every event unmapped.
* The **screen** dimensions are required, not just the cell size. A zero
  ``screen_width`` or ``screen_height`` makes every event unreportable, which
  looks identical to the tracking-mode case above and is much harder to guess.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum
from typing import Any, Tuple

__all__ = [
    "EncoderSize",
    "MouseAction",
    "MouseButton",
    "MouseEncoderOption",
    "MouseFormat",
    "MousePosition",
    "MouseTrackingMode",
    "cell_for",
]


class MouseAction(IntEnum):
    """Phase of a mouse event."""

    PRESS = 0
    RELEASE = 1
    MOTION = 2


class MouseButton(IntEnum):
    """Which button an event involves."""

    UNKNOWN = 0
    LEFT = 1
    RIGHT = 2
    MIDDLE = 3
    FOUR = 4
    FIVE = 5
    SIX = 6
    SEVEN = 7
    EIGHT = 8
    NINE = 9
    TEN = 10
    ELEVEN = 11


class MouseFormat(IntEnum):
    """Wire format the encoder emits."""

    X10 = 0
    UTF8 = 1
    SGR = 2
    URXVT = 3
    SGR_PIXELS = 4


class MouseTrackingMode(IntEnum):
    """Tracking mode the application requested, corresponding to the DEC modes."""

    NONE = 0
    X10 = 1
    NORMAL = 2
    BUTTON = 3
    ANY = 4


class MouseEncoderOption(IntEnum):
    """Writable encoder settings."""

    EVENT = 0
    FORMAT = 1
    SIZE = 2
    ANY_BUTTON_PRESSED = 3
    TRACK_LAST_CELL = 4


@dataclass(frozen=True)
class MousePosition:
    """A position in surface-space pixels, with ``(0, 0)`` at the top left.

    This is not a grid coordinate; the encoder maps it through the cell size.
    """

    x: float = 0.0
    y: float = 0.0


@dataclass(frozen=True)
class EncoderSize:
    """Surface geometry used to map pixels onto cells.

    Fill in ``screen_width`` and ``screen_height`` as well as the cell size: an
    event on a zero-sized screen is not reportable, so leaving them out makes
    the encoder silently produce nothing for every event. The padding fields
    are subtracted from the position to find the usable origin, and defaulting
    them to zero is correct for an unpadded surface.
    """

    screen_width: int = 0
    screen_height: int = 0
    cell_width: int = 0
    cell_height: int = 0
    padding_top: int = 0
    padding_bottom: int = 0
    padding_right: int = 0
    padding_left: int = 0

    def to_c(self, ffi: Any) -> Any:
        """Build the C struct, setting the size header the library validates."""
        struct = ffi.new("GhosttyMouseEncoderSize *")
        struct.size = ffi.sizeof("GhosttyMouseEncoderSize")
        struct.screen_width = self.screen_width
        struct.screen_height = self.screen_height
        struct.cell_width = self.cell_width
        struct.cell_height = self.cell_height
        struct.padding_top = self.padding_top
        struct.padding_bottom = self.padding_bottom
        struct.padding_right = self.padding_right
        struct.padding_left = self.padding_left
        return struct


def cell_for(position: MousePosition, size: EncoderSize) -> Tuple[int, int]:
    """Map a pixel position onto a one-based cell, as the encoder does.

    Provided so callers can reason about highlights without re-deriving the
    arithmetic; a zero cell size yields ``(0, 0)``, matching the encoder's
    behaviour of leaving the coordinate unmapped.
    """
    if size.cell_width <= 0 or size.cell_height <= 0:
        return 0, 0
    column = (position.x - size.padding_left) / size.cell_width + 1
    row = (position.y - size.padding_top) / size.cell_height + 1
    return int(column), int(row)
