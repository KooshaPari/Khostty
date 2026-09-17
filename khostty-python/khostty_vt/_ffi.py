"""Shared-library discovery and loading for ``libghostty-vt``.

The C declarations live in :mod:`khostty_vt._cdef`; this module is only about
finding and opening the shared object they describe, and about checking that
the two still agree. It is an ABI-mode binding: nothing is compiled, an
already-built library is opened with ``dlopen``.

Library discovery order
-----------------------

1. ``KHOSTTY_VT_LIB`` -- full path to the shared object.
2. ``KHOSTTY_VT_LIB_DIR`` -- directory containing it.
3. Paths relative to the installed package: ``../../zig-out/lib`` and
   ``../zig-out/lib``, which covers running from a Khostty checkout and from
   an editable install.
4. ``ctypes.util.find_library("ghostty-vt")`` -- the system loader path.
5. Plain library names on the loader path.

If none succeed, :class:`LibraryNotFoundError` lists every location tried and
the environment variables that override the search.
"""

from __future__ import annotations

import ctypes.util
import os
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from ._cdef import CDEF, STRUCT_SIZES

__all__ = [
    "CDEF",
    "LIBRARY_DIR_ENV",
    "LIBRARY_ENV",
    "STRUCT_SIZES",
    "LibraryNotFoundError",
    "ffi",
    "library",
    "library_path",
    "load",
    "reset",
    "type_manifest",
    "validate_struct_sizes",
]

#: Environment variable holding a full path to the shared library.
LIBRARY_ENV = "KHOSTTY_VT_LIB"

#: Environment variable holding the directory that contains it.
LIBRARY_DIR_ENV = "KHOSTTY_VT_LIB_DIR"


# Platform library file names, most specific first.
_LIBRARY_NAMES = (
    "libghostty-vt.dylib",
    "libghostty-vt.so",
    "libghostty-vt.0.dylib",
    "libghostty-vt.0.so",
)


class LibraryNotFoundError(OSError):
    """Raised when no usable libghostty-vt shared library can be found."""

    def __init__(self, searched: List[str], detail: str = "") -> None:
        self.searched = searched
        lines = [
            "could not locate libghostty-vt.",
            "Build it with:  zig build install -Doptimize=ReleaseFast",
            "Then either set an environment variable:",
            f"    export {LIBRARY_ENV}=/path/to/libghostty-vt.dylib",
            f"    export {LIBRARY_DIR_ENV}=/path/to/lib",
            "or point it at one of the locations searched:",
        ]
        lines.extend(f"    {path}" for path in searched)
        if detail:
            lines.append(f"last error: {detail}")
        super().__init__("\n".join(lines))


def _candidate_paths() -> List[str]:
    """Return every location that will be tried, in order, as strings."""
    candidates: List[str] = []

    explicit = os.environ.get(LIBRARY_ENV)
    if explicit:
        candidates.append(explicit)

    directory = os.environ.get(LIBRARY_DIR_ENV)
    if directory:
        candidates.extend(str(Path(directory) / name) for name in _LIBRARY_NAMES)

    package_dir = Path(__file__).resolve().parent
    for relative in (
        Path("..") / ".." / "zig-out" / "lib",
        Path("..") / "zig-out" / "lib",
        Path("..") / ".." / "build" / "lib",
        Path("..") / ".." / "dist" / "lib",
    ):
        base = (package_dir / relative).resolve()
        candidates.extend(str(base / name) for name in _LIBRARY_NAMES)

    candidates.extend(_LIBRARY_NAMES)
    return candidates


def library_path() -> str:
    """Find the shared library and return its path.

    The result is not cached: discovery is cheap and callers sometimes point
    the environment variables at a different build between calls inside one
    process (tests do this).

    Raises:
        LibraryNotFoundError: if no candidate opens.
    """
    cffi = _import_cffi()
    ffi = cffi.FFI()

    searched = _candidate_paths()
    last_error = ""

    found = ctypes.util.find_library("ghostty-vt")
    if found:
        searched.append(f"{found} (from ctypes.util.find_library)")

    for candidate in searched:
        # A bare name is resolved by the loader itself, so dlopen is the only
        # meaningful test. A path is worth a cheap existence check first, so
        # the reported error mentions real attempts.
        if os.sep in candidate and not Path(candidate).exists():
            continue
        try:
            ffi.dlopen(candidate)
        except OSError as exc:
            last_error = str(exc)
            continue
        return candidate

    raise LibraryNotFoundError(searched, last_error)


def _import_cffi() -> Any:
    try:
        import cffi
    except ImportError as exc:  # pragma: no cover - depends on the environment
        raise ImportError(
            "khostty_vt needs the 'cffi' package. Install it with:\n"
            "    pip install cffi\n"
            "or install the bindings with their dependencies:\n"
            "    pip install khostty-vt"
        ) from exc
    return cffi


# Cached (ffi, lib) pair. Discovery happens on first use so that importing the
# package never requires the library to be present or built.
_cache: Optional[Tuple[Any, Any]] = None
_cache_path: Optional[str] = None


def load(path: Optional[str] = None, *, force: bool = False) -> Tuple[Any, Any]:
    """Open the library and return ``(ffi, lib)``.

    Args:
        path: Explicit shared-object path. When omitted, discovery runs.
        force: Re-open even if a library is already cached. Useful after
            changing the environment variables.

    Returns:
        The ``cffi.FFI`` instance holding the declarations, and the opened
        library object whose attributes are the C functions.
    """
    global _cache, _cache_path

    resolved = path or library_path()
    if _cache is not None and not force and _cache_path == resolved:
        return _cache

    cffi = _import_cffi()
    ffi = cffi.FFI()
    ffi.cdef(CDEF)

    lib = ffi.dlopen(resolved)
    _cache = (ffi, lib)
    _cache_path = resolved
    return _cache


def library() -> Any:
    """Return just the opened library."""
    return load()[1]


def ffi() -> Any:
    """Return just the ``cffi.FFI`` instance holding the declarations."""
    return load()[0]


def reset() -> None:
    """Drop the cached library handle, closing it on the next load."""
    global _cache, _cache_path
    _cache = None
    _cache_path = None


def type_manifest() -> Dict[str, Any]:
    """Return the library's decoded type manifest.

    The manifest is the library's own description of every public struct,
    enum, and union in the linked build. It is the authority used to check
    that the hand-written declarations in this module still match.
    """
    import json

    _, lib = load()
    return json.loads(ffi().string(lib.ghostty_type_json()).decode("utf-8"))


def validate_struct_sizes() -> Dict[str, Tuple[int, int]]:
    """Compare declared struct sizes against the library's manifest.

    Returns:
        A mapping of type name to ``(declared, library)`` for every type where
        the two disagree. An empty mapping means the declarations match.
    """
    manifest = type_manifest()
    types = manifest.get("types", {})
    mismatches: Dict[str, Tuple[int, int]] = {}

    f = ffi()
    for name, declared in STRUCT_SIZES.items():
        entry = types.get(name)
        if entry is None:
            continue
        actual = int(entry.get("size", -1))
        if actual != declared:
            mismatches[name] = (declared, actual)
        # Also ask cffi what it thinks, which catches a cdef typo that happens
        # to have the right total size for the wrong reasons.
        cffi_size = int(f.sizeof(name))
        if cffi_size != actual:
            mismatches[name] = (cffi_size, actual)
    return mismatches
