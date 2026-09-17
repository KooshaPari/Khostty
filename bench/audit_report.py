#!/usr/bin/env python3
"""Audit the numeric tables in bench/results/README.md against the JSON files.

Maps each README table row to the metric name in the JSON and compares all four
run columns. Any mismatch, or any row that cannot be mapped, is reported. This
exists because a hand-written report is exactly where a unit conversion goes
wrong.
"""
import json
import re
import sys

RUNS = ["khostty", "khostty-run2", "upstream", "upstream-run2"]

# README row label -> (section, metric name, scale applied to JSON value)
MAP = {
    # 8.2
    "plain_text bounded": ("vt_throughput", "vt_plain_text_bounded_mib_per_sec", 1),
    "plain_text unbounded": ("vt_throughput", "vt_plain_text_unbounded_mib_per_sec", 1),
    "escape_heavy bounded": ("vt_throughput", "vt_escape_heavy_bounded_mib_per_sec", 1),
    "escape_heavy unbounded": ("vt_throughput", "vt_escape_heavy_unbounded_mib_per_sec", 1),
    "osc_title bounded": ("vt_throughput", "vt_osc_title_bounded_mib_per_sec", 1),
    # 8.3
    "80x24 snapshot size": ("snapshot", "snapshot_80x24_2k_lines_bytes", 1),
    "80x24 encode median": ("snapshot", "snapshot_80x24_2k_lines_encode_median_ms", 1),
    "80x24 decode median": ("snapshot", "snapshot_80x24_2k_lines_decode_median_ms", 1),
    "80x24 round trip": ("snapshot", "snapshot_80x24_2k_lines_roundtrip_median_ms", 1),
    "200x50 snapshot size": ("snapshot", "snapshot_200x50_2k_lines_bytes", 1),
    "200x50 encode median": ("snapshot", "snapshot_200x50_2k_lines_encode_median_ms", 1),
    "200x50 decode median": ("snapshot", "snapshot_200x50_2k_lines_decode_median_ms", 1),
    "200x50 round trip": ("snapshot", "snapshot_200x50_2k_lines_roundtrip_median_ms", 1),
    # 8.4
    "cold (fresh search, fresh needle), frequent needle": ("search", "search_frequent_error_cold_median_ms", 1),
    "cold p95": ("search", "search_frequent_error_cold_p95_ms", 1),
    "rescan (same search, changed needle)": ("search", "search_frequent_error_rescan_median_ms", 1),
    "warm (same needle, results retained)": ("search", "search_frequent_error_warm_median_ms", 1),
    "cold, absent needle (worst case)": ("search", "search_absent_needle_cold_median_ms", 1),
    "cold, 2,000 records": ("search", "search_scaling_2000_records_cold_ms", 1),
    "cold, 10,000 records": ("search", "search_scaling_10000_records_cold_ms", 1),
    "cost per retained row": ("search", "search_frequent_error_us_per_row", 1),
    # 8.5
    "80x24 allocator after create": ("memory", "memory_80x24_library_create_bytes", 1),
    "80x24 allocator at 10k records": ("memory", "memory_80x24_library_bytes_10k_records", 1),
    "80x24 allocator bytes per row": ("memory", "memory_80x24_library_bytes_per_row", 1),
    "80x24 allocator residual after free": ("memory", "memory_80x24_library_residual_bytes", 1),
    "80x24 anonymous delta": ("memory", "memory_80x24_internal_delta_bytes", 1 / 1024),  # KiB
    "80x24 rss delta": ("memory", "memory_80x24_rss_delta_bytes", 1 / 1024),
    "200x50 allocator at 10k records": ("memory", "memory_200x50_library_bytes_10k_records", 1),
    "200x50 allocator bytes per row": ("memory", "memory_200x50_library_bytes_per_row", 1),
    "200x50 anonymous delta": ("memory", "memory_200x50_internal_delta_bytes", 1 / 1024),
    # 8.6
    "200x50 empty, width only": ("resize", "resize_200x50_empty_width_median_ms", 1),
    "200x50 empty, size": ("resize", "resize_200x50_empty_size_median_ms", 1),
    "200x50 + 2k lines, width only": ("resize", "resize_200x50_2k_lines_width_median_ms", 1),
    "200x50 + 2k lines, size": ("resize", "resize_200x50_2k_lines_size_median_ms", 1),
    "200x50 + 10k lines, size": ("resize", "resize_200x50_10k_lines_size_median_ms", 1),
    "200x50 + 10k lines, p95": ("resize", "resize_200x50_10k_lines_size_p95_ms", 1),
    "80x24 + 10k lines, size": ("resize", "resize_80x24_10k_lines_size_median_ms", 1),
}


def main() -> int:
    text = open("bench/results/README.md").read()
    runs = {}
    for label in RUNS:
        data = json.load(open(f"bench/results/{label}-20260917.json"))
        runs[label] = {(m["section"], m["name"]): m["value"] for m in data["metrics"]}

    rows = 0
    problems = 0
    unmapped = []
    for line in text.splitlines():
        if not line.startswith("|") or line.startswith("|---") or "---|" in line:
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) != 5:
            continue
        label = cells[0]
        key = MAP.get(label)
        if key is None:
            unmapped.append(label)
            continue
        section, metric, scale = key
        rows += 1
        for i, run in enumerate(RUNS):
            raw = runs[run].get((section, metric))
            expected = None if raw is None else raw * scale
            cell = cells[i + 1]
            if expected is None:
                if cell != "n/a":
                    print(f"MISMATCH {label} [{run}]: json n/a, readme {cell}")
                    problems += 1
                continue
            numbers = re.findall(r"[-+]?[\d,]+(?:\.\d+)?", cell)
            if not numbers:
                print(f"MISMATCH {label} [{run}]: no number in {cell!r}")
                problems += 1
                continue
            claimed = float(numbers[0].replace(",", ""))
            # Compare on the first significant-figure band used in the report.
            tol = max(abs(expected) * 0.006, 0.0005)
            if abs(claimed - expected) > tol:
                print(
                    f"MISMATCH {label} [{run}]: readme {claimed} vs json {expected:.6g} "
                    f"(tol {tol:.4g})"
                )
                problems += 1

    print(f"\nchecked {rows} mapped table rows across {len(RUNS)} runs")
    if unmapped:
        print("unmapped rows (verify manually):")
        for label in unmapped:
            print(f"  - {label}")
    print("RESULT:", "FAIL" if problems else "PASS")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
