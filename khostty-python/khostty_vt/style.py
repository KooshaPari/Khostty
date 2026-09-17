"""Terminal cell styles.

:class:`Style` mirrors ``GhosttyStyle``: decoration flags plus three
independently-tagged colors. It is what :attr:`khostty_vt.Terminal.cursor_style`
returns, i.e. the attributes that will be applied to text printed next.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Optional, Tuple

from .constants import StyleColorKind, TerminalData, Underline
from .errors import check

__all__ = ["Style", "StyleColor", "StyleColorKind", "Underline", "read_cursor_style"]


@dataclass(frozen=True)
class StyleColor:
    """One color attribute of a :class:`Style`.

    Attributes:
        kind: Which arm is set: none, a palette index, or direct RGB.
        palette: The palette index, meaningful only when ``kind`` is
            :attr:`StyleColorKind.PALETTE`.
        rgb: The ``(r, g, b)`` triple, meaningful only when ``kind`` is
            :attr:`StyleColorKind.RGB`.
    """

    kind: StyleColorKind = StyleColorKind.NONE
    palette: Optional[int] = None
    rgb: Optional[Tuple[int, int, int]] = None

    @property
    def is_set(self) -> bool:
        """Whether the attribute carries a color at all."""
        return self.kind != StyleColorKind.NONE

    def as_rgb(self) -> Optional[Tuple[int, int, int]]:
        """The color as ``(r, g, b)``, or ``None`` for a palette index."""
        return self.rgb


@dataclass(frozen=True)
class Style:
    """The complete SGR style of a cell.

    Colors are :class:`StyleColor` values so an unset attribute is
    distinguishable from black.
    """

    bold: bool = False
    italic: bool = False
    faint: bool = False
    blink: bool = False
    inverse: bool = False
    invisible: bool = False
    strikethrough: bool = False
    overline: bool = False
    underline: Underline = Underline.NONE

    foreground: StyleColor = StyleColor()
    background: StyleColor = StyleColor()
    underline_color: StyleColor = StyleColor()

    @property
    def is_default(self) -> bool:
        """Whether the style is the library's default: no colors, no flags."""
        return (
            not self.decorations
            and not self.foreground.is_set
            and not self.background.is_set
            and not self.underline_color.is_set
        )

    @property
    def decorations(self) -> Tuple[str, ...]:
        """Names of the enabled decoration flags."""
        names = [
            name
            for name, enabled in (
                ("bold", self.bold),
                ("italic", self.italic),
                ("faint", self.faint),
                ("blink", self.blink),
                ("inverse", self.inverse),
                ("invisible", self.invisible),
                ("strikethrough", self.strikethrough),
                ("overline", self.overline),
            )
            if enabled
        ]
        if self.underline != Underline.NONE:
            names.append(f"underline:{self.underline.name.lower()}")
        return tuple(names)

    def __str__(self) -> str:
        inner = ",".join(self.decorations)
        return f"Style({inner})" if inner else "Style(default)"


def _color_from_c(color: Any) -> StyleColor:
    """Decode one ``GhosttyStyleColor`` tagged union."""
    tag = StyleColorKind(int(color.tag))
    if tag == StyleColorKind.PALETTE:
        return StyleColor(kind=tag, palette=int(color.value.palette))
    if tag == StyleColorKind.RGB:
        rgb = color.value.rgb
        return StyleColor(kind=tag, rgb=(int(rgb.r), int(rgb.g), int(rgb.b)))
    return StyleColor()


def style_from_c(style: Any) -> Style:
    """Convert a filled ``GhosttyStyle`` into the Python value."""
    return Style(
        bold=bool(style.bold),
        italic=bool(style.italic),
        faint=bool(style.faint),
        blink=bool(style.blink),
        inverse=bool(style.inverse),
        invisible=bool(style.invisible),
        strikethrough=bool(style.strikethrough),
        overline=bool(style.overline),
        underline=Underline(int(style.underline)),
        foreground=_color_from_c(style.fg_color),
        background=_color_from_c(style.bg_color),
        underline_color=_color_from_c(style.underline_color),
    )


def read_cursor_style(ffi: Any, lib: Any, terminal: Any) -> Style:
    """Read ``GHOSTTY_TERMINAL_DATA_CURSOR_STYLE`` from a terminal handle.

    The style struct is sized, so it is initialised through
    ``ghostty_style_default`` before the read; that also gives the library a
    valid ``size`` field to validate against.
    """
    out = ffi.new("GhosttyStyle *")
    lib.ghostty_style_default(out)
    check(
        lib.ghostty_terminal_get(terminal, int(TerminalData.CURSOR_STYLE), out),
        "read cursor style",
    )
    return style_from_c(out)
