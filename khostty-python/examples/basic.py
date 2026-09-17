#!/usr/bin/env python3
"""Minimal libghostty-vt example through the Python bindings.

Create a terminal, feed it VT-encoded output, then read the screen back as
text, as VT, and as HTML; search it; and round-trip a snapshot.

Run from ``khostty-python`` after building the library::

    zig build install -Doptimize=ReleaseFast   # from the repo root
    python examples/basic.py

If the library is somewhere else, point the bindings at it::

    KHOSTTY_VT_LIB=/path/to/libghostty-vt.dylib python examples/basic.py
"""

from __future__ import annotations

import sys
from pathlib import Path

# Allow running straight from a checkout, before `pip install -e .` has been
# run. After installing, this is a no-op because the package resolves normally.
_ROOT = Path(__file__).resolve().parent.parent
if (_ROOT / "khostty_vt").is_dir() and str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from khostty_vt import Format, Terminal, restore

# ESC, hoisted out of the f-strings below: a backslash escape inside an
# f-string replacement field only parses on Python 3.12 and later.
ESC = b"\x1b"

# What a program would have written to its pty.
PROGRAM_OUTPUT = [
    "\x1b[1m$ build\x1b[0m\r\n",
    "compiling package a... ok\r\n",
    "compiling package b... ok\r\n",
    "\x1b[31merror\x1b[0m: cannot find symbol 'Widget'\r\n",
    "  --> src/app.rs:41:12\r\n",
    "build failed with 1 error\r\n",
    "$ \r\n",
]


def main() -> None:
    with Terminal(cols=80, rows=24) as term:
        # write() accepts str, bytes, or an iterable of either. A real pty
        # delivers bytes in arbitrary splits; the parser handles that.
        term.write(PROGRAM_OUTPUT)

        print(f"=== {term.cols}x{term.rows} screen, cursor at {term.cursor_position} ===")
        print(term.text())
        print("=== end screen ===")

        # The same content is available with styles preserved, and as HTML.
        vt = term.formatter(format=Format.VT, trim=True).format()
        print(f"VT rendering: {len(vt)} bytes, {vt.count(ESC)} escape sequences")

        html = term.formatter(format=Format.HTML, trim=True).text()
        print(f"HTML rendering: {len(html)} bytes, starts with {html[:40]!r}")

        # Search the screen and scrollback.
        with term.search("error") as found:
            found.run()
            total, viewport = found.counts()
            print(f"matches for 'error': {total} total, {viewport} on the viewport")
            for step in range(total):
                index = found.select_next()
                print(f"  match {step + 1} of {total} selected (index {index})")

        # Encoded snapshots are self-contained and can be stored or shipped.
        snapshot = term.snapshot()
        print(
            f"snapshot: {len(snapshot)} bytes (size query agrees: "
            f"{term.snapshot_size() == len(snapshot)})"
        )

        original = term.text()

    # The terminal is closed here; the snapshot outlives it.
    with restore(snapshot) as resumed:
        print(f"restored screen identical: {resumed.text() == original}")


if __name__ == "__main__":
    main()
