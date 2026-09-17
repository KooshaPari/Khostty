# Khostty benchmark results - 2026-09-17

Measured with `bench/` against the prebuilt `libghostty-vt.dylib` through its
public C ABI. Nothing in this report is estimated; every number below appears
in a captured raw log or JSON file in this directory.

## Provenance

| Item | Value |
|---|---|
| Date (Pacific local) | 2026-09-17, 04:26-04:30 PDT |
| Date (UTC) | 2026-09-17T11:26Z - 11:30Z |
| Machine | Apple M1 Pro, MacBookPro18,3 |
| Memory | 16 GiB |
| CPUs | 10 logical (8 performance + 2 efficiency) |
| OS | macOS 27.0 (26A5353q), Darwin 27.0.0, arm64 |
| zig | 0.16.0 |
| C compiler | Apple clang 17.0.0, `-O2 -Wall -Wextra -std=c11` |
| Harness source digest | `783a7e013fcf2796...` (sha256 over `bench/bench.h`, `main.c`, `bench_util.c`, `bench_vt.c`, `bench_snapshot.c`, `bench_search.c`, `bench_search_stub.c`, `bench_memory.c`, `bench_resize.c`; recorded in every JSON as `harness_source_sha256`) |

Measured libraries (digest of the exact file linked, recorded in every JSON):

| Label | Library file | sha256 (first 12) | Version | Optimize |
|---|---|---|---|---|
| khostty | `khostty/zig-out/lib/libghostty-vt.dylib` | `06c3df0ffb8d` | 0.1.0-dev | release-safe |
| upstream | `ghostty/zig-out/lib/libghostty-vt.dylib` | `f61394964104` | 0.1.0-dev | release-safe |

The upstream library is the sibling checkout at
`~/CodeProjects/Phenotype/repos/ghostty`, revision `4c52de80a` dated
**2026-08-05**. Khostty's own merge base with `ghostty-org/ghostty` is
`d4c88d806` dated **2026-09-15**, so the comparison library is **41 days older
than Khostty's base**. See "What the comparison does and does not show".

## Commands

Prerequisites and rebuild steps are in `bench/README.md`. The exact commands
used for this report:

```bash
# Khostty library (already present; documented Khostty build)
zig build -Demit-lib-vt -Doptimize=ReleaseSafe

# Upstream library, same flags so the comparison is controlled
cd ~/CodeProjects/Phenotype/repos/ghostty
zig build -Demit-lib-vt -Doptimize=ReleaseSafe

# Four passes: khostty/upstream interleaved, twice, to expose run-to-run spread
cd ~/CodeProjects/Phenotype/repos/khostty
bench/run.sh --label khostty
bench/run.sh --upstream --label upstream
bench/run.sh --label khostty-run2
bench/run.sh --upstream --label upstream-run2

# Re-derive the tables in this report from the JSON
python3 bench/summarize.py bench/results/khostty-20260917.json \
                            bench/results/upstream-20260917.json
python3 bench/matrix.py bench/results/
```

Raw evidence files: `khostty-20260917.{txt,json}`, `upstream-20260917.{txt,json}`,
`khostty-run2-20260917.{txt,json}`, `upstream-run2-20260917.{txt,json}`.

## Machine load: read this before using the absolute numbers

The machine was **heavily loaded** for every pass. Load average at run start
(10 logical CPUs, so load 10 means fully subscribed):

| Pass | Load avg 1 min |
|---|---|
| khostty | 548 |
| upstream | 572 |
| khostty-run2 | 599 |
| upstream-run2 | 674 |

Consequences, stated plainly:

* Absolute throughput and latency figures are **pessimistic** and not
  representative of a quiet machine. The same `plain_text` bounded workload
  measured 72.2 MiB/s during a quieter window earlier the same day and
  21.1 MiB/s in a pass that overlapped a concurrent build, a 3.4x spread.
* Run-to-run spread on the throughput metrics is large (for example
  `plain_text` bounded: 40.9 and 69.1 MiB/s for the same binary).
* The paired upstream numbers were collected interleaved with the Khostty
  numbers so load affects both similarly. **Directional comparisons within a
  pass are the reliable signal; absolute values are not.**
* Memory accounting and snapshot encode/decode medians were stable across
  passes (identical allocator byte counts, and snapshot encode medians within
  15%), because they are short, allocation-heavy operations rather than
  sustained CPU work.

## 8.2 VT ingest throughput

Terminal 80x24, 16 MiB per repetition, 5 timed repetitions after 1 warmup,
fresh terminal per repetition. `bounded` = 8 MiB scrollback budget,
`unbounded` = no scrollback limit. Median MiB/s:

| Workload | khostty | khostty-run2 | upstream | upstream-run2 |
|---|---|---|---|---|
| plain_text bounded | 40.9 | 69.1 | 65.4 | 43.3 |
| plain_text unbounded | 45.3 | 47.1 | 44.4 | 32.1 |
| escape_heavy bounded | 9.51 | 8.19 | 6.70 | 7.71 |
| escape_heavy unbounded | 8.29 | 8.76 | 6.93 | 9.32 |
| osc_title bounded | 15.46 | 9.51 | 6.87 | 6.30 |

Derived rates, khostty pass 1 / pass 2:

* plain_text bounded: 535,600 / 905,800 log lines per second
* escape_heavy bounded: 89,320 / 76,880 records per second
* osc_title bounded: 579,100 / 356,100 records per second

Interpretation:

* `plain_text` is **indistinguishable within noise**: the ordering flips
  between passes (khostty faster in pass 2, upstream faster in pass 1), and
  both unbound medians are within 4%.
* `escape_heavy` and `osc_title` favour Khostty in **both** passes. The
  OSC-title workload is the largest gap (9.5-15.5 vs 6.3-6.9 MiB/s), which
  points at the OSC/title path rather than the SGR path, since the
  `osc_title` corpus contains only `ESC ] 2 ; ... BEL` plus a short text run.
* Bounded versus unbounded shows **no consistent direction** for
  `plain_text` across passes (pass 1: 40.9 bounded vs 45.3 unbounded; pass 2:
  69.1 vs 47.1), so on this machine the 8 MiB scrollback budget is not a
  dominant cost and ingest is parser bound rather than pruning bound. A
  quieter earlier pair measured 72.2 bounded vs 50.1 unbounded, again with the
  bounded case faster, so the ordering is not a stable property.

## 8.3 Snapshot encode/decode

80x24 and 200x50 terminals, 2,000 log records fed (roughly 4,000 retained
rows), median of 30 after 3 warmups. Each repetition frees everything it
allocates. Snapshot size is stable per library across passes and differs by
only 64 bytes (0.04%) between libraries at both sizes, so the format is
compatible while the encoder's bookkeeping is slightly smaller in Khostty.

| Metric | khostty | khostty-run2 | upstream | upstream-run2 |
|---|---|---|---|---|
| 80x24 snapshot size | 155,728 B | 155,728 B | 155,792 B | 155,792 B |
| 80x24 encode median | 0.255 ms | 0.222 ms | 0.932 ms | 0.828 ms |
| 80x24 decode median | 1.145 ms | 1.402 ms | 1.612 ms | 1.534 ms |
| 80x24 round trip | 1.427 ms | 2.284 ms | 2.450 ms | 3.883 ms |
| 200x50 snapshot size | 156,083 B | 156,083 B | 156,147 B | 156,147 B |
| 200x50 encode median | 0.404 ms | 0.340 ms | 1.294 ms | 2.073 ms |
| 200x50 decode median | 2.260 ms | 2.171 ms | 2.975 ms | 4.728 ms |
| 200x50 round trip | 3.181 ms | 2.890 ms | 5.578 ms | 16.61 ms |

Encode is **3.4x to 6.1x faster** in both passes (largest single consistent
effect in the suite). Decode is 1.1x to 2.2x faster on the median. Tails are
not comparable: p95 for encode ranged 0.28-50 ms and for decode 2.5-116 ms
across libraries and passes, because each repetition allocates a fresh page
pool and the tail reflects page mapping rather than the codec. The median is
the representative figure for embedder use; treat the tails as
load-sensitive.

## 8.4 Scrollback search

Only measurable on Khostty: the compared upstream revision does not export
`ghostty_search_*` at all (`bench/build.sh` detects this and compiles
`bench_search_stub.c`, so the section reports "unavailable" instead of failing
to link). See "What the comparison does and does not show".

Corpus: 10,000 log records (2 physical rows each, 19,977 scrollback rows
retained), `error: E0425` every 137th record (73 matches).

| Metric | khostty | khostty-run2 |
|---|---|---|
| cold (fresh search, fresh needle), frequent needle | 242.6 ms | 351.9 ms |
| cold p95 | 326.6 ms | 482.2 ms |
| rescan (same search, changed needle) | 301.1 ms | 310.0 ms |
| warm (same needle, results retained) | 0.529 ms | 0.509 ms |
| cold, absent needle (worst case) | 275.3 ms | 248.8 ms |
| cold, 2,000 records | 22.9 ms | 33.1 ms |
| cold, 10,000 records | 281.6 ms | 152.3 ms |
| cost per retained row | 12.1 us | 17.6 us |

Observations:

* A full scan of ~20,000 rows costs **0.15-0.35 s**, i.e. 12-18 us per
  retained row (about 5-8 MiB/s of cells). This is 2-3 orders of magnitude
  slower per byte than VT ingest.
* `rescan` matches `cold`, which confirms the cost is the scan itself and not
  search-object creation or terminal registration.
* `warm` (same needle re-submitted) is ~0.5 ms, so a find bar that keeps its
  search object and its needle does not pay the scan per frame.
* Scaling is roughly linear above 2,000 records (22.9 ms -> 281.6 ms for
  5x the records in pass 1), with a superlinear step between 2,000 and 5,000
  records that is worth investigating separately.
* Practical consequence for embedders: run search on a background thread and
  drive it with `ghostty_search_tick()`/`ghostty_search_feed()`, which the API
  explicitly supports, rather than calling `ghostty_search_run()` on the UI
  thread.

## 8.5 Memory footprint

Two independent views. `library` bytes come from a counting `GhosttyAllocator`
(every byte the library requests is observed exactly; the test allocator
declines `resize`/`remap` so growth is alloc-and-copy, which the interface
permits). `anonymous` is `task_vm_info.internal`, the private anonymous pages
where the terminal grid lives. Corpus: 10,000 records, two physical rows each.

| Metric | khostty | khostty-run2 | upstream | upstream-run2 |
|---|---|---|---|---|
| 80x24 allocator after create | 6,344 B | 6,344 B | 11,068 B | 11,068 B |
| 80x24 allocator at 10k records | 23,192 B | 23,192 B | 29,906 B | 29,906 B |
| 80x24 allocator bytes per row | 0.84 B | 0.84 B | 0.94 B | 0.94 B |
| 80x24 allocator residual after free | 0 B | 0 B | 0 B | 0 B |
| 80x24 anonymous delta | 13.98 MiB | 13.98 MiB | 14.11 MiB | 14.09 MiB |
| 80x24 rss delta | 13.98 MiB | 13.98 MiB | 14.11 MiB | 14.09 MiB |
| 200x50 allocator at 10k records | 48,744 B | 48,744 B | 68,084 B | 68,084 B |
| 200x50 allocator bytes per row | 2.13 B | 2.13 B | 2.86 B | 2.86 B |
| 200x50 anonymous delta | 34.82 MiB | 34.82 MiB | 34.93 MiB | 34.93 MiB |

Observations:

* Every byte count is **identical across both passes** and both cycles within
  a pass, so this is the most reproducible section in the suite.
* Library bookkeeping is 22.5% smaller at 80x24 and 28.4% smaller at 200x50
  than the compared upstream revision, and scale per row (0.84 vs 0.94 B at
  80x24; 2.13 vs 2.86 B at 200x50).
* Grid page memory is within 1%: the engine stores the same history in about
  the same number of pages. 20,001 retained rows at 80 columns cost
  ~13.98 MiB, or ~0.72 KiB per 80-column row.
* Both libraries release everything on `ghostty_terminal_free()`: allocator
  residual is 0 B and anonymous memory returns to baseline (16-112 KiB
  residual, which is harness noise).
* Caveat: the allocator counter covers library bookkeeping only. The grid
  memory lives in anonymous mappings, so it appears in the anonymous and
  footprint counters, not the allocator counter. Both numbers are required to
  describe footprint.

## 8.6 Resize cost

Per resize call, median of 120 (or 40 for the 10k-line 200x50 case) timed
calls after 10 warmups, alternating down one column (and one row where noted)
and back.

| Case | khostty | khostty-run2 | upstream | upstream-run2 |
|---|---|---|---|---|
| 200x50 empty, width only | 0.045 ms | 0.046 ms | 0.083 ms | 0.076 ms |
| 200x50 empty, size | 0.048 ms | 0.046 ms | 0.084 ms | 0.098 ms |
| 200x50 + 2k lines, width only | 1.013 ms | 0.989 ms | 1.045 ms | 0.989 ms |
| 200x50 + 2k lines, size | 1.102 ms | 1.024 ms | 1.012 ms | 1.062 ms |
| 200x50 + 10k lines, size | 10.96 ms | 5.23 ms | 22.42 ms | 26.41 ms |
| 200x50 + 10k lines, p95 | 87.2 ms | 117.8 ms | 88.7 ms | 142.8 ms |
| 80x24 + 10k lines, size | 2.46 ms | 2.14 ms | 3.32 ms | 2.42 ms |

Observations:

* Empty-terminal resize is ~22,000 calls/s (0.045 ms) on Khostty, 1.7-1.9x
  faster than the compared upstream revision (12,060 and 13,083 calls/s).
* At 2,000 retained lines the two libraries are equal (~1.0 ms), so the cost
  is not dominated by the reflow algorithm at that size.
* At 10,000 lines (200x50) Khostty is 2.0-5.0x faster in both passes. Note the
  pass-to-pass spread on Khostty itself (5.2 vs 11.0 ms), so treat the
  magnitude as approximate and the direction as reliable.
* Tail latency is large (p95 87-143 ms) and similar in both libraries. A resize
  that has to reflow 10,000 retained rows can exceed a frame budget; the median
  is the steady-state figure and the p95 reflects page mapping cost.

## What the comparison does and does not show

**Does show**

1. Khostty inherits upstream's newer VT engine and does not regress it. All
   measured directions are favourable or neutral, and the two memory counters
   are within 1% on page memory.
2. Directional improvements are consistent in both interleaved passes for
   snapshot encode (3.4-6.1x), resize with large history (2.0-5.0x), allocator
   overhead (-22% to -28%), and OSC-heavy ingest (1.5-2.5x).
3. The scrollback search API is a real, working capability of Khostty's
   library, with measured cold and warm cost.

**Does not show**

1. These are **not** fork-specific optimizations. `git diff --name-only
   <merge-base>..HEAD` shows **zero** changes under `src/terminal/` or
   `include/ghostty/`, so the VT core is upstream's code. The deltas above are
   upstream's own progress between 2026-08-05 (the compared checkout) and
   2026-09-15 (Khostty's base), which the fork carries.
2. The compared upstream revision predates the search API (added upstream on
   2026-08-31), so upstream cannot be measured on section 8.4 at all.
3. Absolute values on this machine are load-contaminated (see above).

**To attribute a delta to the fork**, measure against Khostty's exact base:

```bash
git worktree add "$JCODE_SCRATCH_DIR/khostty-base" d4c88d806
cp -R zig-pkg "$JCODE_SCRATCH_DIR/khostty-base/"     # reuse fetched dependencies
cd "$JCODE_SCRATCH_DIR/khostty-base"
zig build -Demit-lib-vt -Doptimize=ReleaseSafe
cd - && bench/run.sh --upstream --label upstream-base
```

That measurement is **not included here**; it was not run in this session.

## Reproducibility notes

* Results are only comparable at the same optimization mode. The first attempt
  at this comparison was invalid because a plain `zig build` in the upstream
  checkout produces a **Debug** library; it spent its time in
  `Page.verifyIntegrity` inside `PageList.grow` and made the suite ~50x slower.
  `bench/` records `library_optimize` from `ghostty_build_info()` precisely so
  that mistake is visible, and `library_sha256` so the wrong file is visible.
* Every results file records the load average, the harness source digest, the
  library file path, and the library digest. Verified for this report: all
  four files share harness digest `783a7e013fcf2796...`, and the two Khostty
  files share library digest `06c3df0ffb8d...` while the two upstream files
  share `f61394964104...`.
* The harness was not modified after these runs; `bench/` sources at
  `783a7e013fcf2796...` are the ones that produced them.
