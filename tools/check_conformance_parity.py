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
    1  a divergence was found that the baseline does not list, one side lists
       the same case name twice, or a baseline entry no longer diverges (the
       lists were reconciled and the baseline must shrink with them)
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
# `{ "name",` and a name on its own line after `{` are both valid C initialisers;
# requiring `{"` exactly would silently miss a new case written the other way
# while the zero-name guard stayed satisfied by the cases already there.
C_NAME_RE = re.compile(r'^\s*\{\s*"([^"]+)"\s*,', re.MULTILINE)
ZIG_NAME_RE = re.compile(r'\.name\s*=\s*"([^"]+)"')


def strip_comments(source: str) -> str:
    """Blank out C and Zig comments, preserving string and char literals.

    A commented-out case is not a case. Wrapping `sgr_bold`'s initializer in
    `/* ... */` stops the C harness running it, but the text is still there, and
    extracting names from raw source would keep reporting parity. Newlines inside
    a block comment are preserved so the line-anchored C pattern still matches.
    """
    out: list[str] = []
    i, n = 0, len(source)
    while i < n:
        ch = source[i]
        if ch in "\"'":
            out.append(ch)
            i += 1
            while i < n:
                if source[i] == "\\" and i + 1 < n:
                    out.append(source[i : i + 2])
                    i += 2
                    continue
                out.append(source[i])
                i += 1
                if source[i - 1] in (ch, "\n"):
                    break
            continue
        if source.startswith("//", i):
            while i < n and source[i] != "\n":
                i += 1
            continue
        if source.startswith("/*", i):
            end = source.find("*/", i + 2)
            end = n if end < 0 else end + 2
            out.extend("\n" * source.count("\n", i, end))
            i = end
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def c_cases() -> dict[str, list[str]]:
    """Case names per category, read from the C harness arrays."""
    source = strip_comments(HARNESS.read_text())
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
        cases[path.parent.name] = ZIG_NAME_RE.findall(strip_comments(path.read_text()))
    return cases


def diff(
    zig: dict[str, list[str]], c: dict[str, list[str]]
) -> dict[str, dict[str, list[str]]]:
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


def report_duplicates(
    zig_dupes: dict[str, list[str]], c_dupes: dict[str, list[str]]
) -> None:
    print("\nduplicate case names (not baseline-able):", file=sys.stderr)
    for side, found in (("zig", zig_dupes), ("c", c_dupes)):
        for category, names in found.items():
            for name in names:
                print(f"  {category}: {side}: {name}", file=sys.stderr)


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

    # Before the baseline branch: a duplicate is never baseline-able, and writing
    # a baseline for a case list the normal gate rejects would report success for
    # something that cannot pass.
    if zig_dupes or c_dupes:
        report_duplicates(zig_dupes, c_dupes)
        return 1

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
        print(
            f"cases: zig={totals['zig']} c={totals['c']} categories={totals['categories']}"
        )
        for category, sides in found.items():
            print(
                f"  {category:10} zig_only={len(sides['zig_only']):2} "
                f"c_only={len(sides['c_only']):2}"
            )
        if reconciled:
            print(
                f"stale: {len(reconciled)} baseline entries no longer diverge "
                "(the lists were reconciled; the baseline must shrink)"
            )

    if new_drift:
        print("\nnew drift not in the baseline:", file=sys.stderr)
        for line in new_drift:
            print(f"  {line}", file=sys.stderr)
        print(
            "\nAdd the case to both sides, or record it deliberately with "
            "`--write-baseline` if the divergence is intended.",
            file=sys.stderr,
        )

    if reconciled:
        print(
            "\nbaseline entries that no longer diverge:",
            file=sys.stderr,
        )
        for line in reconciled:
            print(f"  {line}", file=sys.stderr)
        print(
            "\nThe lists were reconciled. Re-record the baseline with "
            "`--write-baseline` so it cannot later absorb that divergence again.",
            file=sys.stderr,
        )

    if new_drift or reconciled:
        return 1

    if not args.json:
        print("parity: no new drift")
    return 0


if __name__ == "__main__":
    sys.exit(main())
