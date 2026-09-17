"""Convenience properties over :meth:`khostty_vt.Terminal.get`.

Split into a mixin so the core terminal lifecycle and the read-only accessors
stay separately readable. The mixin relies on the host class providing
``_ffi``, ``_lib``, ``_require_open()``, and ``get()``.
"""

from __future__ import annotations

from typing import Dict, Tuple

from .constants import Screen, TerminalData
from .style import Style

__all__ = ["TerminalDataMixin"]


class TerminalDataMixin:
    """Read-only accessors for the fields an agent typically inspects."""

    __slots__ = ()

    def get(self, data: TerminalData) -> object:  # pragma: no cover - provided by Terminal
        raise NotImplementedError

    @property
    def cols(self) -> int:
        """Terminal width in cells."""
        return self.get(TerminalData.COLS)  # type: ignore[return-value]

    @property
    def rows(self) -> int:
        """Terminal height in cells."""
        return self.get(TerminalData.ROWS)  # type: ignore[return-value]

    @property
    def cursor_x(self) -> int:
        """Cursor column."""
        return self.get(TerminalData.CURSOR_X)  # type: ignore[return-value]

    @property
    def cursor_y(self) -> int:
        """Cursor row."""
        return self.get(TerminalData.CURSOR_Y)  # type: ignore[return-value]

    @property
    def cursor_position(self) -> Tuple[int, int]:
        """Cursor ``(x, y)`` in cells."""
        return self.cursor_x, self.cursor_y

    @property
    def cursor_visible(self) -> bool:
        """Whether the cursor is shown."""
        return self.get(TerminalData.CURSOR_VISIBLE)  # type: ignore[return-value]

    @property
    def cursor_at_prompt(self) -> bool:
        """Whether the cursor is at a semantic shell prompt (OSC 133)."""
        return self.get(TerminalData.CURSOR_AT_PROMPT)  # type: ignore[return-value]

    @property
    def cursor_style(self) -> Style:
        """The SGR style that will be applied to newly printed text.

        This is not the cursor shape; for that, set
        :attr:`~khostty_vt.constants.TerminalOption.DEFAULT_CURSOR_STYLE`.
        """
        return self.get(TerminalData.CURSOR_STYLE)  # type: ignore[return-value]

    @property
    def pending_wrap(self) -> bool:
        """Whether a character at the last column is queued to wrap."""
        return self.get(TerminalData.CURSOR_PENDING_WRAP)  # type: ignore[return-value]

    @property
    def active_screen(self) -> Screen:
        """Which screen buffer is in use."""
        return self.get(TerminalData.ACTIVE_SCREEN)  # type: ignore[return-value]

    @property
    def title(self) -> str:
        """Title set via OSC 0 / OSC 2."""
        return self.get(TerminalData.TITLE)  # type: ignore[return-value]

    @property
    def pwd(self) -> str:
        """Working directory reported via OSC 7."""
        return self.get(TerminalData.PWD)  # type: ignore[return-value]

    @property
    def total_rows(self) -> int:
        """Rows on screen plus in scrollback."""
        return self.get(TerminalData.TOTAL_ROWS)  # type: ignore[return-value]

    @property
    def scrollback_rows(self) -> int:
        """Rows currently in scrollback."""
        return self.get(TerminalData.SCROLLBACK_ROWS)  # type: ignore[return-value]

    @property
    def size_px(self) -> Tuple[int, int]:
        """Terminal size in pixels, ``(width, height)``."""
        return (
            self.get(TerminalData.WIDTH_PX),  # type: ignore[return-value]
            self.get(TerminalData.HEIGHT_PX),  # type: ignore[return-value]
        )

    @property
    def mouse_tracking(self) -> bool:
        """Whether the application enabled mouse reporting."""
        return self.get(TerminalData.MOUSE_TRACKING)  # type: ignore[return-value]

    @property
    def vt_ground(self) -> bool:
        """Whether the VT parser is at a stateless point."""
        return self.get(TerminalData.VT_GROUND)  # type: ignore[return-value]

    @property
    def scrollbar(self) -> Dict[str, int]:
        """Scrollbar geometry: ``total``, ``offset``, and ``len`` in rows."""
        return self.get(TerminalData.SCROLLBAR)  # type: ignore[return-value]
