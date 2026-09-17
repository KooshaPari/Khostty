"""Exception types for the libghostty-vt bindings.

The C API reports every failure as one of a small set of ``GhosttyResult``
codes. :func:`check` turns those into exceptions at the boundary, so no result
code ever reaches calling code as a bare integer.
"""

from __future__ import annotations

from typing import Optional

__all__ = ["GhosttyError", "LibraryNotFoundError", "RESULT_NAMES", "check"]


# Result codes, mirroring GhosttyResult in include/ghostty/vt/types.h.
SUCCESS = 0
OUT_OF_MEMORY = -1
INVALID_VALUE = -2
OUT_OF_SPACE = -3
NO_VALUE = -4
IO_ERROR = -5
LIMIT_EXCEEDED = -6
REJECTED = -7

RESULT_NAMES = {
    SUCCESS: "SUCCESS",
    OUT_OF_MEMORY: "OUT_OF_MEMORY",
    INVALID_VALUE: "INVALID_VALUE",
    OUT_OF_SPACE: "OUT_OF_SPACE",
    NO_VALUE: "NO_VALUE",
    IO_ERROR: "IO_ERROR",
    LIMIT_EXCEEDED: "LIMIT_EXCEEDED",
    REJECTED: "REJECTED",
}

_MESSAGES = {
    OUT_OF_MEMORY: "libghostty-vt could not allocate memory",
    INVALID_VALUE: "libghostty-vt rejected the value (bad argument or released handle)",
    OUT_OF_SPACE: "the buffer provided to libghostty-vt was too small",
    NO_VALUE: "libghostty-vt has no value for this query",
    IO_ERROR: "libghostty-vt reader or writer failed",
    LIMIT_EXCEEDED: "encoded input exceeded a configured limit",
    REJECTED: "libghostty-vt refused the operation on a safety check",
}


class GhosttyError(RuntimeError):
    """A libghostty-vt call returned a non-success ``GhosttyResult``.

    Attributes:
        code: The raw C result code, so callers can still branch on it.
        name: The symbolic name of the code, e.g. ``"NO_VALUE"``.
    """

    def __init__(self, code: int, context: Optional[str] = None) -> None:
        self.code = code
        self.name = RESULT_NAMES.get(code, f"UNKNOWN({code})")
        message = _MESSAGES.get(code, f"libghostty-vt returned result {code}")
        if context:
            message = f"{context}: {message}"
        super().__init__(f"{message} [{self.name}]")


class LibraryNotFoundError(OSError):
    """Re-exported so callers can catch it from the package root."""


def check(result: int, context: Optional[str] = None) -> None:
    """Raise :class:`GhosttyError` unless ``result`` is success.

    Args:
        result: A ``GhosttyResult`` value returned by the C API.
        context: Optional description of the operation, used in the message.
    """
    if result != SUCCESS:
        raise GhosttyError(result, context)
