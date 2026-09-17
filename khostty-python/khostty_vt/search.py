"""Searching terminal contents, including scrollback.

A :class:`Search` borrows a terminal. The two may be freed in either order: if
the terminal is freed first the search detaches and still reports what it had
already collected, but setting a needle or selecting a match stops working.

Matching is byte-exact except ASCII letters, which compare case-insensitively,
so a needle of ``"error"`` also finds ``"ERROR"``.

Threading: :meth:`Search.feed`, :meth:`Search.set_needle`, and the select
options read the bound terminal and must be serialized with other access to it.
:meth:`Search.tick`, :meth:`Search.status`, :meth:`Search.total_matches`, and
:meth:`Search.selected_index` only touch search-owned memory.
"""

from __future__ import annotations

from typing import Any, Optional, Tuple

from . import _ffi
from .constants import Result, SearchData, SearchOption, SearchScroll, SearchStatus
from .errors import GhosttyError, check

__all__ = ["Search", "SearchScroll", "SearchStatus"]


class Search:
    """A text search bound to a terminal.

    Example::

        with Terminal(cols=80, rows=24) as term:
            term.write("error one\\r\\nerror two\\r\\n")
            with term.search("error") as found:
                found.run()
                assert found.total_matches == 2
                assert found.select_next() == 0
    """

    __slots__ = ("_closed", "_ffi", "_handle", "_lib", "_needle", "_ptr", "_terminal")

    def __init__(
        self,
        terminal: Any,
        needle: Optional[str] = None,
        *,
        library: Optional[str] = None,
    ) -> None:
        """Create a search bound to ``terminal``.

        Args:
            terminal: The terminal to search. It must outlive this search, or
                be closed first.
            needle: Optional initial needle; nothing is searched until one is
                set, and setting one here does not run the search.
            library: Explicit shared-library path, for tests.

        Raises:
            GhosttyError: If the terminal is closed or the library refuses.
        """
        ffi, lib = _ffi.load(library)
        handle = terminal._require_open()

        search = ffi.new("GhosttySearch *")
        check(lib.ghostty_search_new(ffi.NULL, search, handle), "create search")

        self._ffi = ffi
        self._lib = lib
        self._ptr = search
        self._handle = search[0]
        self._terminal = terminal
        self._needle: Optional[str] = None
        self._closed = False

        if needle is not None:
            self.set_needle(needle)

    @property
    def closed(self) -> bool:
        """Whether the underlying search has been freed."""
        return self._closed

    @property
    def needle(self) -> Optional[str]:
        """The current needle, or ``None`` when none is set."""
        if self._closed:
            return self._needle
        value = self._ffi.new("GhosttyString *")
        result = self._lib.ghostty_search_get(self._handle, int(SearchData.NEEDLE), value)
        if result == int(Result.NO_VALUE):
            return None
        check(result, "read search needle")
        if not value.ptr or value.len == 0:
            return None
        return bytes(self._ffi.buffer(value.ptr, int(value.len))).decode("utf-8", "replace")

    def close(self) -> None:
        """Free the search. Idempotent, and safe after the terminal is gone."""
        if self._closed:
            return
        self._lib.ghostty_search_free(self._handle)
        self._closed = True
        self._handle = None

    def __enter__(self) -> Search:
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
        return f"<Search {state} needle={self._needle!r}>"

    def _require_open(self) -> Any:
        if self._closed:
            raise GhosttyError(int(Result.INVALID_VALUE), "search is closed")
        return self._handle

    def set_needle(self, needle: str) -> Search:
        """Set the text to search for and restart the search.

        Setting a needle equal (case-insensitively) to the current one keeps
        existing results, so a find bar can resubmit freely. An empty needle
        clears the search and returns it to idle.

        Returns:
            ``self``, so the call chains with :meth:`run`.

        Raises:
            GhosttyError: If the search is closed or the library refuses.
        """
        handle = self._require_open()
        ffi = self._ffi

        payload = needle.encode("utf-8") if needle else b""
        if not payload:
            check(
                self._lib.ghostty_search_set(handle, int(SearchOption.NEEDLE), ffi.NULL),
                "clear needle",
            )
            self._needle = None
            return self

        # The library documents that the bytes are copied, but a borrowed
        # buffer still has to stay alive across the call, so it is held in a
        # named cdata object rather than a temporary.
        buffer = ffi.new("uint8_t[]", payload)
        value = ffi.new("GhosttyString *")
        value.ptr = buffer
        value.len = len(payload)
        check(
            self._lib.ghostty_search_set(handle, int(SearchOption.NEEDLE), value),
            "set needle",
        )
        self._needle = needle
        return self

    def run(self) -> Search:
        """Feed and tick until the search is caught up with the terminal.

        A blocking one-shot convenience for single-threaded use. Searching a
        large scrollback can take a while; interactive callers should drive
        :meth:`feed` and :meth:`tick` from their event loop instead.

        Returns:
            ``self``.

        Raises:
            GhosttyError: If the search is closed or the library refuses.
        """
        check(self._lib.ghostty_search_run(self._require_open()), "run search")
        return self

    def feed(self) -> Search:
        """Catch the search up with the terminal.

        This reads the terminal, so serialize it with other access to the same
        terminal. Feeding is the only way the search learns about changes, so
        keep feeding while it is in use, even after it reports
        :attr:`SearchStatus.COMPLETE`.
        """
        check(self._lib.ghostty_search_feed(self._require_open()), "feed search")
        return self

    def tick(self) -> SearchStatus:
        """Make a bounded amount of progress on already-copied data.

        This never reads the terminal. Loop while the status is
        :attr:`SearchStatus.RUNNING` and switch to :meth:`feed` when it becomes
        :attr:`SearchStatus.FEED_REQUIRED`.
        """
        out = self._ffi.new("int *")
        check(self._lib.ghostty_search_tick(self._require_open(), out), "tick search")
        return SearchStatus(out[0])

    def status(self) -> SearchStatus:
        """Current status, without reading the terminal."""
        out = self._ffi.new("int *")
        check(
            self._lib.ghostty_search_get(self._require_open(), int(SearchData.STATUS), out),
            "read search status",
        )
        return SearchStatus(out[0])

    def total_matches(self) -> int:
        """Number of matches on the active screen. Zero until the first feed."""
        out = self._ffi.new("size_t *")
        check(
            self._lib.ghostty_search_get(self._require_open(), int(SearchData.TOTAL_MATCHES), out),
            "read total matches",
        )
        return int(out[0])

    def selected_index(self) -> Optional[int]:
        """Index of the selected match, or ``None`` when nothing is selected.

        Index ``0`` is the newest match and the list runs newest to oldest, so
        a ``"k of n"`` label renders ``index + 1`` of :meth:`total_matches`.
        """
        out = self._ffi.new("size_t *")
        result = self._lib.ghostty_search_get(
            self._require_open(), int(SearchData.SELECTED_INDEX), out
        )
        if result == int(Result.NO_VALUE):
            return None
        check(result, "read selected index")
        return int(out[0])

    def _select(self, option: SearchOption) -> Optional[int]:
        """Apply a select option and return the resulting index."""
        check(
            self._lib.ghostty_search_set(self._require_open(), int(option), self._ffi.NULL),
            f"search {option.name.lower()}",
        )
        return self.selected_index()

    def select_next(self) -> Optional[int]:
        """Select the next match, moving toward older content, wrapping around.

        Scrolls the viewport per the scroll policy. Reads the terminal, so
        serialize it with other access to the same terminal.

        Returns:
            The new selected index, or ``None`` when there are no matches.
        """
        return self._select(SearchOption.SELECT_NEXT)

    def select_prev(self) -> Optional[int]:
        """Select the previous match, moving toward newer content."""
        return self._select(SearchOption.SELECT_PREV)

    def set_scroll_policy(self, policy: SearchScroll = SearchScroll.IF_NEEDED) -> None:
        """Set the viewport policy applied by the select methods."""
        value = self._ffi.new("int *", int(policy))
        check(
            self._lib.ghostty_search_set(
                self._require_open(),
                int(SearchOption.SELECT_SCROLL),
                value,
            ),
            "set scroll policy",
        )

    def scroll_policy(self) -> SearchScroll:
        """Current viewport policy."""
        out = self._ffi.new("int *")
        check(
            self._lib.ghostty_search_get(self._require_open(), int(SearchData.SELECT_SCROLL), out),
            "read scroll policy",
        )
        return SearchScroll(out[0])

    def viewport_matches(self) -> int:
        """Number of matches covering the viewport, for drawing highlights.

        The list is computed during feeds and cached, so it reflects the
        viewport as of the last feed, and can include matches just outside the
        visible viewport when they share a page with it. The count is obtained
        by asking for the required buffer capacity, so no selection objects
        cross the boundary.
        """
        out = self._ffi.new("GhosttySelectionBuffer *")
        out.ptr = self._ffi.NULL
        out.cap = 0
        out.len = 0
        result = self._lib.ghostty_search_get(
            self._require_open(), int(SearchData.VIEWPORT_MATCHES), out
        )
        if result in (int(Result.SUCCESS), int(Result.OUT_OF_SPACE)):
            return int(out.len)
        raise GhosttyError(result, "read viewport matches")

    def counts(self) -> Tuple[int, int]:
        """``(total_matches, viewport_matches)`` in one call."""
        return self.total_matches(), self.viewport_matches()
