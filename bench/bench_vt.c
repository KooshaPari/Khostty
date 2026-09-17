/*
 * G8 task 8.2 - VT ingest throughput.
 *
 * Measures how many bytes per second libghostty-vt can parse and apply when
 * fed two workloads that bracket real shell/agent output:
 *
 *   plain_text    - 80-column ASCII log lines terminated with CRLF, which
 *                   exercises the fast text path, autowrap, and scroll.
 *   escape_heavy  - SGR color runs, absolute cursor addressing, cursor
 *                   save/restore, OSC window-title changes, and short text
 *                   runs, which exercises the escape state machine.
 *
 * Each workload runs twice, once with an 8 MiB scrollback budget and once with
 * no scrollback limit. The pair separates raw parse cost from the pruning and
 * compaction work a real embedder pays when it bounds history: if the bounded
 * figure is much lower, ingest is memory-management bound rather than
 * parser bound.
 *
 * Every repetition builds a fresh terminal and writes the same 64 KiB chunk
 * until a fixed byte target is reached, so each repetition starts from
 * identical state. The reported figure is the median across repetitions.
 */

#include "bench.h"

#include <stdlib.h>
#include <string.h>

#define CHUNK_BYTES (64u * 1024u)
#define BYTES_PER_REP (16u * 1024u * 1024u)
#define REPS 5
#define WARMUP_REPS 1
#define LINE_COLS 78
#define BOUNDED_SCROLLBACK (8u * 1024u * 1024u)

/* Build a chunk of plain 80-column log lines terminated with CRLF. */
static size_t fill_plain_text(uint8_t *buf, size_t cap, size_t *out_records) {
  static const char *words[] = {"compiling", "linking", "warning",
                                "resolved",  "cached",  "fetching"};
  size_t off = 0;
  size_t records = 0;
  while (off + (LINE_COLS + 2) + 128 < cap) {
    char line[128];
    size_t index = records;
    int n = snprintf(line, sizeof(line),
                     "[%06zu] %-10s artifact-%05zu in 0.%03zu s  %s", index,
                     words[index % 6], index % 100000, (index * 37) % 1000,
                     words[(index * 5) % 6]);
    if (n <= 0) break;
    size_t len = (size_t)n;
    if (len > LINE_COLS) len = LINE_COLS;
    memcpy(buf + off, line, len);
    off += len;
    while (len < LINE_COLS) {
      buf[off++] = ' ';
      len++;
    }
    buf[off++] = '\r';
    buf[off++] = '\n';
    records++;
  }
  *out_records = records;
  return off;
}

/* Build a chunk of escape-sequence-heavy output. One record is an SGR run,
 * an absolute cursor move, cursor save, a coloured text run, an OSC title
 * change, cursor restore, a 256-colour run, and a truecolor run. */
static size_t fill_escape_heavy(uint8_t *buf, size_t cap, size_t *out_records) {
  size_t off = 0;
  size_t records = 0;
  while (off + 192 < cap) {
    char seq[192];
    size_t i = records;
    int n = snprintf(
        seq, sizeof(seq),
        "\033[%d;%dm\033[%u;%uH\033[s\033[1;33mstep %05zu\033[0m"
        "\033]2;khostty bench %05zu\007\033[u"
        "\033[38;5;%dmok\033[0m \033[48;2;%d;%d;%dm done\033[0m\r\n",
        (int)(i % 8) + 30, (int)(i % 2), (unsigned)((i % 24) + 1),
        (unsigned)((i % 80) + 1), i, i, (int)(i % 256), (int)((i * 7) % 255),
        (int)((i * 13) % 255), (int)((i * 29) % 255));
    if (n <= 0) break;
    size_t len = (size_t)n;
    if (len + off > cap) break;
    memcpy(buf + off, seq, len);
    off += len;
    records++;
  }
  *out_records = records;
  return off;
}

/* Build a chunk of OSC title changes with a short text run. Added so the
 * escape_heavy cost can be attributed: if this workload is much slower than
 * plain_text, the OSC path rather than the SGR path dominates escape_heavy. */
static size_t fill_osc_title(uint8_t *buf, size_t cap, size_t *out_records) {
  size_t off = 0;
  size_t records = 0;
  while (off + 64 < cap) {
    char seq[64];
    int n = snprintf(seq, sizeof(seq), "\033]2;window title %06zu\007ok\r\n",
                     records);
    if (n <= 0) break;
    size_t len = (size_t)n;
    if (len + off > cap) break;
    memcpy(buf + off, seq, len);
    off += len;
    records++;
  }
  *out_records = records;
  return off;
}

typedef struct {
  const char *name;
  const char *record_unit;
  uint8_t *chunk;
  size_t chunk_len;
  size_t records;
  bool bounded_scrollback;
} Workload;

typedef struct {
  double mib_per_sec;
  double seconds;
  uint64_t writes;
} Sample;

/* One repetition: fresh terminal, same byte target, one timing sample. */
static Sample run_once(const Workload *w) {
  GhosttyTerminal t = bench_terminal_new(80, 24, !w->bounded_scrollback, false);
  if (w->bounded_scrollback) {
    size_t limit = BOUNDED_SCROLLBACK;
    GhosttyResult rc = ghostty_terminal_set(
        t, GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_BYTES, &limit);
    if (rc != GHOSTTY_SUCCESS) {
      bench_die("set scrollback limit failed: %d", (int)rc);
    }
  }

  size_t writes = (size_t)(BYTES_PER_REP / w->chunk_len);
  if (writes == 0) writes = 1;

  uint64_t start = bench_now_ns();
  for (size_t i = 0; i < writes; i++) {
    ghostty_terminal_vt_write(t, w->chunk, w->chunk_len);
  }
  uint64_t elapsed = bench_now_ns() - start;

  ghostty_terminal_free(t);

  Sample s;
  s.seconds = (double)elapsed / 1e9;
  s.writes = writes;
  double bytes = (double)writes * (double)w->chunk_len;
  s.mib_per_sec = (bytes / (1024.0 * 1024.0)) / s.seconds;
  return s;
}

static void run_workload(const Workload *w, BenchSeries *out_mib,
                         BenchSeries *out_records) {
  for (unsigned rep = 0; rep < REPS + WARMUP_REPS; rep++) {
    Sample s = run_once(w);
    if (rep < WARMUP_REPS) continue;
    bench_series_add(out_mib, s.mib_per_sec);
    bench_series_add(out_records,
                     ((double)s.writes * (double)w->records) / s.seconds);
  }
}

static void report_workload(BenchReport *r, const Workload *w,
                            const BenchSeries *mib, const BenchSeries *records) {
  double med_mib = bench_series_median(mib);
  double med_records = bench_series_median(records);
  const char *policy = w->bounded_scrollback ? "8 MiB scrollback" : "unbounded";

  printf("[8.2] VT throughput / %s (%s)\n", w->name, policy);
  printf("      corpus: %zu byte chunk, %zu records/chunk, %u MiB per "
         "repetition, %d repetitions (1 warmup discarded, fresh terminal "
         "per repetition)\n",
         w->chunk_len, w->records,
         (unsigned)(BYTES_PER_REP / (1024u * 1024u)), REPS);
  printf("      throughput median %.1f MiB/s  min %.1f  max %.1f\n", med_mib,
         bench_series_min(mib), bench_series_max(mib));
  printf("      %-10s median %.0f  (min %.0f, max %.0f)\n\n", w->record_unit,
         med_records, bench_series_min(records), bench_series_max(records));

  char metric[128];
  char note[128];
  const char *suffix = w->bounded_scrollback ? "bounded" : "unbounded";
  const char *unit_word = w->name[0] == 'p' ? "lines" : "records";
  snprintf(metric, sizeof(metric), "vt_%s_%s_mib_per_sec", w->name, suffix);
  bench_metric(r, "vt_throughput", metric, med_mib, "MiB/s",
               "median of 5, 16 MiB each, fresh terminal per repetition");

  snprintf(metric, sizeof(metric), "vt_%s_%s_mib_per_sec_min", w->name, suffix);
  bench_metric(r, "vt_throughput", metric, bench_series_min(mib), "MiB/s",
               "min of 5");

  snprintf(metric, sizeof(metric), "vt_%s_%s_mib_per_sec_max", w->name, suffix);
  bench_metric(r, "vt_throughput", metric, bench_series_max(mib), "MiB/s",
               "max of 5");

  snprintf(metric, sizeof(metric), "vt_%s_%s_%s_per_sec", w->name, suffix,
           unit_word);
  snprintf(note, sizeof(note), "median of 5, unit=%s", w->record_unit);
  bench_metric(r, "vt_throughput", metric, med_records, w->record_unit, note);

  snprintf(metric, sizeof(metric), "vt_%s_%s_ns_per_byte", w->name, suffix);
  bench_metric(r, "vt_throughput", metric,
               1e9 / (med_mib * 1024.0 * 1024.0), "ns/byte",
               "derived from median MiB/s");
}

void bench_vt_throughput(BenchReport *r) {
  uint8_t *plain_chunk = (uint8_t *)malloc(CHUNK_BYTES);
  uint8_t *escape_chunk = (uint8_t *)malloc(CHUNK_BYTES);
  uint8_t *osc_chunk = (uint8_t *)malloc(CHUNK_BYTES);
  if (plain_chunk == NULL || escape_chunk == NULL || osc_chunk == NULL) {
    bench_die("malloc for VT corpus buffers failed");
  }

  Workload plain = {.name = "plain_text",
                    .record_unit = "lines/s",
                    .chunk = plain_chunk,
                    .bounded_scrollback = true};
  plain.chunk_len = fill_plain_text(plain_chunk, CHUNK_BYTES, &plain.records);

  Workload escape = {.name = "escape_heavy",
                     .record_unit = "records/s",
                     .chunk = escape_chunk,
                     .bounded_scrollback = true};
  escape.chunk_len = fill_escape_heavy(escape_chunk, CHUNK_BYTES, &escape.records);

  Workload plain_unbounded = plain;
  plain_unbounded.bounded_scrollback = false;

  Workload escape_unbounded = escape;
  escape_unbounded.bounded_scrollback = false;

  Workload osc = {.name = "osc_title",
                  .record_unit = "records/s",
                  .chunk = osc_chunk,
                  .bounded_scrollback = true};
  osc.chunk_len = fill_osc_title(osc_chunk, CHUNK_BYTES, &osc.records);

  /* Order matters for interpretation: each workload is measured bounded then
   * unbounded so the pair can be read as one delta, then the OSC-only workload
   * explains the escape_heavy result. */
  const Workload *cases[] = {&plain, &plain_unbounded, &escape,
                             &escape_unbounded, &osc};

  BenchSeries mib, records;
  for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
    bench_series_init(&mib);
    bench_series_init(&records);
    run_workload(cases[i], &mib, &records);
    report_workload(r, cases[i], &mib, &records);
  }

  bench_report_note(r, "vt_terminal", "80x24");
  bench_report_note(r, "vt_bounded_scrollback_bytes", "8388608");
  bench_report_note(r, "vt_bytes_per_repetition", "16777216");

  free(plain_chunk);
  free(escape_chunk);
  free(osc_chunk);
}
