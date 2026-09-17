/*
 * G8 task 8.3 - snapshot encode/decode latency.
 *
 * libghostty-vt can serialize a terminal (screen + scrollback + parser
 * continuation) into a compact snapshot and restore it in another process or
 * after a restart. That round trip is what makes session restore in an agent
 * harness cheap, so both halves are timed here:
 *
 *   encode - ghostty_snapshot_encode_alloc() on a populated terminal
 *   decode - ghostty_snapshot_decoder_new_buf() + decoder_decode() into a
 *            fresh terminal, then freeing both
 *
 * The snapshot is produced once and reused for the decode timings so the
 * decode numbers are not contaminated by encode cost. Every repetition frees
 * what it allocates, so the reported latency includes the full lifetime cost
 * an embedder pays.
 */

#include "bench.h"

#include <stdlib.h>

#define LINES 2000
#define WARMUP 3
#define REPS 30

static GhosttyTerminal build_source(uint16_t cols, uint16_t rows,
                                    size_t lines) {
  GhosttyTerminal t = bench_terminal_new(cols, rows, true, true);
  bench_feed_log_lines(t, lines, "error: E0425", 137);
  return t;
}

static void run_scenario(BenchReport *r, const char *name, uint16_t cols,
                         uint16_t rows, size_t lines) {
  GhosttyTerminal source = build_source(cols, rows, lines);

  uint64_t scrollback_rows = 0;
  (void)ghostty_terminal_get(source, GHOSTTY_TERMINAL_DATA_SCROLLBACK_ROWS,
                            &scrollback_rows);

  BenchSeries enc, dec, roundtrip;
  bench_series_init(&enc);
  bench_series_init(&dec);
  bench_series_init(&roundtrip);

  size_t snapshot_len = 0;
  uint8_t *snapshot = NULL;

  for (unsigned rep = 0; rep < REPS + WARMUP; rep++) {
    uint8_t *buf = NULL;
    size_t len = 0;
    uint64_t t0 = bench_now_ns();
    GhosttyResult rc = ghostty_snapshot_encode_alloc(source, NULL, &buf, &len);
    uint64_t t1 = bench_now_ns();
    if (rc != GHOSTTY_SUCCESS) {
      bench_die("snapshot encode failed: %d", (int)rc);
    }
    if (rep < WARMUP) {
      ghostty_free(NULL, buf, len);
      continue;
    }
    bench_series_add(&enc, (double)(t1 - t0) / 1e6);
    if (snapshot == NULL) {
      snapshot = buf;
      snapshot_len = len;
    } else {
      ghostty_free(NULL, buf, len);
    }
  }

  if (snapshot == NULL) bench_die("snapshot encode produced no output");

  for (unsigned rep = 0; rep < REPS + WARMUP; rep++) {
    GhosttySnapshotDecoder decoder = NULL;
    GhosttyTerminal restored = NULL;
    uint64_t t0 = bench_now_ns();
    GhosttyResult rc =
        ghostty_snapshot_decoder_new_buf(NULL, &decoder, snapshot, snapshot_len);
    if (rc != GHOSTTY_SUCCESS) bench_die("decoder_new_buf failed: %d", (int)rc);
    rc = ghostty_snapshot_decoder_decode(decoder, &restored);
    uint64_t t1 = bench_now_ns();
    if (rc != GHOSTTY_SUCCESS) bench_die("decoder_decode failed: %d", (int)rc);
    ghostty_snapshot_decoder_free(decoder);
    ghostty_terminal_free(restored);

    if (rep < WARMUP) continue;
    bench_series_add(&dec, (double)(t1 - t0) / 1e6);
  }

  /* Full encode+decode round trip, as a session restore actually pays it. */
  for (unsigned rep = 0; rep < REPS + WARMUP; rep++) {
    uint8_t *buf = NULL;
    size_t len = 0;
    uint64_t t0 = bench_now_ns();
    GhosttyResult rc = ghostty_snapshot_encode_alloc(source, NULL, &buf, &len);
    if (rc != GHOSTTY_SUCCESS) bench_die("roundtrip encode failed: %d", (int)rc);
    GhosttySnapshotDecoder decoder = NULL;
    GhosttyTerminal restored = NULL;
    rc = ghostty_snapshot_decoder_new_buf(NULL, &decoder, buf, len);
    if (rc != GHOSTTY_SUCCESS) bench_die("roundtrip decoder_new_buf failed: %d", (int)rc);
    rc = ghostty_snapshot_decoder_decode(decoder, &restored);
    uint64_t t1 = bench_now_ns();
    if (rc != GHOSTTY_SUCCESS) bench_die("roundtrip decode failed: %d", (int)rc);
    ghostty_snapshot_decoder_free(decoder);
    ghostty_terminal_free(restored);
    ghostty_free(NULL, buf, len);

    if (rep < WARMUP) continue;
    bench_series_add(&roundtrip, (double)(t1 - t0) / 1e6);
  }

  double med_enc = bench_series_median(&enc);
  double med_dec = bench_series_median(&dec);
  double med_rt = bench_series_median(&roundtrip);

  printf("[8.3] snapshot %s (%ux%u, %zu lines fed, %llu scrollback rows)\n",
         name, (unsigned)cols, (unsigned)rows, lines,
         (unsigned long long)scrollback_rows);
  printf("      snapshot size: %zu bytes (%.2f KiB)\n", snapshot_len,
         (double)snapshot_len / 1024.0);
  printf("      encode  median %.3f ms  p95 %.3f ms  min %.3f  max %.3f\n",
         med_enc, bench_series_p95(&enc), bench_series_min(&enc),
         bench_series_max(&enc));
  printf("      decode  median %.3f ms  p95 %.3f ms  min %.3f  max %.3f\n",
         med_dec, bench_series_p95(&dec), bench_series_min(&dec),
         bench_series_max(&dec));
  printf("      round   median %.3f ms  p95 %.3f ms  (encode+decode+free)\n\n",
         med_rt, bench_series_p95(&roundtrip));

  char metric[128];
  char note[128];
#define EMIT(suffix, value, unitv, notetext)                                  \
  do {                                                                        \
    snprintf(metric, sizeof(metric), "snapshot_%s_%s", name, suffix);         \
    snprintf(note, sizeof(note), "%s", notetext);                             \
    bench_metric(r, "snapshot", metric, value, unitv, note);                  \
  } while (0)

  EMIT("bytes", (double)snapshot_len, "bytes", "serialized size");
  EMIT("encode_median_ms", med_enc, "ms", "median of 30");
  EMIT("encode_p95_ms", bench_series_p95(&enc), "ms", "p95 of 30");
  EMIT("decode_median_ms", med_dec, "ms", "median of 30");
  EMIT("decode_p95_ms", bench_series_p95(&dec), "ms", "p95 of 30");
  EMIT("roundtrip_median_ms", med_rt, "ms", "median of 30");
  EMIT("roundtrip_p95_ms", bench_series_p95(&roundtrip), "ms", "p95 of 30");
  EMIT("encode_mib_per_sec", ((double)snapshot_len / 1048576.0) / (med_enc / 1e3),
       "MiB/s", "snapshot bytes / encode time");
  EMIT("decode_mib_per_sec", ((double)snapshot_len / 1048576.0) / (med_dec / 1e3),
       "MiB/s", "snapshot bytes / decode time");

#undef EMIT

  bench_report_note(r, "snapshot_scenario", name);
  ghostty_free(NULL, snapshot, snapshot_len);
  ghostty_terminal_free(source);
}

void bench_snapshot_latency(BenchReport *r) {
  run_scenario(r, "80x24_2k_lines", 80, 24, LINES);
  run_scenario(r, "200x50_2k_lines", 200, 50, LINES);
}
