#!/usr/bin/env python3
"""Summarize Khostty benchmark result files into a comparison table.

Reads one or more results/*.json files produced by bench/run.sh and prints the
headline metrics side by side, so a reader can reproduce the table in
results/README.md from the raw JSON rather than trusting the prose.

Usage:
    python3 bench/summarize.py bench/results/*.json
    python3 bench/summarize.py bench/results/khostty-20260917.json \
                              bench/results/upstream-20260917.json

No third-party dependencies. Percent-delta columns are only printed when
exactly two files are given, and are computed as (second - first) / first.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

# (label, section, metric name, unit shown in the table)
ROWS: list[tuple[str, str, str, str]] = [
    ("load avg (1m)", "notes", "load_average_at_start", "text"),
    ("harness pid", "notes", "harness_pid", "text"),
    ("library version", "notes", "library_version", "text"),
    ("optimize", "notes", "library_optimize", "text"),
    ("memory 80x24 allocator", "memory", "memory_80x24_library_bytes_10k_records", "B"),
    ("memory 80x24 anonymous", "memory", "memory_80x24_internal_delta_bytes", "KiB"),
    ("memory 200x50 allocator", "memory", "memory_200x50_library_bytes_10k_records", "B"),
    ("memory 200x50 anonymous", "memory", "memory_200x50_internal_delta_bytes", "KiB"),
    ("vt plain bounded", "vt_throughput", "vt_plain_text_bounded_mib_per_sec", "MiB/s"),
    ("vt plain unbounded", "vt_throughput", "vt_plain_text_unbounded_mib_per_sec", "MiB/s"),
    ("vt escape bounded", "vt_throughput", "vt_escape_heavy_bounded_mib_per_sec", "MiB/s"),
    ("vt escape unbounded", "vt_throughput", "vt_escape_heavy_unbounded_mib_per_sec", "MiB/s"),
    ("vt osc bounded", "vt_throughput", "vt_osc_title_bounded_mib_per_sec", "MiB/s"),
    ("snapshot 80x24 encode", "snapshot", "snapshot_80x24_2k_lines_encode_median_ms", "ms"),
    ("snapshot 80x24 decode", "snapshot", "snapshot_80x24_2k_lines_decode_median_ms", "ms"),
    ("snapshot 200x50 encode", "snapshot", "snapshot_200x50_2k_lines_encode_median_ms", "ms"),
    ("snapshot 200x50 decode", "snapshot", "snapshot_200x50_2k_lines_decode_median_ms", "ms"),
    ("search frequent cold", "search", "search_frequent_error_cold_median_ms", "ms"),
    ("search frequent warm", "search", "search_frequent_error_warm_median_ms", "ms"),
    ("search absent cold", "search", "search_absent_needle_cold_median_ms", "ms"),
    ("search 10k scaling", "search", "search_scaling_10000_records_cold_ms", "ms"),
    ("resize empty width", "resize", "resize_200x50_empty_width_median_ms", "ms"),
    ("resize 2k width", "resize", "resize_200x50_2k_lines_width_median_ms", "ms"),
    ("resize 10k size", "resize", "resize_200x50_10k_lines_size_median_ms", "ms"),
    ("resize 80x24 10k size", "resize", "resize_80x24_10k_lines_size_median_ms", "ms"),
]


def load(path: Path) -> dict:
    with path.open() as handle:
        return json.load(handle)


def index(data: dict) -> dict[tuple[str, str], float | str]:
    table: dict[tuple[str, str], float | str] = {}
    for metric in data.get("metrics", []):
        table[(metric["section"], metric["name"])] = metric["value"]
    return table


def fmt(value, unit: str) -> str:
    if value is None:
        return "n/a"
    if unit == "text":
        return str(value)
    if unit == "KiB":
        return f"{value / 1024.0:,.1f}"
    if unit == "B":
        return f"{value:,.0f}"
    if value >= 1000:
        return f"{value:,.0f}"
    if value >= 10:
        return f"{value:,.1f}"
    return f"{value:,.3f}"


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 2

    paths = [Path(p) for p in argv[1:]]
    runs = [(p.stem, load(p)) for p in paths]

    notes = []
    for name, data in runs:
        note_map = data.get("notes", {})
        machine = data.get("machine", {})
        load_text = note_map.get("load_average_at_start", "unknown")
        notes.append(
            {
                "run": name,
                "library": data.get("library", "unknown"),
                "version": note_map.get("library_version", "unknown"),
                "optimize": note_map.get("library_optimize", "unknown"),
                "git_head": note_map.get("git_head", "unknown"),
                "date": note_map.get("date_local", "unknown"),
                "load": load_text.split(" ")[0] if load_text else "unknown",
                "chip": machine.get("chip", "unknown"),
            }
        )

    for n in notes:
        print(f"{n['run']}: {n['chip']} | {n['library']}")
        print(f"{'':>{len(n['run'])}}  version={n['version']} optimize={n['optimize']}")
        print(f"{'':>{len(n['run'])}}  git={n['git_head'][:12]} date={n['date']} load1m={n['load']}")
    print()

    indexed = [(name, index(data), data.get("notes", {})) for name, data in runs]

    width = max(len(label) for label, _, _, _ in ROWS) + 2
    header = "metric".ljust(width) + "unit".ljust(9)
    for name, _, _ in indexed:
        header += name.rjust(max(len(name) + 2, 14))
    if len(indexed) == 2:
        header += "delta".rjust(12)
    print(header)
    print("-" * len(header))

    for label, section, metric, unit in ROWS:
        row = label.ljust(width) + unit.ljust(9)
        values = []
        for _, table, note_map in indexed:
            if section == "notes":
                raw = note_map.get(metric)
                if raw is None:
                    values.append(None)
                elif metric == "load_average_at_start":
                    values.append(raw.split(" ")[0])
                else:
                    values.append(raw)
            else:
                values.append(table.get((section, metric)))
        for value, (name, _, _) in zip(values, indexed):
            row += fmt(value, unit).rjust(max(len(name) + 2, 14))
        numeric = all(isinstance(value, (int, float)) for value in values)
        if len(indexed) == 2 and numeric and values[0]:
            pct = (values[1] - values[0]) / values[0] * 100.0
            row += f"{pct:+.1f}%".rjust(12)
        print(row)

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
