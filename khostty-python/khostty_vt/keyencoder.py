"""Key encoding: the encoder and its one-shot convenience.

The event type lives in :mod:`khostty_vt.key`; this module is the encoder that
turns events into bytes.
"""

from __future__ import annotations

from typing import Any, Optional, Union

from . import _ffi
from ._enums_gen import Keys
from .constants import Result
from .errors import GhosttyError
from .key import (
    KeyAction,
    KeyEncoderOption,
    KeyEvent,
    KittyFlags,
    Mods,
    OptionAsAlt,
)

__all__ = ["KeyEncoder", "encode_key"]


class KeyEncoder:
    """Encodes key events into the byte sequences a pty expects.

    The encoder holds the mode state that decides which encoding applies, so
    it should be long-lived and kept in step with the terminal it feeds, either
    with :meth:`sync_from_terminal` or explicitly.
    """

    __slots__ = ("_closed", "_ffi", "_handle", "_lib", "_ptr")

    def __init__(self, *, library: Optional[str] = None) -> None:
        ffi, lib = _ffi.load(library)
        handle = ffi.new("GhosttyKeyEncoder *")
        if lib.ghostty_key_encoder_new(ffi.NULL, handle) != int(Result.SUCCESS):
            raise GhosttyError(int(Result.OUT_OF_MEMORY), "create key encoder")

        self._ffi = ffi
        self._lib = lib
        self._ptr = handle
        self._handle = handle[0]
        self._closed = False

    @property
    def closed(self) -> bool:
        """Whether the underlying encoder has been freed."""
        return self._closed

    def _require_open(self) -> Any:
        if self._closed:
            raise GhosttyError(int(Result.INVALID_VALUE), "key encoder is closed")
        return self._handle

    def close(self) -> None:
        """Free the encoder. Idempotent."""
        if self._closed:
            return
        self._lib.ghostty_key_encoder_free(self._handle)
        self._closed = True
        self._handle = None

    def __enter__(self) -> KeyEncoder:
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
        return f"<KeyEncoder {state}>"

    def set_flag(self, option: KeyEncoderOption, value: bool) -> KeyEncoder:
        """Set a boolean encoder option.

        These are the DEC-mode-shaped settings: cursor key application (mode
        1), keypad application, alt-ESC prefix (mode 1036), backarrow key mode,
        and so on.
        """
        flag = self._ffi.new("_Bool *", bool(value))
        self._lib.ghostty_key_encoder_setopt(self._require_open(), int(option), flag)
        return self

    def set_kitty_flags(self, flags: KittyFlags) -> KeyEncoder:
        """Set the Kitty keyboard protocol flags, passed through verbatim."""
        value = self._ffi.new("uint8_t *", int(flags))
        self._lib.ghostty_key_encoder_setopt(
            self._require_open(), int(KeyEncoderOption.KITTY_FLAGS), value
        )
        return self

    def set_option_as_alt(self, mode: OptionAsAlt) -> KeyEncoder:
        """Set how the platform's Option key is reported."""
        value = self._ffi.new("int *", int(mode))
        self._lib.ghostty_key_encoder_setopt(
            self._require_open(), int(KeyEncoderOption.MACOS_OPTION_AS_ALT), value
        )
        return self

    def sync_from_terminal(self, terminal: Any) -> KeyEncoder:
        """Copy the modes that affect key encoding out of a terminal.

        This is what makes arrows follow the application's DEC mode 1 and Kitty
        flags without the caller tracking them. Call it after the application
        changes modes.

        Args:
            terminal: An open terminal.

        Raises:
            GhosttyError: If the terminal is closed.
        """
        handle = self._require_open()
        self._lib.ghostty_key_encoder_setopt_from_terminal(handle, terminal._require_open())
        return self

    def encode(self, event: KeyEvent) -> bytes:
        """Turn an event into bytes.

        See the module docstring for the two requirements that make an encode
        produce nothing: a printable key without text, and Kitty flags without
        an unshifted codepoint.

        Raises:
            GhosttyError: If either handle is closed, or the library refuses.
        """
        handle = self._require_open()
        event_handle = event._require_open()
        ffi = self._ffi

        written = ffi.new("size_t *")
        buffer = ffi.new("char[]", 128)
        result = self._lib.ghostty_key_encoder_encode(handle, event_handle, buffer, 128, written)
        if result == int(Result.OUT_OF_SPACE):
            size = int(written[0])
            buffer = ffi.new("char[]", size)
            result = self._lib.ghostty_key_encoder_encode(
                handle, event_handle, buffer, size, written
            )
        if result != int(Result.SUCCESS):
            raise GhosttyError(result, "encode key")
        return bytes(ffi.buffer(buffer, int(written[0])))


def encode_key(
    key: Union[int, Keys],
    mods: Mods = Mods.NONE,
    action: KeyAction = KeyAction.PRESS,
    *,
    utf8: Optional[str] = None,
    codepoint: Optional[int] = None,
    kitty_flags: Optional[KittyFlags] = None,
    option_as_alt: Optional[OptionAsAlt] = None,
    alt_esc_prefix: Optional[bool] = None,
    library: Optional[str] = None,
) -> bytes:
    """Encode a single keystroke.

    This is a convenience that allocates an encoder and an event per call, which
    is right for tests and occasional use. A hot path should keep a
    :class:`KeyEncoder` and one reused :class:`KeyEvent`.

    Args:
        key: Physical key code.
        mods: Held modifiers.
        action: Event phase.
        utf8: Text the key produces. Required for printable keys.
        codepoint: Unshifted codepoint. Required for Kitty encoding.
        kitty_flags: Kitty protocol flags to enable.
        option_as_alt: Option-as-Alt behaviour.
        alt_esc_prefix: Enable the DEC 1036 alt-ESC prefix. An Alt prefix needs
            this *and* ``option_as_alt``.
        library: Explicit shared-library path, for tests.

    Returns:
        The encoded bytes, or ``b""`` when the event is not encodable.
    """
    with KeyEncoder(library=library) as encoder, KeyEvent(library=library) as event:
        if kitty_flags is not None:
            encoder.set_kitty_flags(kitty_flags)
        if option_as_alt is not None:
            encoder.set_option_as_alt(option_as_alt)
        if alt_esc_prefix is not None:
            encoder.set_flag(KeyEncoderOption.ALT_ESC_PREFIX, alt_esc_prefix)

        event.set_key(key)
        event.set_mods(mods)
        event.set_action(action)
        if utf8 is not None:
            event.set_utf8(utf8)
        if codepoint is not None:
            event.set_unshifted_codepoint(codepoint)

        return encoder.encode(event)
