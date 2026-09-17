"""Shared fixtures for the khostty-vt test suite.

The bindings are only meaningful against a real ``libghostty-vt``. The
``library`` fixture therefore *fails* the suite when no library can be found,
rather than skipping: a green run against nothing would prove nothing. Set
``KHOSTTY_VT_SKIP_IF_MISSING=1`` to opt into skipping instead, which is useful
for a lint-only CI job.
"""

from __future__ import annotations

import os
from typing import Iterator

import pytest

import khostty_vt
from khostty_vt import Terminal

SKIP_ENV = "KHOSTTY_VT_SKIP_IF_MISSING"


@pytest.fixture(scope="session")
def library() -> str:
    """Path to the shared library under test."""
    try:
        return khostty_vt.library_path()
    except khostty_vt.LibraryNotFoundError as exc:
        if os.environ.get(SKIP_ENV) == "1":
            pytest.skip(f"libghostty-vt not built ({SKIP_ENV}=1): {exc}")
        raise AssertionError(
            "libghostty-vt was not found, so these tests cannot prove anything.\n"
            "Build it with `zig build install -Doptimize=ReleaseFast` from the repo root,\n"
            "or set KHOSTTY_VT_LIB / KHOSTTY_VT_LIB_DIR.\n\n"
            f"{exc}"
        ) from exc


@pytest.fixture
def terminal(library: str) -> Iterator[Terminal]:
    """A fresh 80x24 terminal, closed at the end of the test."""
    with Terminal(cols=80, rows=24, library=library) as term:
        yield term


@pytest.fixture
def make_terminal(library: str) -> Iterator[object]:
    """Factory for terminals with custom dimensions and content."""
    created: list[Terminal] = []

    def factory(cols: int = 80, rows: int = 24, content: str = "") -> Terminal:
        term = Terminal(cols=cols, rows=rows, library=library)
        created.append(term)
        if content:
            term.write(content)
        return term

    yield factory

    for term in created:
        term.close()


@pytest.fixture
def transcript() -> str:
    """A representative build transcript, as a pty would deliver it."""
    return "\r\n".join(
        [
            "$ make test",
            "compiling module A... ok",
            "compiling module B... error: missing semicolon",
            "linking... error: undefined symbol",
            "$ grep -n ERROR build.log",
            "",
        ]
    )
