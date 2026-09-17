/*
 * Khostty benchmark harness - shared declarations.
 *
 * Companion to conformance/harness.c: a small, dependency-free C program
 * compiled against the prebuilt libghostty-vt (see bench/build.sh). Each
 * benchmark function implements one task from the G8 benchmark suite in
 * docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md.
 *
 * The harness never fabricates results: a benchmark that cannot run reports
 * the reason through bench_metric(..., "unsupported") or bench_die(), and the
 * emitted JSON/raw log records exactly which measurements were observed.
 */

#ifndef KHOSTTY_BENCH_H
#define KHOSTTY_BENCH_H

#include <ghostty/vt.h>

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

/* ---------- fixed capacities (no dynamic allocation for bookkeeping) ---------- */

#define BENCH_SERIES_MAX 512
#define BENCH_METRIC_MAX 160
#define BENCH_NOTE_MAX 64
#define BENCH_TEXT_MAX 256

/* ---------- timing ---------- */

/* Monotonic nanosecond clock (mach_absolute_time based on Darwin). */
uint64_t bench_now_ns(void);

/* ---------- sample series ---------- */

typedef struct {
  double v[BENCH_SERIES_MAX];
  size_t n;
} BenchSeries;

void bench_series_init(BenchSeries *s);
void bench_series_add(BenchSeries *s, double ms);
double bench_series_min(const BenchSeries *s);
double bench_series_max(const BenchSeries *s);
double bench_series_mean(const BenchSeries *s);
double bench_series_median(const BenchSeries *s);
double bench_series_p95(const BenchSeries *s);
double bench_series_sum(const BenchSeries *s);

/* ---------- report ---------- */

typedef struct {
  char key[BENCH_TEXT_MAX];
  char value[BENCH_TEXT_MAX];
} BenchNote;

typedef struct {
  char section[48];
  char name[BENCH_TEXT_MAX];
  double value;
  char unit[32];
  char note[BENCH_TEXT_MAX];
} BenchMetric;

typedef struct {
  BenchMetric metrics[BENCH_METRIC_MAX];
  size_t metric_count;
  BenchNote notes[BENCH_NOTE_MAX];
  size_t note_count;
  char label[BENCH_TEXT_MAX];       /* e.g. "khostty" or "upstream" */
  char library[BENCH_TEXT_MAX];     /* dylib path the binary was linked to */
  bool truncated;
} BenchReport;

void bench_report_note(BenchReport *r, const char *key, const char *value);
void bench_metric(BenchReport *r, const char *section, const char *name,
                  double value, const char *unit, const char *note);

/* Human-readable run header: machine spec, library, label, notes. */
void bench_report_header(const BenchReport *r, FILE *out);
/* Serialize the full report (spec + notes + metrics) as JSON. */
int bench_report_write_json(const BenchReport *r, const char *path);

/* ---------- process memory ---------- */

/* Resident set size of this process in bytes (mach task basic info). */
size_t bench_rss_bytes(void);
/* Physical footprint in bytes (TASK_VM_INFO phys_footprint), 0 if unavailable. */
size_t bench_phys_footprint_bytes(void);
/* Sum of size_in_use across all malloc zones. */
size_t bench_malloc_in_use_bytes(void);
/* Anonymous private bytes (task_vm_info.internal): heap plus anonymous
 * mappings, which is where libghostty-vt gets its grid pages. */
size_t bench_internal_bytes(void);
/* Peak anonymous private bytes. */
size_t bench_internal_peak_bytes(void);
/* Purgeable/compressed bytes held by the process. */
size_t bench_compressed_bytes(void);

/* ---------- benchmarks (one per G8 task) ---------- */

void bench_vt_throughput(BenchReport *r);     /* 8.2 */
void bench_snapshot_latency(BenchReport *r);  /* 8.3 */
void bench_search_latency(BenchReport *r);    /* 8.4 */
void bench_memory_footprint(BenchReport *r);  /* 8.5 */
void bench_resize_cost(BenchReport *r);       /* 8.6 */

/* ---------- shared helpers ---------- */

/*
 * Create a terminal. `unlimited_scrollback` clears the scrollback byte limit;
 * `continuation_tracking` enables GHOSTTY_TERMINAL_OPT_CONTINUATION_MAX_BYTES
 * so snapshot encoding is valid mid-sequence.
 */
GhosttyTerminal bench_terminal_new(uint16_t cols, uint16_t rows,
                                   bool unlimited_scrollback,
                                   bool continuation_tracking);

/*
 * Same as bench_terminal_new() but with an explicit allocator, so the memory
 * benchmark can account for every byte the library requests.
 */
GhosttyTerminal bench_terminal_new_with(const GhosttyAllocator *alloc,
                                        uint16_t cols, uint16_t rows,
                                        bool unlimited_scrollback,
                                        bool continuation_tracking);

/*
 * Feed `lines` synthetic log lines, one ghostty_terminal_vt_write call per
 * line, to exercise the per-line scrollback path. Every `marker_stride`-th
 * line contains `marker` (stride 0 disables the marker). Returns bytes fed.
 */
size_t bench_feed_log_lines(GhosttyTerminal t, size_t lines, const char *marker,
                            unsigned marker_stride);

/* Print to stderr and exit(1). Used only for truly unrunnable benchmarks. */
void bench_die(const char *fmt, ...);

#endif /* KHOSTTY_BENCH_H */
