"""Key event encoding.

Turns a key event into the byte sequence a pty expects, under whichever scheme
the application selected: legacy encoding, xterm modifyOtherKeys, or the Kitty
keyboard protocol.

Two facts about the C API are easy to miss, and both are covered by tests:

* A printable key encodes to **nothing** unless its text is set. A physical key
  code does not say which character was produced, so
  :meth:`KeyEvent.set_utf8` is required for anything that types a character.
* Kitty encoding additionally needs the **unshifted codepoint**. With Kitty
  flags enabled but no codepoint the result is empty; with it, ``Ctrl+C``
  becomes ``\\x1b[99;5u``.
"""

from __future__ import annotations

from enum import IntEnum, IntFlag
from typing import Any, Optional, Union

from . import _ffi
from ._enums_gen import Keys
from .constants import Result
from .errors import GhosttyError

__all__ = [
    "KeyAction",
    "KeyEncoderOption",
    "KeyEvent",
    "Keys",
    "KittyFlags",
    "Mods",
    "OptionAsAlt",
]


class Mods(IntFlag):
    """Modifier bitmask, mirroring the ``GHOSTTY_MODS_*`` constants.

    The ``*_SIDE`` bits are only meaningful when the corresponding base
    modifier is also set.
    """

    NONE = 0
    SHIFT = 1 << 0
    CTRL = 1 << 1
    ALT = 1 << 2
    SUPER = 1 << 3
    CAPS_LOCK = 1 << 4
    NUM_LOCK = 1 << 5
    SHIFT_SIDE = 1 << 6
    CTRL_SIDE = 1 << 7
    ALT_SIDE = 1 << 8
    SUPER_SIDE = 1 << 9


class KeyAction(IntEnum):
    """Phase of a key event."""

    RELEASE = 0
    PRESS = 1
    REPEAT = 2


class OptionAsAlt(IntEnum):
    """How the platform's Option key is reported."""

    FALSE = 0
    TRUE = 1
    LEFT = 2
    RIGHT = 3


class KittyFlags(IntFlag):
    """Kitty keyboard protocol flags, passed to the encoder verbatim."""

    DISABLED = 0
    DISAMBIGUATE = 1 << 0
    REPORT_EVENTS = 1 << 1
    REPORT_ALTERNATES = 1 << 2
    REPORT_ALL = 1 << 3
    REPORT_ASSOCIATED = 1 << 4
    ALL = DISAMBIGUATE | REPORT_EVENTS | REPORT_ALTERNATES | REPORT_ALL | REPORT_ASSOCIATED


class KeyEncoderOption(IntEnum):
    """Writable encoder settings.

    ``KITTY_FLAGS`` is a byte-sized bitmask and ``MACOS_OPTION_AS_ALT`` an
    int-sized enum, so they have dedicated setters rather than going through
    :meth:`KeyEncoder.set_flag`.
    """

    CURSOR_KEY_APPLICATION = 0
    KEYPAD_KEY_APPLICATION = 1
    IGNORE_KEYPAD_WITH_NUMLOCK = 2
    ALT_ESC_PREFIX = 3
    MODIFY_OTHER_KEYS_STATE_2 = 4
    KITTY_FLAGS = 5
    MACOS_OPTION_AS_ALT = 6
    BACKARROW_KEY_MODE = 7


class KeyEvent:
    """A mutable input event handed to a :class:`KeyEncoder`.

    One event can be reconfigured and reused for every keystroke rather than
    allocating per event, which is what the C API recommends.
    """

    __slots__ = ("_closed", "_ffi", "_handle", "_lib", "_ptr", "_utf8_buffer")

    def __init__(self, *, library: Optional[str] = None) -> None:
        ffi, lib = _ffi.load(library)
        handle = ffi.new("GhosttyKeyEvent *")
        if lib.ghostty_key_event_new(ffi.NULL, handle) != int(Result.SUCCESS):
            raise GhosttyError(int(Result.OUT_OF_MEMORY), "create key event")

        self._ffi = ffi
        self._lib = lib
        self._ptr = handle
        self._handle = handle[0]
        #: Holds the bytes last passed to set_utf8. The C API documents that
        #: the event does not take ownership of the text pointer, so the buffer
        #: has to outlive the call; keeping it here makes it live as long as
        #: the event does. Without this CPython frees it immediately and
        #: encoding silently produces garbage instead of the typed character.
        self._utf8_buffer = None
        self._closed = False

    @property
    def closed(self) -> bool:
        """Whether the underlying event has been freed."""
        return self._closed

    def _require_open(self) -> Any:
        if self._closed:
            raise GhosttyError(int(Result.INVALID_VALUE), "key event is closed")
        return self._handle

    def close(self) -> None:
        """Free the event. Idempotent."""
        if self._closed:
            return
        self._lib.ghostty_key_event_free(self._handle)
        self._closed = True
        self._handle = None
        self._utf8_buffer = None

    def __enter__(self) -> KeyEvent:
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
        return f"<KeyEvent {state}>"

    def set_key(self, key: Union[int, Keys]) -> KeyEvent:
        """Set which physical key the event describes."""
        self._lib.ghostty_key_event_set_key(self._require_open(), int(key))
        return self

    def key(self) -> int:
        """The event's physical key, as a raw value."""
        return int(self._lib.ghostty_key_event_get_key(self._require_open()))

    def set_action(self, action: KeyAction) -> KeyEvent:
        """Set the event phase."""
        self._lib.ghostty_key_event_set_action(self._require_open(), int(action))
        return self

    def action(self) -> KeyAction:
        """The event phase."""
        return KeyAction(self._lib.ghostty_key_event_get_action(self._require_open()))

    def set_mods(self, mods: Mods) -> KeyEvent:
        """Set the held modifiers."""
        self._lib.ghostty_key_event_set_mods(self._require_open(), int(mods))
        return self

    def mods(self) -> Mods:
        """The held modifiers."""
        return Mods(self._lib.ghostty_key_event_get_mods(self._require_open()))

    def set_consumed_mods(self, mods: Mods) -> KeyEvent:
        """Set modifiers the key itself consumes, so they are not re-reported."""
        self._lib.ghostty_key_event_set_consumed_mods(self._require_open(), int(mods))
        return self

    def consumed_mods(self) -> Mods:
        """The consumed modifiers."""
        return Mods(self._lib.ghostty_key_event_get_consumed_mods(self._require_open()))

    def set_composing(self, composing: bool) -> KeyEvent:
        """Mark the key as part of an IME composition."""
        self._lib.ghostty_key_event_set_composing(self._require_open(), composing)
        return self

    def composing(self) -> bool:
        """Whether the key is part of an IME composition."""
        return bool(self._lib.ghostty_key_event_get_composing(self._require_open()))

    def set_utf8(self, text: str) -> KeyEvent:
        """Set the text this key produces.

        This is what makes a printable key encode at all, and what carries
        composed input from dead keys and IMEs.

        The bytes are retained by the event, because the C API borrows the
        pointer rather than copying it. Setting new text releases the previous
        buffer.
        """
        handle = self._require_open()
        payload = text.encode("utf-8")
        self._utf8_buffer = self._ffi.new("char[]", payload) if payload else None
        self._lib.ghostty_key_event_set_utf8(
            handle,
            self._utf8_buffer if self._utf8_buffer is not None else self._ffi.NULL,
            len(payload),
        )
        return self

    def utf8(self) -> str:
        """The text this key produces."""
        out = self._ffi.new("size_t *")
        ptr = self._lib.ghostty_key_event_get_utf8(self._require_open(), out)
        length = int(out[0])
        if not ptr or length == 0:
            return ""
        return bytes(self._ffi.buffer(ptr, length)).decode("utf-8", "replace")

    def set_unshifted_codepoint(self, codepoint: int) -> KeyEvent:
        """Set the codepoint the key produces unshifted.

        The Kitty protocol needs this; without it a Kitty encode produces
        nothing.
        """
        self._lib.ghostty_key_event_set_unshifted_codepoint(self._require_open(), int(codepoint))
        return self

    def unshifted_codepoint(self) -> int:
        """The unshifted codepoint."""
        return int(self._lib.ghostty_key_event_get_unshifted_codepoint(self._require_open()))
