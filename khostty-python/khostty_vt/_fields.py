"""Decoding of ``ghostty_terminal_get`` data fields.

The C API returns one untyped ``void *`` per field, whose concrete type depends
on the ``GhosttyTerminalData`` key. This module owns that mapping in one place:
the key groups below, split by the C type they are written through, and
:func:`read_field` which performs the read and converts to a Python value.

Fields that expose a callback or an owned handle have no converter and are
reported as unsupported rather than read into the wrong shape.
"""

from __future__ import annotations

from typing import Any

from .constants import Result, Screen, TerminalData
from .errors import GhosttyError, check
from .style import read_cursor_style

__all__ = ["read_field"]

# Fields written through a uint16_t out-parameter.
_UINT16_FIELDS = frozenset(
    {
        TerminalData.COLS,
        TerminalData.ROWS,
        TerminalData.CURSOR_X,
        TerminalData.CURSOR_Y,
    }
)

# Fields written through a C bool out-parameter.
_BOOL_FIELDS = frozenset(
    {
        TerminalData.CURSOR_PENDING_WRAP,
        TerminalData.CURSOR_VISIBLE,
        TerminalData.MOUSE_TRACKING,
        TerminalData.VT_GROUND,
        TerminalData.CURSOR_AT_PROMPT,
        TerminalData.KITTY_IMAGE_MEDIUM_FILE,
        TerminalData.KITTY_IMAGE_MEDIUM_TEMP_FILE,
        TerminalData.KITTY_IMAGE_MEDIUM_SHARED_MEM,
    }
)

# Fields written through a size_t out-parameter.
_SIZE_FIELDS = frozenset(
    {
        TerminalData.TOTAL_ROWS,
        TerminalData.SCROLLBACK_ROWS,
        TerminalData.SCROLLBACK_MAX_BYTES,
        TerminalData.SCROLLBACK_MAX_LINES,
        TerminalData.CONTINUATION_MAX_BYTES,
        TerminalData.KITTY_IMAGE_STORAGE_LIMIT,
        TerminalData.CLIPBOARD_WRITE_MAX_BYTES,
    }
)

# Fields written through a uint32_t out-parameter.
_UINT32_FIELDS = frozenset({TerminalData.WIDTH_PX, TerminalData.HEIGHT_PX})

# Fields written through a GhosttyString out-parameter, borrowed from the
# terminal for the duration of the call.
_STRING_FIELDS = frozenset({TerminalData.TITLE, TerminalData.PWD})

# Fields written through a GhosttyColorRgb out-parameter.
_RGB_FIELDS = frozenset(
    {
        TerminalData.COLOR_FOREGROUND,
        TerminalData.COLOR_BACKGROUND,
        TerminalData.COLOR_CURSOR,
        TerminalData.COLOR_FOREGROUND_DEFAULT,
        TerminalData.COLOR_BACKGROUND_DEFAULT,
        TerminalData.COLOR_CURSOR_DEFAULT,
    }
)

# Fields whose value type is a handle or callback, so there is nothing safe to
# convert into a Python object.
_OPAQUE_FIELDS = frozenset(
    {
        TerminalData.INVALID,
        TerminalData.COLOR_PALETTE,
        TerminalData.COLOR_PALETTE_DEFAULT,
        TerminalData.KITTY_GRAPHICS,
        TerminalData.SELECTION,
        TerminalData.MODE,
    }
)


def read_field(ffi: Any, lib: Any, handle: Any, data: TerminalData) -> Any:
    """Read one data field from an open terminal handle.

    Args:
        ffi: The cffi ``FFI`` instance holding the declarations.
        lib: The opened library.
        handle: A live ``GhosttyTerminal``.
        data: Which field to read.

    Returns:
        The value converted to the Python type documented by ``data``. See
        :class:`~khostty_vt.constants.TerminalData`.

    Raises:
        GhosttyError: If the field has no converter, or the library refuses.
    """
    data = TerminalData(data)

    if data in _UINT16_FIELDS:
        out = ffi.new("uint16_t *")
        check(lib.ghostty_terminal_get(handle, int(data), out), "read data")
        return int(out[0])

    if data in _BOOL_FIELDS:
        out = ffi.new("_Bool *")
        check(lib.ghostty_terminal_get(handle, int(data), out), "read data")
        return bool(out[0])

    if data in _SIZE_FIELDS:
        out = ffi.new("size_t *")
        check(lib.ghostty_terminal_get(handle, int(data), out), "read data")
        return int(out[0])

    if data in _UINT32_FIELDS:
        out = ffi.new("uint32_t *")
        check(lib.ghostty_terminal_get(handle, int(data), out), "read data")
        return int(out[0])

    if data in _STRING_FIELDS:
        out = ffi.new("GhosttyString *")
        check(lib.ghostty_terminal_get(handle, int(data), out), "read data")
        if not out.ptr or out.len == 0:
            return ""
        return bytes(ffi.buffer(out.ptr, int(out.len))).decode("utf-8", "replace")

    if data in _RGB_FIELDS:
        out = ffi.new("GhosttyColorRgb *")
        check(lib.ghostty_terminal_get(handle, int(data), out), "read data")
        return (int(out.r), int(out.g), int(out.b))

    if data == TerminalData.ACTIVE_SCREEN:
        out = ffi.new("int *")
        check(lib.ghostty_terminal_get(handle, int(data), out), "read data")
        return Screen(out[0])

    if data == TerminalData.CURSOR_STYLE:
        return read_cursor_style(ffi, lib, handle)

    if data == TerminalData.SCROLLBAR:
        out = ffi.new("GhosttyTerminalScrollbar *")
        check(lib.ghostty_terminal_get(handle, int(data), out), "read data")
        return {"total": int(out.total), "offset": int(out.offset), "len": int(out.len)}

    if data == TerminalData.KITTY_KEYBOARD_FLAGS:
        out = ffi.new("uint8_t *")
        check(lib.ghostty_terminal_get(handle, int(data), out), "read data")
        return int(out[0])

    if data in _OPAQUE_FIELDS:
        raise GhosttyError(
            int(Result.INVALID_VALUE),
            f"{data.name} exposes a handle or callback and has no Python converter",
        )

    raise GhosttyError(
        int(Result.INVALID_VALUE),
        f"{data.name} has no converter in these bindings",
    )
