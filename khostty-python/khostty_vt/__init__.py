"""Python bindings for libghostty-vt, the terminal emulator from Ghostty.

The package wraps the C library that ships as ``libghostty-vt`` in a Khostty or
Ghostty checkout. It is meant for tooling that needs to *understand* terminal
output rather than display it: agent harnesses, log scrapers, test helpers.

Quick start::

    from khostty_vt import Terminal

    with Terminal(cols=80, rows=24) as term:
        term.write("$ make test\\r\\n")
        term.write("FAIL: 2 tests failed\\r\\n")
        print(term.text())
        print(term.search("fail").total_matches)

Handles are RAII: :class:`~khostty_vt.Terminal`,
:class:`~khostty_vt.Formatter`, and :class:`~khostty_vt.Search` are context
managers that free the underlying C object on exit, and they also close
themselves from ``__del__`` as a backstop.

Finding the library
-------------------

The shared object is located at first use, not at import, so importing this
package never requires the library to be present or built. Set
``KHOSTTY_VT_LIB`` to a full path or ``KHOSTTY_VT_LIB_DIR`` to a directory, or
build in place so the default search finds it::

    zig build install -Doptimize=ReleaseFast

:func:`khostty_vt.validate_struct_sizes` checks the hand-written cffi
declarations against the library's own type manifest, which is the way to
confirm a mismatched pair of headers and binary rather than debugging the
symptoms.
"""

from __future__ import annotations

from ._ffi import (
    LIBRARY_DIR_ENV,
    LIBRARY_ENV,
    LibraryNotFoundError,
    library_path,
    load,
    reset,
    type_manifest,
    validate_struct_sizes,
)
from ._verify import validate_abi, validate_enum_values
from .constants import (
    CursorShape,
    FormatterFormat,
    Result,
    Screen,
    SearchData,
    SearchOption,
    SearchScroll,
    SearchStatus,
    StyleColorKind,
    TerminalData,
    TerminalOption,
    Underline,
)
from .errors import GhosttyError
from .formatter import Format, Formatter, FormatterExtras, FormatterOptions
from .search import Search
from .snapshot import restore, snapshot_size
from .style import Style, StyleColor
from .terminal import Terminal

__all__ = [
    "LIBRARY_DIR_ENV",
    "LIBRARY_ENV",
    "CursorShape",
    "Format",
    "Formatter",
    "FormatterExtras",
    "FormatterFormat",
    "FormatterOptions",
    "GhosttyError",
    "LibraryNotFoundError",
    "Result",
    "Screen",
    "Search",
    "SearchData",
    "SearchOption",
    "SearchScroll",
    "SearchStatus",
    "Style",
    "StyleColor",
    "StyleColorKind",
    "Terminal",
    "TerminalData",
    "TerminalOption",
    "Underline",
    "__version__",
    "library_path",
    "load",
    "reset",
    "restore",
    "snapshot_size",
    "type_manifest",
    "validate_abi",
    "validate_enum_values",
    "validate_struct_sizes",
]

__version__ = "0.1.0"
