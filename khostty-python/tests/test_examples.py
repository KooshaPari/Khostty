"""Smoke tests that run the shipped examples end to end.

The examples are the documentation for the package, so they are executed rather
than only linted. Each runs in a subprocess, which also proves the checkout
bootstrap in them works without an install.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

EXAMPLES = Path(__file__).resolve().parent.parent / "examples"


def run_example(name: str) -> str:
    """Run one example and return its stdout."""
    result = subprocess.run(
        [sys.executable, str(EXAMPLES / name)],
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    assert result.returncode == 0, (
        f"{name} exited {result.returncode}\n--- stdout ---\n{result.stdout}\n"
        f"--- stderr ---\n{result.stderr}"
    )
    return result.stdout


@pytest.mark.parametrize("name", ["basic.py", "agent.py"])
def test_examples_exist(name: str) -> None:
    assert (EXAMPLES / name).is_file()


def test_basic_example_runs(library: str) -> None:
    out = run_example("basic.py")

    assert "screen" in out
    assert "restored screen identical: True" in out
    assert "cannot find symbol" in out


def test_agent_example_runs(library: str) -> None:
    out = run_example("agent.py")

    assert "at-prompt" in out
    assert "matches for 'FAIL'" in out
    assert "resumed session renders identically: True" in out
    assert "transcript still readable after reflow: True" in out

    # The input half: encoding keystrokes and pointer events back to the pane.
    assert "key: encoder emitted b'a' for 'a'" in out
    assert "Ctrl+C encodes to b'\\x03'" in out
    assert "encoded b'\\x1b[<0;6;3M'" in out
