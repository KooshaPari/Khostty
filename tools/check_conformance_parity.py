#!/usr/bin/env python3
"""Check that the Zig conformance case lists and the C harness agree.

The conformance suite exists twice: `conformance/cases/<category>/cases.zig`
carries the typed case data, and `conformance/harness.c` carries a parallel,
hand-maintained `static const TestCase <CATEGORY>_CASES[]` array per category.
Nothing links them, so they can drift without any test noticing: as of
2026-11-12 the Zig side has 91 cases and the C side 84, with 16 names only in
Zig and 9 only in C.

This gate makes drift visible. It is baseline-aware rather than strict, because
the divergence that already exists is a known, documented quantity: new drift
fails the build, existing drift is listed in
`conformance/case-parity-baseline.json` and shrinks as the lists are reconciled.

Exit codes:
    0  every divergence found is in the baseline
    1  a divergence was found that the baseline does not list, or one side
       lists the same case name twice
    2  the parser found no case *names* on one side (a broken parser, not a
       clean run)
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
HARNESS = REPO_ROOT / "conformance" / "harness.c"
CASES_DIR = REPO_ROOT / "conformance" / "cases"
BASELINE = REPO_ROOT / "conformance" / "case-parity-baseline.json"

# `KITTY_CASES` in C corresponds to `conformance/cases/kitty-gfx/`. Every other
# category maps by lowercasing and turning `_` into `-`.
CATEGORY_ALIASES = {"kitty": "kitty-gfx"}

C_BLOCK_RE = re.compile(r"static const TestCase ([A-Z0-9_]+)_CASES\[\]\s*=\s*\{")
C_NAME_RE = re.compile(r'^\s*\{"([^"]+)",', re.MULTILINE)
ZIG_NAME_RE = re.compile(r'\.name\s*=\s*"([^"]+)"')


def c_cases() -> dict[str, list[str]]:
    """Case names per category, read from the C harness arrays."""
    source = HARNESS.read_text()
    blocks = C_BLOCK_RE.split(source)
    cases: dict[str, list[str]] = {}
    # split() with one capture group yields [preamble, cat, body, cat, body, ...]
    for i in range(1, len(blocks), 2):
        raw = blocks[i].lower()
        category = CATEGORY_ALIASES.get(raw, raw.replace("_", "-"))
        cases[category] = C_NAME_RE.findall(blocks[i + 1])
    return cases


def zig_cases() -> dict[str, list[str]]:
    """Case names per category, read from the Zig case files."""
    cases: dict[str, list[str]] = {}
    for path in sorted(CASES_DIR.glob("*/cases.zig")):
        cases[path.parent.name] = ZIG_NAME_RE.findall(path.read_text())
    return cases


def diff(zig: dict[str, list[str]], c: dict[str, list[str]]) -> dict[str, dict[str, list[str]]]:
    """Per-category name divergence between the two sides."""
    out: dict[str, dict[str, list[str]]] = {}
    for category in sorted(set(zig) | set(c)):
        zig_names, c_names = set(zig.get(category, [])), set(c.get(category, []))
        zig_only = sorted(zig_names - c_names)
        c_only = sorted(c_names - zig_names)
        if zig_only or c_only:
            out[category] = {"zig_only": zig_only, "c_only": c_only}
    return out


def duplicates(cases: dict[str, list[str]]) -> dict[str, list[str]]:
    """Case names that appear more than once in one category.

    A duplicate is always a defect: the runner executes the case twice under one
    name, and the set-based parity comparison cannot see it, because the name is
    present on the other side exactly once.
    """
    out: dict[str, list[str]] = {}
    for category, names in sorted(cases.items()):
        seen: set[str] = set()
        repeated: set[str] = set()
        for name in names:
            if name in seen:
                repeated.add(name)
            seen.add(name)
        if repeated:
            out[category] = sorted(repeated)
    return out


def load_baseline() -> dict[str, dict[str, list[str]]]:
    if not BASELINE.exists():
        return {}
    return json.loads(BASELINE.read_text()).get("known_divergence", {})


def unbaselined(found: dict[str, dict[str, list[str]]], baseline: dict) -> list[str]:
    """Divergences present now but absent from the baseline, as readable lines."""
    problems: list[str] = []
    for category, sides in found.items():
        known = baseline.get(category, {})
        for side in ("zig_only", "c_only"):
            new = sorted(set(sides.get(side, [])) - set(known.get(side, [])))
            problems.extend(f"{category}: {side}: {name}" for name in new)
    return problems


def stale_baseline(found: dict[str, dict[str, list[str]]], baseline: dict) -> list[str]:
    """Baseline entries that no longer diverge: the lists were reconciled."""
    stale: list[str] = []
    for category, sides in baseline.items():
        current = found.get(category, {})
        for side in ("zig_only", "c_only"):
            gone = sorted(set(sides.get(side, [])) - set(current.get(side, [])))
            stale.extend(f"{category}: {side}: {name}" for name in gone)
    return stale


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--write-baseline",
        action="store_true",
        help="rewrite the baseline from the current divergence (do not use in CI)",
    )
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    args = parser.parse_args()

    zig, c = zig_cases(), c_cases()
    # Guard on names parsed, not on the category maps: a parser that reads every
    # file but extracts nothing still produces a non-empty map, and treating that
    # as a clean run is exactly the "zero without a positive control" error this
    # audit already made once.
    zig_total = sum(map(len, zig.values()))
    c_total = sum(map(len, c.values()))
    if zig_total == 0 or c_total == 0:
        print(
            f"error: parsed zero cases on one side (zig={zig_total} c={c_total}); "
            "this is a parser fault, not a clean run",
            file=sys.stderr,
        )
        return 2

    found = diff(zig, c)
    zig_dupes, c_dupes = duplicates(zig), duplicates(c)

    if args.write_baseline:
        payload = {
            "note": (
                "Known divergence between the Zig case lists and the C harness arrays. "
                "Shrink this file as the lists are reconciled; the parity gate fails on "
                "any divergence that is not listed here."
            ),
            "zig_total": zig_total,
            "c_total": c_total,
            "known_divergence": found,
        }
        BASELINE.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
        print(f"wrote {BASELINE.relative_to(REPO_ROOT)}")
        return 0

    baseline = load_baseline()
    new_drift = unbaselined(found, baseline)
    reconciled = stale_baseline(found, baseline)
    totals = {
        "zig": zig_total,
        "c": c_total,
        "categories": len(set(zig) | set(c)),
    }

    if args.json:
        print(
            json.dumps(
                {
                    "totals": totals,
                    "divergence": found,
                    "duplicate_names": {"zig": zig_dupes, "c": c_dupes},
                    "new_drift": new_drift,
                    "reconciled_baseline_entries": reconciled,
                },
                indent=2,
                sort_keys=True,
            )
        )
    else:
        print(f"cases: zig={totals['zig']} c={totals['c']} categories={totals['categories']}")
        for category, sides in found.items():
            print(
                f"  {category:10} zig_only={len(sides['zig_only']):2} "
                f"c_only={len(sides['c_only']):2}"
            )
        if reconciled:
            print(
                f"note: {len(reconciled)} baseline entries no longer diverge "
                "(the lists were reconciled; shrink the baseline)"
            )

    if zig_dupes or c_dupes:
        print("\nduplicate case names (not baseline-able):", file=sys.stderr)
        for side, found_dupes in (("zig", zig_dupes), ("c", c_dupes)):
            for category, names in found_dupes.items():
                for name in names:
                    print(f"  {category}: {side}: {name}", file=sys.stderr)
        return 1

    if new_drift:
        print("\nnew drift not in the baseline:", file=sys.stderr)
        for line in new_drift:
            print(f"  {line}", file=sys.stderr)
        print(
            "\nAdd the case to both sides, or record it deliberately with "
            "`--write-baseline` if the divergence is intended.",
            file=sys.stderr,
        )
        return 1

    print("parity: no new drift")
    return 0


if __name__ == "__main__":
    sys.exit(main())
