"""Snapshot encoding and restore.

A snapshot is a self-contained byte stream capturing a terminal's screen,
modes, and unfinished VT parser state. Decoding it yields a fresh terminal that
renders identically, which is how a session can be persisted and resumed.

:func:`restore` is the decoder entry point; :meth:`khostty_vt.Terminal.snapshot`
produces the bytes.
"""

from __future__ import annotations

from typing import Any, Optional

from . import _ffi
from .constants import Result
from .errors import GhosttyError, check

__all__ = ["restore", "snapshot_size"]


def snapshot_size(terminal: Any, *, library: Optional[str] = None) -> int:
    """Number of bytes :meth:`Terminal.snapshot` would produce, without encoding.

    This is the two-call pattern the C API documents: query with a NULL buffer,
    then encode into a buffer of the reported size. Use it to reuse one buffer
    across frames.

    Args:
        terminal: An open terminal.
        library: Explicit shared-library path, for tests.

    Returns:
        The required capacity in bytes.

    Raises:
        GhosttyError: If the terminal is closed or the library refuses.
    """
    ffi, lib = _ffi.load(library)
    handle = terminal._require_open()
    out = ffi.new("size_t *")
    result = lib.ghostty_snapshot_encode_buf(handle, ffi.NULL, 0, out)
    if result == int(Result.OUT_OF_SPACE):
        return int(out[0])
    check(result, "query snapshot size")
    return int(out[0])


def restore(data: bytes, *, library: Optional[str] = None) -> Any:
    """Decode snapshot bytes into a new :class:`~khostty_vt.Terminal`.

    Ownership of the decoded terminal passes to the caller, which is
    responsible for closing it; the decoder itself is freed here.

    Args:
        data: Bytes produced by :meth:`Terminal.snapshot`.
        library: Explicit shared-library path, for tests.

    Returns:
        A new terminal. Close it, or use it as a context manager.

    Raises:
        GhosttyError: If `data` is empty or cannot be decoded.
    """
    if not data:
        raise GhosttyError(int(Result.INVALID_VALUE), "restore snapshot: no data")

    from .terminal import Terminal

    ffi, lib = _ffi.load(library)

    # The decoder keeps the source pointer for the duration of the decode, so
    # the bytes live in cffi-owned memory rather than a Python buffer.
    source = ffi.new("uint8_t[]", data)

    decoder = ffi.new("GhosttySnapshotDecoder *")
    check(
        lib.ghostty_snapshot_decoder_new_buf(ffi.NULL, decoder, source, len(data)),
        "create snapshot decoder",
    )

    try:
        handle = ffi.new("GhosttyTerminal *")
        check(lib.ghostty_snapshot_decoder_decode(decoder[0], handle), "decode snapshot")
        terminal = Terminal.__new__(Terminal)
        terminal._adopt(ffi, lib, handle)
        return terminal
    finally:
        lib.ghostty_snapshot_decoder_free(decoder[0])
