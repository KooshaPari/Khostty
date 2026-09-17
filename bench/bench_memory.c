/*
 * G8 task 8.5 - memory footprint.
 *
 * Two independent views of the same question ("what does a terminal cost?"):
 *
 * 1. Library-attributed bytes. The terminal is created with a counting
 *    GhosttyAllocator, so every byte libghostty-vt requests is observed
 *    exactly, including the bytes it later releases. This is the authoritative
 *    per-terminal number and it is immune to allocator and page-cache noise.
 *    In exchange, resize() and remap() deliberately decline in-place growth
 *    (they return false / NULL, which the allocator interface explicitly
 *    permits), so the reported figure reflects alloc-and-copy growth. That is
 *    the only way to attribute bytes without relying on malloc zone internals.
 *    See the note caveat_library_bytes in the results JSON.
 *
 * 2. Process-level corroboration. RSS and phys_footprint deltas show the real
 *    page cost. These floor at the allocator's reuse: the first cycle is the
 *    meaningful one, later cycles report near-zero deltas because freed pages
 *    are recycled rather than returned to the OS.
 *
 * Corpus: 10,000 synthetic log records where each record spans two physical
 * rows, so 10,000 records fill roughly 20,000 retained rows. The retained-row
 * count is printed for every cycle so the row/byte relationship is checkable.
 *
 * This section runs first in the suite, before other benchmarks allocate and
 * free large buffers.
 */

#include "bench.h"

#include <stdlib.h>
#include <string.h>

#define SCROLLBACK_RECORDS 10000
#define CHECKPOINT_RECORDS 1000
#define CYCLES 2

/* ---------- counting allocator ---------- */

typedef struct {
  size_t live;
  size_t peak;
  size_t alloc_calls;
  size_t free_calls;
  size_t declined_resize;
  size_t declined_remap;
  size_t failed_alloc;
} CountState;

static void *count_alloc(void *ctx, size_t len, uint8_t alignment,
                         uintptr_t ret_addr) {
  (void)ret_addr;
  CountState *st = (CountState *)ctx;
  if (alignment > 16) {
    /* The interface guarantees alignment <= 16, which malloc satisfies on
     * Darwin; anything larger would need posix_memalign and is treated as an
     * allocator failure rather than an unchecked assumption. */
    st->failed_alloc++;
    return NULL;
  }
  void *p = malloc(len);
  if (p == NULL) {
    st->failed_alloc++;
    return NULL;
  }
  st->alloc_calls++;
  st->live += len;
  if (st->live > st->peak) st->peak = st->live;
  return p;
}

/* Decline in-place growth: the caller then allocates, copies, and frees, which
 * keeps byte accounting exact. Returning false / NULL is part of the contract. */
static bool count_resize(void *ctx, void *memory, size_t memory_len,
                         uint8_t alignment, size_t new_len,
                         uintptr_t ret_addr) {
  (void)memory;
  (void)memory_len;
  (void)alignment;
  (void)new_len;
  (void)ret_addr;
  ((CountState *)ctx)->declined_resize++;
  return false;
}

static void *count_remap(void *ctx, void *memory, size_t memory_len,
                         uint8_t alignment, size_t new_len,
                         uintptr_t ret_addr) {
  (void)memory;
  (void)memory_len;
  (void)alignment;
  (void)new_len;
  (void)ret_addr;
  ((CountState *)ctx)->declined_remap++;
  return NULL;
}

static void count_free(void *ctx, void *memory, size_t memory_len,
                       uint8_t alignment, uintptr_t ret_addr) {
  (void)alignment;
  (void)ret_addr;
  CountState *st = (CountState *)ctx;
  if (memory == NULL) return;
  free(memory);
  st->free_calls++;
  if (st->live >= memory_len) {
    st->live -= memory_len;
  } else {
    st->live = 0;
  }
}

static const GhosttyAllocatorVtable COUNT_VTABLE = {
    .alloc = count_alloc,
    .resize = count_resize,
    .remap = count_remap,
    .free = count_free,
};

/* ---------- process counters ---------- */

typedef struct {
  size_t rss;
  size_t footprint;
  size_t internal;
  size_t internal_peak;
  size_t malloc_bytes;
} MemSnapshot;

static MemSnapshot mem_snap(void) {
  MemSnapshot s;
  s.rss = bench_rss_bytes();
  s.footprint = bench_phys_footprint_bytes();
  s.internal = bench_internal_bytes();
  s.internal_peak = bench_internal_peak_bytes();
  s.malloc_bytes = bench_malloc_in_use_bytes();
  return s;
}

static double delta_bytes(size_t after, size_t before) {
  if (after >= before) return (double)(after - before);
  return -(double)(before - after);
}

static void run_cycle(BenchReport *r, const char *scenario, uint16_t cols,
                      uint16_t rows, unsigned cycle) {
  CountState counts;
  memset(&counts, 0, sizeof(counts));
  GhosttyAllocator allocator = {.ctx = &counts, .vtable = &COUNT_VTABLE};

  MemSnapshot base = mem_snap();

  GhosttyTerminal t =
      bench_terminal_new_with(&allocator, cols, rows, true, false);
  size_t after_create = counts.live;

  bench_feed_log_lines(t, CHECKPOINT_RECORDS, NULL, 0);
  size_t after_1k = counts.live;

  bench_feed_log_lines(t, SCROLLBACK_RECORDS - CHECKPOINT_RECORDS, NULL, 0);
  size_t after_10k = counts.live;
  size_t peak = counts.peak;

  size_t scrollback_rows = 0;
  size_t total_rows = 0;
  (void)ghostty_terminal_get(t, GHOSTTY_TERMINAL_DATA_SCROLLBACK_ROWS,
                             &scrollback_rows);
  (void)ghostty_terminal_get(t, GHOSTTY_TERMINAL_DATA_TOTAL_ROWS, &total_rows);

  MemSnapshot at_full = mem_snap();
  ghostty_terminal_free(t);
  size_t residual = counts.live;
  MemSnapshot after_free = mem_snap();

  double rows_growth = (double)(after_10k - after_create);
  double per_row = rows_growth / (double)(total_rows > rows ? total_rows - rows : 1);
  double per_record = rows_growth / (double)SCROLLBACK_RECORDS;
  double rss_delta = delta_bytes(at_full.rss, base.rss);
  double footprint_delta = delta_bytes(at_full.footprint, base.footprint);
  double residual_malloc = delta_bytes(after_free.malloc_bytes, base.malloc_bytes);
  double internal_delta = delta_bytes(at_full.internal, base.internal);
  double internal_after_free = delta_bytes(after_free.internal, base.internal);

  printf("[8.5] memory footprint / %s (cycle %u)\n", scenario, cycle);
  printf("      library bytes: create %zu B, +1000 records %zu B, "
         "at %d records %zu B (peak %zu B)\n",
         after_create, after_1k - after_create, SCROLLBACK_RECORDS, after_10k,
         peak);
  printf("      per retained row %.1f B, per record %.0f B "
         "(%.0f rows retained)\n",
         per_row, per_record, (double)total_rows);
  printf("      library blocks: %zu allocs, %zu frees, "
         "%zu declined resizes, %zu declined remaps\n",
         counts.alloc_calls, counts.free_calls, counts.declined_resize,
         counts.declined_remap);
  printf("      process: anonymous-internal +%.1f KiB "
         "(%.2f MiB total). rss +%.1f KiB, phys_footprint +%.1f KiB\n",
         internal_delta / 1024.0, (double)at_full.internal / 1048576.0,
         rss_delta / 1024.0, footprint_delta / 1024.0);
  printf("      after free: library bytes %zu B, anonymous-internal %+.1f KiB, "
         "malloc-zone residual %+.1f KiB\n\n",
         residual, internal_after_free / 1024.0, residual_malloc / 1024.0);

  char metric[192];
  char note[128];
#define EMIT(name, value, unitv, notetext)                                    \
  do {                                                                        \
    snprintf(metric, sizeof(metric), "memory_%s_%s", scenario, name);         \
    snprintf(note, sizeof(note), "%s", notetext);                             \
    bench_metric(r, "memory", metric, value, unitv, note);                    \
  } while (0)

  EMIT("library_create_bytes", (double)after_create, "bytes",
       "live bytes after ghostty_terminal_new");
  EMIT("library_bytes_1k_records", (double)(after_1k - after_create), "bytes",
       "growth from create to 1000 records");
  EMIT("library_bytes_10k_records", (double)after_10k, "bytes",
       "live bytes at 10000 records");
  EMIT("library_peak_bytes", (double)peak, "bytes", "high-water live bytes");
  EMIT("library_bytes_per_row", per_row, "bytes/row",
       "growth / retained rows");
  EMIT("library_bytes_per_record", per_record, "bytes/record",
       "growth / 10000 records");
  EMIT("library_residual_bytes", (double)residual, "bytes",
       "live bytes after terminal free");
  EMIT("alloc_calls", (double)counts.alloc_calls, "calls", "counting allocator");
  EMIT("free_calls", (double)counts.free_calls, "calls", "counting allocator");
  EMIT("declined_resize_calls", (double)counts.declined_resize, "calls",
       "allocator returned false by design");
  EMIT("declined_remap_calls", (double)counts.declined_remap, "calls",
       "allocator returned NULL by design");
  EMIT("internal_delta_bytes", internal_delta, "bytes",
       "anonymous private bytes, includes grid pages");
  EMIT("internal_after_free_delta_bytes", internal_after_free, "bytes",
       "anonymous private bytes after terminal free");
  EMIT("rss_delta_bytes", rss_delta, "bytes", "process rss delta");
  EMIT("phys_footprint_delta_bytes", footprint_delta, "bytes",
       "process phys_footprint delta");
  EMIT("rows_retained", (double)total_rows, "rows",
       "scrollback + viewport rows");
  EMIT("malloc_zone_residual_bytes", residual_malloc, "bytes",
       "process malloc zones after free");

#undef EMIT
}

void bench_memory_footprint(BenchReport *r) {
  const uint16_t dims[2][2] = {{80, 24}, {200, 50}};
  const char *names[2] = {"80x24", "200x50"};

  for (size_t s = 0; s < 2; s++) {
    for (unsigned c = 1; c <= CYCLES; c++) {
      run_cycle(r, names[s], dims[s][0], dims[s][1], c);
    }
  }

  bench_report_note(r, "memory_records", "10000");
  bench_report_note(r, "memory_rows_per_record", "2");
  bench_report_note(r, "memory_corpus", "synthetic log records, no marker");
  bench_report_note(r, "memory_primary_counter",
                    "GhosttyAllocator live bytes (exact)");
  bench_report_note(
      r, "caveat_library_bytes",
      "counting allocator declines resize/remap so growth is alloc+copy; "
      "bytes are exact, timing is not measured in this section");
  bench_report_note(
      r, "memory_process_counters",
      "mach task_info internal (anonymous private) + rss + phys_footprint, "
      "malloc zone size_in_use");
  bench_report_note(
      r, "attribution",
      "GhosttyAllocator sees library bookkeeping only; the terminal page/grid "
      "memory is obtained from anonymous mappings, so it appears in the "
      "internal/footprint counters, not the allocator counter");
  bench_report_note(
      r, "caveat_malloc_zones",
      "malloc zone statistics do not cover the library's mmap-backed pages, "
      "so they are reported only as a residual check");
}
