"""Terminal input: feeding bytes through the VT parser.

Split from :mod:`khostty_vt.terminal` because the write path is where the
Python-to-C byte handling lives, and it is the hot path. The mixin relies on the
host class providing ``_ffi``, ``_lib``, ``_require_open()``, and
``_total_written``.
"""

from __future__ import annotations

from typing import Iterable, Union

from .constants import Result
from .errors import check

__all__ = ["TerminalWriteMixin", "Writable"]

#: Types the write path accepts.
Writable = Union[str, bytes, bytearray, memoryview]


class TerminalWriteMixin:
    """Feeding bytes into a terminal."""

    __slots__ = ()

    def write(self, data: Union[Writable, Iterable[Writable]]) -> int:
        """Feed bytes through the terminal's VT parser.

        This mirrors ``ghostty_terminal_vt_write``, which cannot fail: malformed
        input is logged internally and the parser is kept consistent rather than
        reporting an error. Queries and device-status reports are discarded,
        since these bindings install no write-PTY callback.

        Args:
            data: ``str`` (encoded as UTF-8), a bytes-like object, or an
                iterable of those. An iterable is fed chunk by chunk, which is
                how bytes arrive from a pty in arbitrarily split writes.

        Returns:
            The number of bytes fed.

        Raises:
            GhosttyError: If the terminal is closed.
            TypeError: If an element is not a str or bytes-like object.
        """
        handle = self._require_open()  # type: ignore[attr-defined]

        if isinstance(data, (str, bytes, bytearray, memoryview)):
            chunks: Iterable[Writable] = (data,)
        elif isinstance(data, Iterable):
            chunks = data
        else:
            raise TypeError(
                f"write() expects str, bytes-like, or an iterable of them, got {type(data)}"
            )

        total = 0
        ffi = self._ffi  # type: ignore[attr-defined]
        lib = self._lib  # type: ignore[attr-defined]
        for chunk in chunks:
            payload = self._encode(chunk)
            if not payload:
                continue
            # The buffer is a named cdata object so it stays alive across the
            # call; a temporary would still be referenced, but naming it keeps
            # the lifetime obvious.
            buffer = ffi.new("uint8_t[]", payload)
            lib.ghostty_terminal_vt_write(handle, buffer, len(payload))
            total += len(payload)

        self._total_written += total  # type: ignore[attr-defined]
        return total

    @staticmethod
    def _encode(chunk: Writable) -> bytes:
        """Normalise one chunk to bytes."""
        if isinstance(chunk, str):
            return chunk.encode("utf-8")
        if isinstance(chunk, (bytes, bytearray, memoryview)):
            return bytes(chunk)
        raise TypeError(f"cannot write {type(chunk).__name__}; expected str or bytes-like")

    def write_until_ground(self, data: Writable) -> tuple:
        """Write only the shortest prefix needed to reach ground.

        Ground is the stateless point of the stream: not inside a UTF-8
        sequence, ESC, CSI, or OSC. It is the safe place to inject out-of-band
        sequences, which is how an embedder interleaves its own writes with a
        pty's.

        Args:
            data: Bytes to feed.

        Returns:
            ``(consumed, reached_ground)``. ``consumed`` counts bytes up to and
            including the one that reaches ground, so zero means the stream was
            already at ground and nothing was written. ``reached_ground`` is
            False when the whole slice was consumed without reaching ground
            (the C API's ``GHOSTTY_NO_VALUE``).

        Raises:
            GhosttyError: If the terminal is closed.
        """
        handle = self._require_open()  # type: ignore[attr-defined]
        payload = self._encode(data)
        if not payload:
            return 0, True

        ffi = self._ffi  # type: ignore[attr-defined]
        lib = self._lib  # type: ignore[attr-defined]

        buffer = ffi.new("uint8_t[]", payload)
        out = ffi.new("size_t *")
        result = lib.ghostty_terminal_vt_write_until_ground(handle, buffer, len(payload), out)
        consumed = int(out[0])
        if result == int(Result.NO_VALUE):
            return consumed, False
        check(result, "write until ground")
        return consumed, True

    @property
    def bytes_written(self) -> int:
        """Total bytes fed through :meth:`write`."""
        return self._total_written  # type: ignore[attr-defined]
