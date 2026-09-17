/*
 * G8 task 8.6 - resize cost.
 *
 * Resizing is on the interactive path: every window drag, pane split, or
 * font-size change calls ghostty_terminal_resize(), and a width change forces
 * the grid to reflow every retained row, including scrollback. This benchmark
 * separates the two costs:
 *
 *   width change - reflows wrapped lines across the retained grid, the
 *                  expensive case
 *   size change  - changes both columns and rows
 *
 * and runs each against terminals holding 0, 2,000, and 10,000 scrollback
 * lines, so the cost per retained row is observable. Each repetition resizes
 * down and back up and both resizes are timed, giving per-call latency instead
 * of per-pair latency.
 */

#include "bench.h"

#include <stdlib.h>

#define REPS_SMALL 120
#define REPS_LARGE 40
#define WARMUP 10

typedef struct {
  const char *name;
  uint16_t cols;
  uint16_t rows;
  size_t lines;
  unsigned reps;
  bool change_rows;
} ResizeCase;

static void run_case(BenchReport *r, const ResizeCase *c) {
  GhosttyTerminal t = bench_terminal_new(c->cols, c->rows, true, false);
  if (c->lines > 0) bench_feed_log_lines(t, c->lines, NULL, 0);

  uint16_t alt_cols = (uint16_t)(c->cols - 1);
  uint16_t alt_rows = c->change_rows ? (uint16_t)(c->rows - 1) : c->rows;

  BenchSeries series;
  bench_series_init(&series);

  for (unsigned i = 0; i < c->reps + WARMUP; i++) {
    bool down = (i % 2) == 0;
    uint16_t cols = down ? alt_cols : c->cols;
    uint16_t rows = down ? alt_rows : c->rows;
    uint64_t t0 = bench_now_ns();
    GhosttyResult rc = ghostty_terminal_resize(t, cols, rows, 8, 16);
    uint64_t t1 = bench_now_ns();
    if (rc != GHOSTTY_SUCCESS) bench_die("resize failed: %d", (int)rc);
    if (i < WARMUP) continue;
    bench_series_add(&series, (double)(t1 - t0) / 1e6);
  }

  double med = bench_series_median(&series);
  double per_row_us = c->lines > 0 ? (med * 1000.0) / (double)c->lines : 0.0;

  printf("[8.6] resize / %s\n", c->name);
  printf("      %ux%u <-> %ux%u, %zu scrollback lines, %u timed resizes\n",
         (unsigned)c->cols, (unsigned)c->rows, (unsigned)alt_cols,
         (unsigned)alt_rows, c->lines, c->reps);
  printf("      per resize: median %.4f ms  p95 %.4f ms  min %.4f  max %.4f\n",
         med, bench_series_p95(&series), bench_series_min(&series),
         bench_series_max(&series));
  if (c->lines > 0) {
    printf("      cost per retained row: %.3f us\n", per_row_us);
  }
  printf("      sustained: %.0f resizes/sec (median)\n\n", 1000.0 / med);

  char metric[160];
  char note[128];
#define EMIT(suffix, value, unitv, notetext)                                  \
  do {                                                                        \
    snprintf(metric, sizeof(metric), "resize_%s_%s", c->name, suffix);        \
    snprintf(note, sizeof(note), "%s", notetext);                             \
    bench_metric(r, "resize", metric, value, unitv, note);                    \
  } while (0)

  EMIT("median_ms", med, "ms", "median per resize call");
  EMIT("p95_ms", bench_series_p95(&series), "ms", "p95 per resize call");
  EMIT("resizes_per_sec", 1000.0 / med, "resizes/s", "derived from median");
  if (c->lines > 0) {
    EMIT("us_per_retained_row", per_row_us, "us/row",
         "median ms / scrollback lines");
  }
#undef EMIT

  ghostty_terminal_free(t);
}

void bench_resize_cost(BenchReport *r) {
  static const ResizeCase CASES[] = {
      {"200x50_empty_width", 200, 50, 0, REPS_SMALL, false},
      {"200x50_empty_size", 200, 50, 0, REPS_SMALL, true},
      {"200x50_2k_lines_width", 200, 50, 2000, REPS_SMALL, false},
      {"200x50_2k_lines_size", 200, 50, 2000, REPS_SMALL, true},
      {"200x50_10k_lines_size", 200, 50, 10000, REPS_LARGE, true},
      {"80x24_10k_lines_size", 80, 24, 10000, REPS_LARGE, true},
  };

  for (size_t i = 0; i < sizeof(CASES) / sizeof(CASES[0]); i++) {
    run_case(r, &CASES[i]);
  }

  bench_report_note(r, "resize_cell_px", "8x16");
  bench_report_note(r, "resize_alternation",
                    "down one column (and one row where noted) then back");
}
