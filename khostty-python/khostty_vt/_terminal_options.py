"""Terminal option writes.

Each ``GhosttyTerminalOption`` takes a different C value shape: a
``GhosttyString``, a ``bool``, a ``size_t``, an ``int``, or a
``GhosttyColorRgb``, all passed as ``const void *``. This module owns that
mapping so :mod:`khostty_vt.terminal` stays about lifecycle.

Callback options are recognised and rejected with a clear error rather than
being written with the wrong shape.
"""

from __future__ import annotations

from typing import Any, FrozenSet

from .constants import Result, TerminalOption
from .errors import GhosttyError, check

__all__ = ["TerminalOptionsMixin"]

# Options written through a GhosttyString.
_STRING_OPTIONS: FrozenSet[TerminalOption] = frozenset(
    {TerminalOption.TITLE, TerminalOption.PWD, TerminalOption.TERMINFO_NAME}
)

# Options written through a C bool.
_BOOL_OPTIONS: FrozenSet[TerminalOption] = frozenset(
    {
        TerminalOption.DEFAULT_CURSOR_BLINK,
        TerminalOption.TITLE_REPORT,
        TerminalOption.KITTY_IMAGE_MEDIUM_FILE,
        TerminalOption.KITTY_IMAGE_MEDIUM_TEMP_FILE,
        TerminalOption.KITTY_IMAGE_MEDIUM_SHARED_MEM,
    }
)

# Options written through a size_t.
_SIZE_OPTIONS: FrozenSet[TerminalOption] = frozenset(
    {
        TerminalOption.SCROLLBACK_MAX_BYTES,
        TerminalOption.SCROLLBACK_MAX_LINES,
        TerminalOption.CONTINUATION_MAX_BYTES,
        TerminalOption.APC_MAX_BYTES,
        TerminalOption.APC_MAX_BYTES_KITTY,
        TerminalOption.UNKNOWN_MAX_BYTES,
        TerminalOption.KITTY_IMAGE_STORAGE_LIMIT,
        TerminalOption.CLIPBOARD_WRITE_MAX_BYTES,
    }
)

# Options written through a GhosttyColorRgb.
_RGB_OPTIONS: FrozenSet[TerminalOption] = frozenset(
    {
        TerminalOption.COLOR_FOREGROUND,
        TerminalOption.COLOR_BACKGROUND,
        TerminalOption.COLOR_CURSOR,
    }
)

# Options whose value is another struct or a callback.
_UNSUPPORTED_OPTIONS: FrozenSet[TerminalOption] = frozenset(
    {
        TerminalOption.USERDATA,
        TerminalOption.WRITE_PTY,
        TerminalOption.BELL,
        TerminalOption.ENQUIRY,
        TerminalOption.XTVERSION,
        TerminalOption.TITLE_CHANGED,
        TerminalOption.SIZE,
        TerminalOption.COLOR_SCHEME,
        TerminalOption.DEVICE_ATTRIBUTES,
        TerminalOption.COLOR_PALETTE,
        TerminalOption.SELECTION,
        TerminalOption.GLYPH_PROTOCOL,
        TerminalOption.PWD_CHANGED,
        TerminalOption.CLIPBOARD_WRITE,
        TerminalOption.DESKTOP_NOTIFICATION,
        TerminalOption.PROGRESS_REPORT,
        TerminalOption.MODE_DEFAULT,
        TerminalOption.MODE,
        TerminalOption.UNKNOWN_SEQUENCE,
        TerminalOption.CLIPBOARD_READ,
    }
)


class TerminalOptionsMixin:
    """Writing terminal options."""

    __slots__ = ()

    def set_option(self, option: TerminalOption, value: Any) -> Any:
        """Write an option, choosing the C value shape from ``option``.

        Args:
            option: Which option to write.
            value: ``str`` for string options, ``bool`` for flags, ``int`` for
                size limits and the cursor shape, ``(r, g, b)`` for colors.

        Returns:
            ``self``, so calls chain.

        Raises:
            GhosttyError: If the option takes a callback these bindings do not
                expose, or the library refuses the value.
        """
        ffi = self._ffi  # type: ignore[attr-defined]
        lib = self._lib  # type: ignore[attr-defined]
        handle = self._require_open()  # type: ignore[attr-defined]
        option = TerminalOption(option)

        if option in _STRING_OPTIONS:
            payload = str(value).encode("utf-8")
            # The buffer is bound to a local on purpose. Assigning
            # `string.ptr = ffi.new(...)` would store only the raw pointer,
            # letting CPython free the owning cdata immediately and leaving
            # the call reading freed memory.
            buffer = ffi.new("uint8_t[]", payload) if payload else ffi.NULL
            string = ffi.new("GhosttyString *")
            string.ptr = buffer
            string.len = len(payload)
            check(lib.ghostty_terminal_set(handle, int(option), string), "set option")

        elif option in _BOOL_OPTIONS:
            flag = ffi.new("_Bool *", bool(value))
            check(lib.ghostty_terminal_set(handle, int(option), flag), "set option")

        elif option in _SIZE_OPTIONS:
            size = ffi.new("size_t *", int(value))
            check(lib.ghostty_terminal_set(handle, int(option), size), "set option")

        elif option == TerminalOption.DEFAULT_CURSOR_STYLE:
            shape = ffi.new("int *", int(value))
            check(lib.ghostty_terminal_set(handle, int(option), shape), "set option")

        elif option in _RGB_OPTIONS:
            r, g, b = (int(component) for component in value)
            color = ffi.new("GhosttyColorRgb *")
            color.r, color.g, color.b = r, g, b
            check(lib.ghostty_terminal_set(handle, int(option), color), "set option")

        elif option in _UNSUPPORTED_OPTIONS:
            raise GhosttyError(
                int(Result.INVALID_VALUE),
                f"option {option.name} takes a struct or callback that these bindings "
                "do not expose",
            )

        else:  # pragma: no cover - every enum member is covered above
            raise GhosttyError(int(Result.INVALID_VALUE), f"unknown option {option}")

        return self
