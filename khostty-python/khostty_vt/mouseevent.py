"""Mouse input: the event type and the encoder.

The geometry and enum types live in :mod:`khostty_vt.mouse`; this module is the
event and the encoder that turns events into bytes.
"""

from __future__ import annotations

from typing import Any, Optional

from . import _ffi
from .constants import Result
from .errors import GhosttyError
from .mouse import (
    EncoderSize,
    MouseAction,
    MouseButton,
    MouseEncoderOption,
    MouseFormat,
    MousePosition,
    MouseTrackingMode,
)

__all__ = ["MouseEncoder", "MouseEvent", "encode_mouse"]


class MouseEvent:
    """A mutable pointer event handed to a :class:`MouseEncoder`.

    As with key events, one instance can be reconfigured and reused for every
    movement rather than allocating per event.
    """

    __slots__ = ("_closed", "_ffi", "_handle", "_lib", "_ptr")

    def __init__(self, *, library: Optional[str] = None) -> None:
        ffi, lib = _ffi.load(library)
        handle = ffi.new("GhosttyMouseEvent *")
        if lib.ghostty_mouse_event_new(ffi.NULL, handle) != int(Result.SUCCESS):
            raise GhosttyError(int(Result.OUT_OF_MEMORY), "create mouse event")

        self._ffi = ffi
        self._lib = lib
        self._ptr = handle
        self._handle = handle[0]
        self._closed = False

    @property
    def closed(self) -> bool:
        """Whether the underlying event has been freed."""
        return self._closed

    def _require_open(self) -> Any:
        if self._closed:
            raise GhosttyError(int(Result.INVALID_VALUE), "mouse event is closed")
        return self._handle

    def close(self) -> None:
        """Free the event. Idempotent."""
        if self._closed:
            return
        self._lib.ghostty_mouse_event_free(self._handle)
        self._closed = True
        self._handle = None

    def __enter__(self) -> MouseEvent:
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
        return f"<MouseEvent {state}>"

    def set_action(self, action: MouseAction) -> MouseEvent:
        """Set the event phase."""
        self._lib.ghostty_mouse_event_set_action(self._require_open(), int(action))
        return self

    def action(self) -> MouseAction:
        """The event phase."""
        return MouseAction(self._lib.ghostty_mouse_event_get_action(self._require_open()))

    def set_button(self, button: MouseButton) -> MouseEvent:
        """Set which button the event involves."""
        self._lib.ghostty_mouse_event_set_button(self._require_open(), int(button))
        return self

    def clear_button(self) -> MouseEvent:
        """Mark the event as involving no button, which is how bare motion is
        reported."""
        self._lib.ghostty_mouse_event_clear_button(self._require_open())
        return self

    def button(self) -> Optional[MouseButton]:
        """The button, or ``None`` when no button is involved."""
        out = self._ffi.new("int *")
        if not self._lib.ghostty_mouse_event_get_button(self._require_open(), out):
            return None
        return MouseButton(out[0])

    def set_mods(self, mods: int) -> MouseEvent:
        """Set the held modifiers.

        Args:
            mods: A :class:`khostty_vt.Mods` value or plain bitmask.
        """
        self._lib.ghostty_mouse_event_set_mods(self._require_open(), int(mods))
        return self

    def mods(self) -> int:
        """The held modifiers as a raw bitmask."""
        return int(self._lib.ghostty_mouse_event_get_mods(self._require_open()))

    def set_position(self, position: MousePosition) -> MouseEvent:
        """Set the position in surface-space pixels."""
        c_position = self._ffi.new("GhosttyMousePosition *")
        c_position.x = position.x
        c_position.y = position.y
        self._lib.ghostty_mouse_event_set_position(self._require_open(), c_position[0])
        return self

    def position(self) -> MousePosition:
        """The position in surface-space pixels."""
        c_position = self._lib.ghostty_mouse_event_get_position(self._require_open())
        return MousePosition(x=float(c_position.x), y=float(c_position.y))


class MouseEncoder:
    """Encodes pointer events into the byte sequences a pty expects.

    The tracking mode and format are decided by the application and change at
    runtime, so either keep the encoder in step with
    :meth:`sync_from_terminal` or set them explicitly.
    """

    __slots__ = ("_closed", "_ffi", "_handle", "_lib", "_ptr")

    def __init__(self, *, library: Optional[str] = None) -> None:
        ffi, lib = _ffi.load(library)
        handle = ffi.new("GhosttyMouseEncoder *")
        if lib.ghostty_mouse_encoder_new(ffi.NULL, handle) != int(Result.SUCCESS):
            raise GhosttyError(int(Result.OUT_OF_MEMORY), "create mouse encoder")

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
            raise GhosttyError(int(Result.INVALID_VALUE), "mouse encoder is closed")
        return self._handle

    def close(self) -> None:
        """Free the encoder. Idempotent."""
        if self._closed:
            return
        self._lib.ghostty_mouse_encoder_free(self._handle)
        self._closed = True
        self._handle = None

    def __enter__(self) -> MouseEncoder:
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
        return f"<MouseEncoder {state}>"

    def reset(self) -> MouseEncoder:
        """Clear accumulated state such as the last reported cell.

        Call it when the pointer leaves the surface, so re-entry is not treated
        as motion from the old position.
        """
        self._lib.ghostty_mouse_encoder_reset(self._require_open())
        return self

    def sync_from_terminal(self, terminal: Any) -> MouseEncoder:
        """Copy the tracking mode and format the application selected out of a
        terminal.

        Raises:
            GhosttyError: If the terminal is closed.
        """
        handle = self._require_open()
        self._lib.ghostty_mouse_encoder_setopt_from_terminal(handle, terminal._require_open())
        return self

    def set_tracking_mode(self, mode: MouseTrackingMode) -> MouseEncoder:
        """Set the mode reported to the application."""
        value = self._ffi.new("int *", int(mode))
        self._lib.ghostty_mouse_encoder_setopt(
            self._require_open(), int(MouseEncoderOption.EVENT), value
        )
        return self

    def set_format(self, format: MouseFormat) -> MouseEncoder:
        """Set the wire format."""
        value = self._ffi.new("int *", int(format))
        self._lib.ghostty_mouse_encoder_setopt(
            self._require_open(), int(MouseEncoderOption.FORMAT), value
        )
        return self

    def set_size(self, size: EncoderSize) -> MouseEncoder:
        """Set the surface geometry used to map pixels onto cells."""
        self._lib.ghostty_mouse_encoder_setopt(
            self._require_open(), int(MouseEncoderOption.SIZE), size.to_c(self._ffi)
        )
        return self

    def set_any_button_pressed(self, pressed: bool) -> MouseEncoder:
        """Tell the encoder whether any button is currently down.

        This is what decides between press and drag encodings for motion.
        """
        value = self._ffi.new("_Bool *", bool(pressed))
        self._lib.ghostty_mouse_encoder_setopt(
            self._require_open(), int(MouseEncoderOption.ANY_BUTTON_PRESSED), value
        )
        return self

    def set_track_last_cell(self, enabled: bool) -> MouseEncoder:
        """Enable coalescing of motion within the same cell."""
        value = self._ffi.new("_Bool *", bool(enabled))
        self._lib.ghostty_mouse_encoder_setopt(
            self._require_open(), int(MouseEncoderOption.TRACK_LAST_CELL), value
        )
        return self

    def encode(self, event: MouseEvent) -> bytes:
        """Turn an event into bytes.

        An empty result with no error is normal: see the module docstring.

        Raises:
            GhosttyError: If either handle is closed, or the library refuses.
        """
        handle = self._require_open()
        event_handle = event._require_open()
        ffi = self._ffi

        written = ffi.new("size_t *")
        buffer = ffi.new("char[]", 64)
        result = self._lib.ghostty_mouse_encoder_encode(handle, event_handle, buffer, 64, written)
        if result == int(Result.OUT_OF_SPACE):
            size = int(written[0])
            buffer = ffi.new("char[]", size)
            result = self._lib.ghostty_mouse_encoder_encode(
                handle, event_handle, buffer, size, written
            )
        if result != int(Result.SUCCESS):
            raise GhosttyError(result, "encode mouse event")
        return bytes(ffi.buffer(buffer, int(written[0])))


def encode_mouse(
    position: MousePosition,
    button: Optional[MouseButton] = None,
    action: MouseAction = MouseAction.PRESS,
    *,
    mode: MouseTrackingMode = MouseTrackingMode.NORMAL,
    format: MouseFormat = MouseFormat.SGR,
    size: Optional[EncoderSize] = None,
    mods: int = 0,
    any_button_pressed: Optional[bool] = None,
    library: Optional[str] = None,
) -> bytes:
    """Encode a single pointer event.

    A convenience that allocates an encoder and an event per call. A hot path
    should keep a :class:`MouseEncoder` and one reused :class:`MouseEvent`.

    Args:
        position: Position in surface-space pixels.
        button: Button involved, or ``None`` for bare motion.
        action: Event phase.
        mode: Tracking mode to report under.
        format: Wire format.
        size: Cell geometry, needed to map pixels onto cells.
        mods: Modifier bitmask.
        any_button_pressed: Whether any button is down, which decides between
            press and drag encodings for motion.
        library: Explicit shared-library path, for tests.

    Returns:
        The encoded bytes, or ``b""`` when the event is not reportable.
    """
    with MouseEncoder(library=library) as encoder, MouseEvent(library=library) as event:
        encoder.set_tracking_mode(mode).set_format(format)
        if size is not None:
            encoder.set_size(size)

        event.set_action(action).set_position(position).set_mods(mods)
        if button is None:
            event.clear_button()
        else:
            event.set_button(button)
        if any_button_pressed is not None:
            encoder.set_any_button_pressed(any_button_pressed)

        return encoder.encode(event)
