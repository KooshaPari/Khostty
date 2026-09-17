#!/usr/bin/env python3
"""Print the headline metric matrix across the captured result files."""
import json
import sys

LABELS = ["khostty", "khostty-run2", "upstream", "upstream-run2"]
SECTIONS = {
    "memory": ["memory_80x24_library_create_bytes",
               "memory_80x24_library_bytes_10k_records",
               "memory_80x24_library_peak_bytes",
               "memory_80x24_library_bytes_per_row",
               "memory_80x24_library_residual_bytes",
               "memory_80x24_internal_delta_bytes",
               "memory_80x24_rss_delta_bytes",
               "memory_80x24_phys_footprint_delta_bytes",
               "memory_200x50_library_bytes_10k_records",
               "memory_200x50_library_bytes_per_row",
               "memory_200x50_internal_delta_bytes",
               "memory_200x50_rss_delta_bytes"],
    "vt_throughput": ["vt_plain_text_bounded_mib_per_sec",
                      "vt_plain_text_bounded_mib_per_sec_min",
                      "vt_plain_text_bounded_mib_per_sec_max",
                      "vt_plain_text_unbounded_mib_per_sec",
                      "vt_escape_heavy_bounded_mib_per_sec",
                      "vt_escape_heavy_bounded_mib_per_sec_min",
                      "vt_escape_heavy_bounded_mib_per_sec_max",
                      "vt_escape_heavy_unbounded_mib_per_sec",
                      "vt_osc_title_bounded_mib_per_sec",
                      "vt_plain_text_bounded_lines_per_sec",
                      "vt_escape_heavy_bounded_records_per_sec",
                      "vt_osc_title_bounded_records_per_sec"],
    "snapshot": ["snapshot_80x24_2k_lines_bytes",
                 "snapshot_80x24_2k_lines_encode_median_ms",
                 "snapshot_80x24_2k_lines_decode_median_ms",
                 "snapshot_80x24_2k_lines_roundtrip_median_ms",
                 "snapshot_200x50_2k_lines_bytes",
                 "snapshot_200x50_2k_lines_encode_median_ms",
                 "snapshot_200x50_2k_lines_decode_median_ms",
                 "snapshot_200x50_2k_lines_roundtrip_median_ms"],
    "search": ["search_frequent_error_cold_median_ms",
               "search_frequent_error_cold_p95_ms",
               "search_frequent_error_rescan_median_ms",
               "search_frequent_error_warm_median_ms",
               "search_frequent_error_us_per_row",
               "search_absent_needle_cold_median_ms",
               "search_short_common_cold_median_ms",
               "search_scaling_2000_records_cold_ms",
               "search_scaling_10000_records_cold_ms"],
    "resize": ["resize_200x50_empty_width_median_ms",
               "resize_200x50_empty_size_median_ms",
               "resize_200x50_2k_lines_width_median_ms",
               "resize_200x50_2k_lines_size_median_ms",
               "resize_200x50_10k_lines_size_median_ms",
               "resize_200x50_10k_lines_size_p95_ms",
               "resize_200x50_10k_lines_size_us_per_retained_row",
               "resize_80x24_10k_lines_size_median_ms"],
}


def main() -> int:
    prefix = sys.argv[1] if len(sys.argv) > 1 else "bench/results/"
    runs = {}
    for label in LABELS:
        with open(f"{prefix}{label}-20260917.json") as handle:
            data = json.load(handle)
        runs[label] = {(m["section"], m["name"]): m["value"] for m in data["metrics"]}

    header = f"{'metric':56}" + "".join(f"{lab:>16}" for lab in LABELS)
    print(header)
    print("-" * len(header))
    for section, names in SECTIONS.items():
        for name in names:
            cells = []
            for label in LABELS:
                value = runs[label].get((section, name))
                cells.append("n/a" if value is None else f"{value:,.4g}")
            print(f"{section + '.' + name:56}" + "".join(f"{c:>16}" for c in cells))
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
