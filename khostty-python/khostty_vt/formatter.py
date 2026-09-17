"""Rendering terminal content as plain text, VT sequences, or HTML.

A :class:`Formatter` borrows a terminal and reads its current state on every
call, so one formatter can be reused across frames instead of being rebuilt.
The terminal must outlive the formatter.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Optional

from . import _ffi
from .constants import FormatterFormat, Result
from .errors import GhosttyError, check

__all__ = ["Format", "Formatter", "FormatterExtras", "FormatterOptions"]

#: Alias so callers can write ``Format.PLAIN`` as the WBS describes.
Format = FormatterFormat


@dataclass(frozen=True)
class FormatterExtras:
    """Non-content state a styled format can include.

    These only affect :attr:`Format.VT` and :attr:`Format.HTML`;
    :attr:`Format.PLAIN` ignores them.
    """

    cursor: bool = False
    style: bool = False
    hyperlink: bool = False
    charsets: bool = False
    palette: bool = False
    modes: bool = False
    scrolling_region: bool = False
    pwd: bool = False
    keyboard: bool = False


@dataclass(frozen=True)
class FormatterOptions:
    """Formatting options.

    Attributes:
        format: Output encoding.
        unwrap: Join soft-wrapped lines into logical lines.
        trim: Strip trailing whitespace from non-blank lines.
        extras: Extra state to emit for the styled formats.
    """

    format: FormatterFormat = FormatterFormat.PLAIN
    unwrap: bool = False
    trim: bool = True
    extras: FormatterExtras = field(default_factory=FormatterExtras)


def _options_struct(ffi: Any, options: FormatterOptions) -> Any:
    """Build a ``GhosttyFormatterTerminalOptions`` with both size fields set.

    The C API validates ``size`` on the outer struct and on the nested extras
    struct, so both must be set to their ``sizeof``. cffi fills them in from
    its own declarations, which is exactly what ``GHOSTTY_INIT_SIZED`` does in
    C.
    """
    opts = ffi.new("GhosttyFormatterTerminalOptions *")
    opts.size = ffi.sizeof("GhosttyFormatterTerminalOptions")
    opts.emit = int(options.format)
    opts.unwrap = options.unwrap
    opts.trim = options.trim

    extras = options.extras
    opts.extra.size = ffi.sizeof("GhosttyFormatterTerminalExtra")
    opts.extra.palette = extras.palette
    opts.extra.modes = extras.modes
    opts.extra.scrolling_region = extras.scrolling_region
    opts.extra.pwd = extras.pwd
    opts.extra.keyboard = extras.keyboard

    opts.extra.screen.size = ffi.sizeof("GhosttyFormatterScreenExtra")
    opts.extra.screen.cursor = extras.cursor
    opts.extra.screen.style = extras.style
    opts.extra.screen.hyperlink = extras.hyperlink
    opts.extra.screen.charsets = extras.charsets

    opts.selection = ffi.NULL
    return opts


class Formatter:
    """Renders a terminal's active screen.

    Example::

        with Terminal(cols=80, rows=24) as term:
            term.write("\\x1b[1mhi\\x1b[0m")
            with term.formatter(format=Format.PLAIN, trim=True) as fmt:
                assert fmt.format() == b"hi"
    """

    __slots__ = ("_closed", "_ffi", "_handle", "_lib", "_options", "_ptr", "_terminal")

    def __init__(
        self,
        terminal: Any,
        options: Optional[FormatterOptions] = None,
        *,
        format: Optional[FormatterFormat] = None,
        unwrap: Optional[bool] = None,
        trim: Optional[bool] = None,
        extras: Optional[FormatterExtras] = None,
        library: Optional[str] = None,
    ) -> None:
        """Create a formatter for ``terminal``.

        Either pass a :class:`FormatterOptions` or the individual keyword
        arguments; the keywords override the corresponding fields.

        Args:
            terminal: The terminal to format. It must outlive this formatter.
            options: Base options.
            format: Output encoding.
            unwrap: Join soft-wrapped lines.
            trim: Strip trailing whitespace.
            extras: Extra state for the styled formats.
            library: Explicit shared-library path, for tests.

        Raises:
            GhosttyError: If the terminal is closed or the library refuses.
        """
        base = options or FormatterOptions()
        resolved = FormatterOptions(
            format=base.format if format is None else format,
            unwrap=base.unwrap if unwrap is None else unwrap,
            trim=base.trim if trim is None else trim,
            extras=base.extras if extras is None else extras,
        )

        ffi, lib = _ffi.load(library)
        handle = terminal._require_open()

        formatter = ffi.new("GhosttyFormatter *")
        # The C API takes the options struct by value, hence the [0].
        check(
            lib.ghostty_formatter_terminal_new(
                ffi.NULL, formatter, handle, _options_struct(ffi, resolved)[0]
            ),
            "create formatter",
        )

        self._ffi = ffi
        self._lib = lib
        self._ptr = formatter
        self._handle = formatter[0]
        self._options = resolved
        # Hold a reference so the borrowed terminal outlives the formatter.
        self._terminal = terminal
        self._closed = False

    @property
    def options(self) -> FormatterOptions:
        """Options this formatter was created with."""
        return self._options

    @property
    def closed(self) -> bool:
        """Whether the underlying formatter has been freed."""
        return self._closed

    def close(self) -> None:
        """Free the formatter. Idempotent, and a no-op on a closed formatter."""
        if self._closed:
            return
        self._lib.ghostty_formatter_free(self._handle)
        self._closed = True
        self._handle = None

    def __enter__(self) -> Formatter:
        return self

    def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> None:
        self.close()

    def __del__(self) -> None:  # pragma: no cover - GC timing is not testable
        try:
            self.close()
        except Exception:
            pass

    def __repr__(self) -> str:
        state = "closed" if self._closed else "open"
        return f"<Formatter {state}>"

    def format(self) -> bytes:
        """Render the terminal's current state and return the bytes.

        Returns:
            The rendered output, or ``b""`` when the formatter produces
            nothing (which the C API reports as success with a NULL buffer).

        Raises:
            GhosttyError: If the formatter is closed or rendering fails.
        """
        if self._closed:
            raise GhosttyError(int(Result.INVALID_VALUE), "format")

        ffi = self._ffi
        out_ptr = ffi.new("uint8_t **")
        out_len = ffi.new("size_t *")
        check(
            self._lib.ghostty_formatter_format_alloc(self._handle, ffi.NULL, out_ptr, out_len),
            "format terminal",
        )

        length = int(out_len[0])
        if not out_ptr[0] or length == 0:
            self._lib.ghostty_free(ffi.NULL, out_ptr[0], 0)
            return b""
        try:
            return bytes(ffi.buffer(out_ptr[0], length))
        finally:
            self._lib.ghostty_free(ffi.NULL, out_ptr[0], length)

    def text(self, encoding: str = "utf-8", errors: str = "replace") -> str:
        """Render and decode, defaulting to replacement for invalid bytes."""
        return self.format().decode(encoding, errors)
