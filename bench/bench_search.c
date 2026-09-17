/*
 * G8 task 8.4 - scrollback search latency.
 *
 * Agent harnesses need "find that error in the last 10k lines" to be
 * interactive. This benchmark separates the three costs a find bar actually
 * pays, because they differ by three orders of magnitude:
 *
 *   cold     - a fresh search object with a new needle: the full scan of the
 *              active area plus scrollback. This is what a user pays when the
 *              find bar opens or when a new query is typed.
 *   rescan   - an existing search object whose needle changes, forcing the
 *              full scan again. Confirms the cold cost is the scan itself and
 *              not search-object setup or terminal registration.
 *   warm     - the same needle re-submitted on an existing search object. The
 *              library keeps its results, so this only reports "already caught
 *              up" and must be sub-millisecond; it is the number an embedder
 *              pays per rendered frame while the find bar stays open.
 *
 * A scaling sweep at the end measures cold latency against corpus size, so the
 * per-row cost can be checked for linearity rather than trusted from a single
 * point.
 *
 * Corpus: 10,000 synthetic log records, two physical rows per record, with
 * "error: E0425" on every 137th record, giving a deterministic 73 matches.
 */

#include "bench.h"

#include <stdlib.h>
#include <string.h>

#define RECORDS 10000
#define MARKER_STRIDE 137
#define COLD_REPS 9
#define RESCAN_REPS 5
#define WARM_REPS 25
#define WARMUP 2

typedef struct {
  const char *name;
  const char *needle;
} NeedleCase;

static const NeedleCase CASES[] = {
    {"frequent_error", "error: E0425"},
    {"absent_needle", "zzz-no-such-token-zzz"},
    {"short_common", "cache miss"},
};

/* Alternating needle used by the rescan case. */
/* Distinct from every case needle so each rescan repetition is a real
 * rescan rather than a retained-result no-op. */
static const char *ALT_NEEDLE = "cache hit";

static GhosttyTerminal build_terminal(size_t records) {
  GhosttyTerminal t = bench_terminal_new(80, 24, true, false);
  bench_feed_log_lines(t, records, "error: E0425", MARKER_STRIDE);
  return t;
}

static void run_case(BenchReport *r, GhosttyTerminal t, const NeedleCase *c,
                     size_t scrollback_rows, size_t total_rows) {
  BenchSeries cold, warm;
  bench_series_init(&cold);
  bench_series_init(&warm);
  size_t matches = 0;

  for (unsigned rep = 0; rep < COLD_REPS + WARMUP; rep++) {
    GhosttySearch search = NULL;
    GhosttyString needle = {(const uint8_t *)c->needle, strlen(c->needle)};

    uint64_t t0 = bench_now_ns();
    GhosttyResult rc = ghostty_search_new(NULL, &search, t);
    if (rc != GHOSTTY_SUCCESS) bench_die("search_new failed: %d", (int)rc);
    rc = ghostty_search_set(search, GHOSTTY_SEARCH_OPT_NEEDLE, &needle);
    if (rc != GHOSTTY_SUCCESS) bench_die("search_set needle failed: %d", (int)rc);
    rc = ghostty_search_run(search);
    if (rc != GHOSTTY_SUCCESS) bench_die("search_run failed: %d", (int)rc);

    size_t found = 0;
    rc = ghostty_search_get(search, GHOSTTY_SEARCH_DATA_TOTAL_MATCHES, &found);
    if (rc != GHOSTTY_SUCCESS) bench_die("search_get matches failed: %d", (int)rc);
    GhosttySearchStatus status = GHOSTTY_SEARCH_STATUS_RUNNING;
    (void)ghostty_search_get(search, GHOSTTY_SEARCH_DATA_STATUS, &status);

    /* Warm path: same search object, same needle, run again. */
    uint64_t t1 = bench_now_ns();
    rc = ghostty_search_run(search);
    if (rc != GHOSTTY_SUCCESS) bench_die("warm search_run failed: %d", (int)rc);
    uint64_t t2 = bench_now_ns();
    ghostty_search_free(search);

    if (status != GHOSTTY_SEARCH_STATUS_COMPLETE) {
      bench_die("search for '%s' did not complete (status %d)", c->needle,
                (int)status);
    }
    if (rep < WARMUP) continue;
    matches = found;
    bench_series_add(&cold, (double)(t1 - t0) / 1e6);
    bench_series_add(&warm, (double)(t2 - t1) / 1e6);
  }

  /* Rescan: one search object, alternating needles so every run rescans. */
  BenchSeries rescan;
  bench_series_init(&rescan);
  {
    GhosttySearch search = NULL;
    GhosttyString a = {(const uint8_t *)c->needle, strlen(c->needle)};
    GhosttyString b = {(const uint8_t *)ALT_NEEDLE, strlen(ALT_NEEDLE)};
    (void)ghostty_search_new(NULL, &search, t);
    for (unsigned rep = 0; rep < RESCAN_REPS + WARMUP; rep++) {
      const GhosttyString *n = (rep % 2 == 0) ? &a : &b;
      (void)ghostty_search_set(search, GHOSTTY_SEARCH_OPT_NEEDLE, n);
      uint64_t t0 = bench_now_ns();
      GhosttyResult rc = ghostty_search_run(search);
      uint64_t t1 = bench_now_ns();
      if (rc != GHOSTTY_SUCCESS) bench_die("rescan run failed: %d", (int)rc);
      if (rep < WARMUP) continue;
      bench_series_add(&rescan, (double)(t1 - t0) / 1e6);
    }
    ghostty_search_free(search);
  }

  double med_cold = bench_series_median(&cold);
  double med_rescan = bench_series_median(&rescan);
  double med_warm = bench_series_median(&warm);
  double rows_per_ms = (double)total_rows / med_cold;

  printf("[8.4] scrollback search / %s\n", c->name);
  printf("      needle \"%s\": %zu matches across %zu rows "
         "(%zu scrollback + 24 viewport)\n",
         c->needle, matches, total_rows, scrollback_rows);
  printf("      cold   median %.3f ms  p95 %.3f ms  min %.3f  max %.3f "
         "(full scan, fresh search)\n",
         med_cold, bench_series_p95(&cold), bench_series_min(&cold),
         bench_series_max(&cold));
  printf("      rescan median %.3f ms  p95 %.3f ms  (same search, changed "
         "needle forces a full rescan)\n",
         med_rescan, bench_series_p95(&rescan));
  printf("      warm   median %.4f ms  p95 %.4f ms  (same needle, caught up)\n",
         med_warm, bench_series_p95(&warm));
  printf("      full-scan rate %.1f rows/ms (%.1f MiB/s of cells, "
         "%.2f us per retained row)\n\n",
         rows_per_ms, ((double)total_rows * 80.0 / 1048576.0) / (med_cold / 1e3),
         med_cold * 1000.0 / (double)total_rows);

  char metric[160];
  char note[128];
#define EMIT(kind, value, unitv, notetext)                                    \
  do {                                                                        \
    snprintf(metric, sizeof(metric), "search_%s_%s", c->name, kind);          \
    snprintf(note, sizeof(note), "%s", notetext);                             \
    bench_metric(r, "search", metric, value, unitv, note);                    \
  } while (0)

  EMIT("cold_median_ms", med_cold, "ms", "median of 9 full scans");
  EMIT("cold_p95_ms", bench_series_p95(&cold), "ms", "p95 of 9 full scans");
  EMIT("rescan_median_ms", med_rescan, "ms",
       "median of 5, alternating needle");
  EMIT("warm_median_ms", med_warm, "ms",
       "median of 25, same needle, retained results");
  EMIT("rows_per_ms", rows_per_ms, "rows/ms", "retained rows / cold median ms");
  EMIT("us_per_row", med_cold * 1000.0 / (double)total_rows, "us/row",
       "cold median / retained rows");
  EMIT("matches", (double)matches, "matches", "deterministic corpus");
#undef EMIT
}

/* Cold-search latency against corpus size, to check linearity. */
static void run_scaling(BenchReport *r) {
  static const size_t sizes[] = {2000, 10000};
  static const unsigned reps = 5;

  printf("[8.4] cold-search scaling (needle \"error: E0425\")\n");
  printf("      %-9s %-9s %-12s %-12s\n", "records", "rows", "cold_med_ms",
         "us_per_row");

  for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
    GhosttyTerminal t = build_terminal(sizes[i]);
    size_t rows = 0;
    (void)ghostty_terminal_get(t, GHOSTTY_TERMINAL_DATA_TOTAL_ROWS, &rows);

    BenchSeries series;
    bench_series_init(&series);
    GhosttyString needle = {(const uint8_t *)"error: E0425", 12};
    for (unsigned rep = 0; rep < reps; rep++) {
      GhosttySearch s = NULL;
      (void)ghostty_search_new(NULL, &s, t);
      (void)ghostty_search_set(s, GHOSTTY_SEARCH_OPT_NEEDLE, &needle);
      uint64_t t0 = bench_now_ns();
      GhosttyResult rc = ghostty_search_run(s);
      uint64_t t1 = bench_now_ns();
      if (rc != GHOSTTY_SUCCESS) bench_die("scaling search failed: %d", (int)rc);
      ghostty_search_free(s);
      bench_series_add(&series, (double)(t1 - t0) / 1e6);
    }
    double med = bench_series_median(&series);
    ghostty_terminal_free(t);

    printf("      %-9zu %-9zu %-12.3f %-12.3f\n", sizes[i], rows, med,
           med * 1000.0 / (double)rows);

    char metric[128];
    snprintf(metric, sizeof(metric), "search_scaling_%zu_records_cold_ms",
             sizes[i]);
    char note[96];
    snprintf(note, sizeof(note), "median of 5, %zu rows retained", rows);
    bench_metric(r, "search", metric, med, "ms", note);
  }
  printf("\n");
}

void bench_search_latency(BenchReport *r) {
  GhosttyTerminal t = build_terminal(RECORDS);
  size_t scrollback_rows = 0;
  size_t total_rows = 0;
  (void)ghostty_terminal_get(t, GHOSTTY_TERMINAL_DATA_SCROLLBACK_ROWS,
                             &scrollback_rows);
  (void)ghostty_terminal_get(t, GHOSTTY_TERMINAL_DATA_TOTAL_ROWS, &total_rows);

  printf("[8.4] corpus: %d records, %zu scrollback rows retained, "
         "marker every %d records\n", RECORDS, scrollback_rows,
         MARKER_STRIDE);

  for (size_t i = 0; i < sizeof(CASES) / sizeof(CASES[0]); i++) {
    run_case(r, t, &CASES[i], scrollback_rows, total_rows);
  }
  ghostty_terminal_free(t);

  run_scaling(r);

  bench_report_note(r, "search_records_fed", "10000");
  bench_report_note(r, "search_rows_per_record", "2");
  bench_report_note(r, "search_corpus",
                    "synthetic log records, error marker every 137 records");
  bench_report_note(
      r, "search_interpretation",
      "cold = full scan; rescan confirms it is scan-bound, not setup-bound; "
      "warm = same needle with retained results, the per-frame cost");
}
