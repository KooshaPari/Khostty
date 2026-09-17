#!/usr/bin/env python3
"""Agent-oriented example: drive a terminal and read its state as data.

This is the workflow the bindings exist for. Instead of scraping a rendered
screen, an agent asks the terminal structured questions: what is on screen,
where is the cursor, is the program waiting at a prompt, where are the
failures, and can this session be resumed later.

Run from ``khostty-python`` after building the library::

    zig build install -Doptimize=ReleaseFast   # from the repo root
    python examples/agent.py
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Iterable

# Allow running straight from a checkout, before `pip install -e .` has been
# run. After installing, this is a no-op because the package resolves normally.
_ROOT = Path(__file__).resolve().parent.parent
if (_ROOT / "khostty_vt").is_dir() and str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from khostty_vt import Format, Screen, SearchScroll, Terminal, TerminalOption, restore

TEST_OUTPUT = [
    "$ make test\r\n",
    "ok   github.com/example/a\t0.021s\r\n",
    "ok   github.com/example/b\t0.114s\r\n",
    "--- FAIL: TestWidgetRender (0.03s)\r\n",
    "    widget_test.go:41: got 3 widgets, want 4\r\n",
    "FAIL\tgithub.com/example/c\t0.412s\r\n",
]


def feed(term: Terminal, chunks: Iterable[str]) -> None:
    """Feed output, then a fresh prompt."""
    for chunk in chunks:
        term.write(chunk)
    term.write("$ ")


def report_prompt(term: Terminal) -> None:
    """Report what the agent knows about whether the program is waiting."""
    # OSC 133 prompt marks are what make cursor_at_prompt meaningful; without
    # them the cursor position is the fallback signal.
    before = term.cursor_at_prompt
    term.write("\x1b]133;A\x07")
    after = term.cursor_at_prompt

    print(
        f"cursor at {term.cursor_position}, at-prompt={before} "
        f"(after an OSC 133 mark: {after}), vt_ground={term.vt_ground}"
    )


def report_failures(term: Terminal, needle: str = "FAIL") -> None:
    """Walk the matches, keeping the viewport where it is."""
    with term.search(needle) as found:
        found.set_scroll_policy(SearchScroll.NONE)
        found.run()
        total, viewport = found.counts()
        print(f"{total} matches for {needle!r} ({viewport} on the viewport)")
        if not total:
            return

        for step in range(total):
            index = found.select_next()
            print(f"  match {step + 1} of {total} selected (index {index}, 0 is newest)")
        print(f"  stepping back selects index {found.select_prev()}")


def report_context(term: Terminal) -> None:
    """Read screen-level facts an agent would branch on."""
    print(
        f"screen={term.active_screen.name.lower()} "
        f"scrollback_rows={term.scrollback_rows} "
        f"total_rows={term.total_rows} "
        f"mouse_tracking={term.mouse_tracking}"
    )


def report_render(term: Terminal) -> None:
    """Show that the same state renders three ways."""
    plain = term.text()
    vt = term.formatter(format=Format.VT, trim=True).format()
    html = term.formatter(format=Format.HTML, trim=True).text()

    print(f"renderings: plain={len(plain)}B vt={len(vt)}B html={len(html)}B")
    print(f"  transcript still readable after reflow: {'TestWidgetRender' in plain}")


def report_resume(term: Terminal) -> bytes:
    """Snapshot the session so another process could resume it."""
    snapshot = term.snapshot()
    print(
        f"snapshot: {len(snapshot)} bytes, size query agrees: "
        f"{term.snapshot_size() == len(snapshot)}"
    )
    return snapshot


def resize_pane(term: Terminal, cols: int, rows: int) -> None:
    """Resize as a layout change would, with placeholder cell metrics."""
    term.resize(cols, rows, 8, 16)
    print(f"resized to {term.cols}x{term.rows} cells ({term.size_px[0]}x{term.size_px[1]} px)")


def main() -> None:
    with Terminal(cols=80, rows=24) as pane:
        # Keep a scrollback budget the agent can reason about instead of
        # inheriting the library default.
        pane.set_option(TerminalOption.SCROLLBACK_MAX_LINES, 5000)

        feed(pane, TEST_OUTPUT)
        report_prompt(pane)
        report_context(pane)
        report_failures(pane)
        report_render(pane)
        snapshot = report_resume(pane)
        resize_pane(pane, 120, 40)
        assert pane.active_screen == Screen.PRIMARY

        transcript = pane.text()

    with restore(snapshot) as resumed:
        print(
            f"resumed session renders identically: {resumed.text() == transcript}, "
            f"cursor {resumed.cursor_position}"
        )


if __name__ == "__main__":
    main()
