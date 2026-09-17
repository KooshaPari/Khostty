"""The :class:`Terminal` wrapper.

A terminal owns one opaque ``GhosttyTerminal`` handle. Handles are RAII: the
class is a context manager, ``close()`` is idempotent, and ``__del__`` closes as
a backstop. Using a closed terminal raises :class:`~khostty_vt.GhosttyError`
rather than passing a dangling pointer to C.

The class is not thread-safe. The C library requires callers to serialize all
access to one terminal handle.

The class is assembled from three mixins so each concern is readable on its
own: :class:`~khostty_vt._terminal_data.TerminalDataMixin` holds the read-only
accessors, :class:`~khostty_vt._terminal_write.TerminalWriteMixin` the input
path, and :class:`~khostty_vt._terminal_options.TerminalOptionsMixin` the option
writes. This module is the lifecycle surface; field decoding lives in
:mod:`khostty_vt._fields`.
"""

from __future__ import annotations

from typing import Any, Optional

from . import _ffi
from ._fields import read_field
from ._terminal_data import TerminalDataMixin
from ._terminal_options import TerminalOptionsMixin
from ._terminal_write import TerminalWriteMixin, Writable
from .constants import Result, TerminalData
from .errors import GhosttyError, check

__all__ = ["Terminal", "Writable"]


class Terminal(TerminalWriteMixin, TerminalOptionsMixin, TerminalDataMixin):
    """A libghostty-vt terminal.

    Example::

        with Terminal(cols=80, rows=24) as term:
            term.write("$ make test\\r\\n")
            term.write("FAIL\\r\\n")
            print(term.text())
            print(term.cols, term.rows, term.title)
    """

    __slots__ = ("_closed", "_ffi", "_handle", "_lib", "_library", "_ptr", "_total_written")

    def __init__(
        self,
        cols: int = 80,
        rows: int = 24,
        *,
        library: Optional[str] = None,
    ) -> None:
        """Create a terminal with a ``cols`` by ``rows`` grid.

        Args:
            cols: Width in cells. Must be positive.
            rows: Height in cells. Must be positive.
            library: Explicit shared-library path. Discovery runs when omitted.

        Raises:
            ValueError: If ``cols`` or ``rows`` is not positive.
            GhosttyError: If the library refuses to create the terminal.
        """
        if cols <= 0 or rows <= 0:
            raise ValueError(f"cols and rows must be positive, got {cols}x{rows}")

        ffi, lib = _ffi.load(library)
        handle = ffi.new("GhosttyTerminal *")
        check(lib.ghostty_terminal_new(ffi.NULL, handle, cols, rows), "create terminal")

        self._ffi = ffi
        self._lib = lib
        self._ptr = handle
        self._handle = handle[0]
        self._library = library
        self._closed = False
        self._total_written = 0

    def _adopt(self, ffi: Any, lib: Any, handle: Any) -> None:
        """Take ownership of an already-created handle.

        Used by :func:`khostty_vt.snapshot.restore`, which receives a terminal
        from the C decoder instead of creating one.
        """
        self._ffi = ffi
        self._lib = lib
        self._ptr = handle
        self._handle = handle[0]
        self._library = None
        self._closed = False
        self._total_written = 0

    @property
    def closed(self) -> bool:
        """Whether the terminal handle has been released."""
        return self._closed

    @property
    def library_path(self) -> Optional[str]:
        """Explicit library path this terminal was created with, if any."""
        return self._library

    def _require_open(self) -> Any:
        """Return the C handle, or raise if the terminal is closed."""
        if self._closed:
            raise GhosttyError(int(Result.INVALID_VALUE), "terminal is closed")
        return self._handle

    def close(self) -> None:
        """Free the terminal handle. Idempotent and safe to call twice."""
        if self._closed:
            return
        self._lib.ghostty_terminal_free(self._handle)
        self._closed = True
        self._handle = None

    def __enter__(self) -> Terminal:
        return self

    def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> None:
        self.close()

    def __del__(self) -> None:  # pragma: no cover - GC timing is not testable
        try:
            self.close()
        except Exception:
            pass

    def __repr__(self) -> str:
        if self._closed:
            return "<Terminal closed>"
        try:
            return f"<Terminal {self.cols}x{self.rows} open>"
        except GhosttyError:  # pragma: no cover - defensive
            return "<Terminal open>"

    # -- lifecycle -------------------------------------------------------

    def reset(self) -> Terminal:
        """Perform a full reset (RIS), preserving dimensions and options."""
        self._lib.ghostty_terminal_reset(self._require_open())
        return self

    def resize(
        self,
        cols: int,
        rows: int,
        cell_width_px: int = 0,
        cell_height_px: int = 0,
    ) -> Terminal:
        """Resize the grid to ``cols`` by ``rows`` cells.

        The primary screen reflows wrapped content; the alternate screen does
        not. The pixel dimensions feed image protocols and XTWINOPS size
        reports, so pass the real cell metrics when they are known.

        Raises:
            ValueError: If ``cols`` or ``rows`` is not positive.
            GhosttyError: If the terminal is closed or the resize fails.
        """
        if cols <= 0 or rows <= 0:
            raise ValueError(f"cols and rows must be positive, got {cols}x{rows}")
        check(
            self._lib.ghostty_terminal_resize(
                self._require_open(), cols, rows, cell_width_px, cell_height_px
            ),
            "resize terminal",
        )
        return self

    # -- reading ---------------------------------------------------------

    def get(self, data: TerminalData) -> Any:
        """Read a data field, converted to its natural Python type.

        The mapping is documented per member of
        :class:`~khostty_vt.constants.TerminalData`. Fields that expose a
        callback or an owned handle raise :class:`~khostty_vt.GhosttyError`
        rather than being read into the wrong shape.

        Raises:
            GhosttyError: If the terminal is closed, the field has no converter,
                or the library refuses the read.
        """
        return read_field(self._ffi, self._lib, self._require_open(), data)

    # -- rendering -------------------------------------------------------

    def formatter(self, *args: Any, **kwargs: Any) -> Any:
        """Create a :class:`~khostty_vt.Formatter` bound to this terminal."""
        from .formatter import Formatter

        kwargs.setdefault("library", self._library)
        return Formatter(self, *args, **kwargs)

    def text(
        self,
        *,
        trim: bool = True,
        unwrap: bool = False,
        encoding: str = "utf-8",
        errors: str = "replace",
    ) -> str:
        """Render the active screen as plain text.

        Args:
            trim: Strip trailing whitespace from non-blank lines.
            unwrap: Join soft-wrapped lines into logical lines.
            encoding: Decoding used for the rendered bytes.
            errors: Decoding error policy; rendering can emit partial UTF-8.

        Returns:
            The screen contents.
        """
        with self.formatter(trim=trim, unwrap=unwrap) as fmt:
            return fmt.text(encoding, errors)

    def formatted(
        self,
        encoding: str = "utf-8",
        errors: str = "replace",
        **kwargs: Any,
    ) -> str:
        """Render the active screen with a non-plain format.

        Extra keyword arguments are passed to
        :class:`~khostty_vt.Formatter`, so ``formatted(format=Format.HTML)``
        renders HTML.

        Args:
            encoding: Decoding used for the rendered bytes.
            errors: Decoding error policy.
            **kwargs: Forwarded to :class:`~khostty_vt.Formatter`.
        """
        with self.formatter(**kwargs) as fmt:
            return fmt.text(encoding, errors)

    # -- snapshot --------------------------------------------------------

    def snapshot(self) -> bytes:
        """Encode a complete snapshot of this terminal.

        The snapshot is self-contained:
        :func:`khostty_vt.snapshot.restore` decodes it into an equivalent
        terminal, which is how a session is persisted and resumed.

        Raises:
            GhosttyError: If the terminal is closed, or its parser is
                mid-sequence without continuation tracking having been enabled
                before that input was written.
        """
        ffi = self._ffi
        handle = self._require_open()

        out_ptr = ffi.new("uint8_t **")
        out_len = ffi.new("size_t *")
        check(
            self._lib.ghostty_snapshot_encode_alloc(handle, ffi.NULL, out_ptr, out_len),
            "snapshot",
        )

        length = int(out_len[0])
        if not out_ptr[0] or length == 0:
            self._lib.ghostty_free(ffi.NULL, out_ptr[0], 0)
            return b""
        try:
            return bytes(ffi.buffer(out_ptr[0], length))
        finally:
            self._lib.ghostty_free(ffi.NULL, out_ptr[0], length)

    def snapshot_size(self) -> int:
        """Bytes :meth:`snapshot` would produce, without allocating them."""
        from .snapshot import snapshot_size

        return snapshot_size(self, library=self._library)

    def snapshot_buffer(self, size: int) -> Any:
        """Allocate a cffi buffer suitable for :meth:`snapshot_into`.

        Args:
            size: Capacity in bytes; :meth:`snapshot_size` reports the exact
                value needed.

        Returns:
            An ``uint8_t[]`` cffi buffer.
        """
        return self._ffi.new("uint8_t[]", int(size))

    def snapshot_into(self, buffer: Any) -> int:
        """Encode into ``buffer`` and return the number of bytes written.

        Args:
            buffer: A writable cffi buffer large enough for the snapshot. A
                buffer that is too small raises, and may have been partially
                overwritten, so discard its contents rather than appending.

        Raises:
            GhosttyError: If the terminal is closed or the buffer is too small.
        """
        ffi = self._ffi
        handle = self._require_open()
        out = ffi.new("size_t *")
        check(
            self._lib.ghostty_snapshot_encode_buf(handle, buffer, ffi.sizeof(buffer), out),
            "snapshot into buffer",
        )
        return int(out[0])

    # -- search ----------------------------------------------------------

    def search(self, needle: Optional[str] = None, **kwargs: Any) -> Any:
        """Create a :class:`~khostty_vt.Search` bound to this terminal.

        Args:
            needle: Optional initial needle. Nothing is searched until one is
                set; call :meth:`Search.run` or :meth:`Search.feed` to drive it.
        """
        from .search import Search

        kwargs.setdefault("library", self._library)
        return Search(self, needle, **kwargs)

    def find(self, needle: str, **kwargs: Any) -> Any:
        """Create a search for ``needle`` and run it to completion.

        Returns:
            The finished :class:`~khostty_vt.Search`, for reading counts and
            stepping matches. It is the caller's to close, or to use as a
            context manager.
        """
        search = self.search(needle, **kwargs)
        search.run()
        return search
