"""Tests for the cffi boundary: discovery, declarations, and error mapping.

These are the tests that catch a bindings/library mismatch, which is otherwise
only visible as wrong values or a crash deep inside a wrapper.
"""

from __future__ import annotations

import os

import pytest

import khostty_vt
from khostty_vt import _cdef, _ffi, errors
from khostty_vt.constants import Result, TerminalData, TerminalOption
from khostty_vt.errors import GhosttyError, check


def test_library_is_found(library: str) -> None:
    assert os.path.exists(library) or "/" not in library


def test_manifest_is_schema_1(library: str) -> None:
    manifest = khostty_vt.type_manifest()

    assert manifest["schema"] == 1
    assert manifest["library_version"]
    assert manifest["types"], "manifest declares no types"
    assert manifest["abi"]["pointer_size"] in (4, 8)


def test_struct_sizes_match_the_library(library: str) -> None:
    """The hand-written layouts must match the library's own view of them.

    ABI-mode cffi compiles nothing, so nothing else checks this. A mismatch
    here is what would otherwise show up as misread formatter options.
    """
    assert khostty_vt.validate_struct_sizes() == {}


def test_enum_values_match_the_library(library: str) -> None:
    """Every declared member must exist with the same value, in both directions."""
    assert khostty_vt.validate_enum_values() == {}


def test_validate_abi_reports_ok(library: str) -> None:
    report = khostty_vt.validate_abi()

    assert report["ok"] is True
    assert report["struct_sizes"] == {}
    assert report["enum_values"] == {}
    assert report["library_version"]


def test_declared_struct_sizes_cover_the_declared_types(library: str) -> None:
    """Every entry in STRUCT_SIZES must be a type the cdef actually declares."""
    ffi = khostty_vt.load()[0]
    for name in _cdef.STRUCT_SIZES:
        # Raises if the type is absent from the cdef.
        assert ffi.sizeof(name) > 0


def test_type_manifest_is_cached_but_reparseable(library: str) -> None:
    first = khostty_vt.type_manifest()
    second = khostty_vt.type_manifest()

    assert first["library_version"] == second["library_version"]
    assert len(first["types"]) == len(second["types"])


def test_load_returns_the_same_handle(library: str) -> None:
    ffi_a, lib_a = khostty_vt.load()
    ffi_b, lib_b = khostty_vt.load()

    assert ffi_a is ffi_b
    assert lib_a is lib_b
    assert khostty_vt.load(force=True)[1] is not None


def test_import_does_not_require_the_library() -> None:
    """Loading is lazy, so importing the package is always safe.

    That is what lets a caller check `import khostty_vt` on a machine with no
    build while still getting a clear error at the first real use.
    """
    khostty_vt.reset()
    assert khostty_vt.load  # the lazy entry point exists without being called
    assert khostty_vt.__version__


def test_library_not_found_error_is_explanatory(monkeypatch: pytest.MonkeyPatch) -> None:
    """A bad KHOSTTY_VT_LIB must produce a message naming the fixes.

    The candidate list is replaced as well as the environment, so the real
    in-tree library cannot satisfy the search and mask the error path.
    """
    monkeypatch.setenv(khostty_vt.LIBRARY_ENV, "/nonexistent/libghostty-vt.dylib")
    monkeypatch.setenv(khostty_vt.LIBRARY_DIR_ENV, "/nonexistent")
    monkeypatch.setattr(_ffi.ctypes.util, "find_library", lambda name: None)
    # Only an absolute, non-existent path: a bare library name would still
    # resolve through the already-loaded image and mask the error path.
    monkeypatch.setattr(_ffi, "_candidate_paths", lambda: ["/nonexistent/libghostty-vt.dylib"])

    try:
        with pytest.raises(khostty_vt.LibraryNotFoundError) as excinfo:
            khostty_vt.library_path()
    finally:
        # Other tests need the real library back.
        khostty_vt.reset()

    message = str(excinfo.value)
    assert "libghostty-vt" in message
    assert khostty_vt.LIBRARY_ENV in message
    assert "zig build install" in message


def test_explicit_library_path_is_honoured(library: str) -> None:
    ffi, lib = khostty_vt.load(library)

    assert ffi.sizeof("GhosttyString") == 16
    assert lib is not None


def test_result_names_cover_every_declared_code() -> None:
    for member in Result:
        assert member.name in errors.RESULT_NAMES.values()


def test_check_raises_with_the_symbolic_name() -> None:
    with pytest.raises(GhosttyError) as excinfo:
        check(int(Result.NO_VALUE), "reading something")

    error = excinfo.value
    assert error.code == int(Result.NO_VALUE)
    assert error.name == "NO_VALUE"
    assert "reading something" in str(error)
    assert "[NO_VALUE]" in str(error)


def test_check_passes_through_success() -> None:
    assert check(int(Result.SUCCESS)) is None


def test_unknown_result_code_is_reported_verbatim() -> None:
    with pytest.raises(GhosttyError) as excinfo:
        check(-99)

    assert excinfo.value.code == -99
    assert "UNKNOWN" in excinfo.value.name


def test_data_enum_matches_the_manifest(library: str) -> None:
    """Spot-check the values the wrappers depend on most."""
    types = khostty_vt.type_manifest()["types"]
    values = types["GhosttyTerminalData"]["values"]

    assert values["COLS"] == int(TerminalData.COLS)
    assert values["ROWS"] == int(TerminalData.ROWS)
    assert values["TITLE"] == int(TerminalData.TITLE)
    assert values["VT_GROUND"] == int(TerminalData.VT_GROUND)
    assert types["GhosttyTerminalOption"]["values"]["SCROLLBACK_MAX_LINES"] == int(
        TerminalOption.SCROLLBACK_MAX_LINES
    )
