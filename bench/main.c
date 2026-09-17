/*
 * Khostty benchmark harness - runner.
 *
 * G8 task 8.1 (harness) and 8.7 (run everything, record machine spec, date,
 * and results). Compiles against the prebuilt libghostty-vt and can be linked
 * against either the Khostty fork's dylib or an upstream Ghostty dylib so the
 * two can be measured with byte-identical source and flags.
 *
 *   bench/.build/bench_khostty  --out bench/results/results.json
 *   bench/.build/bench_upstream --label upstream --out bench/results/upstream.json
 *
 * Provenance comes from the loaded library itself (ghostty_build_info), so a
 * results file cannot silently describe the wrong binary.
 */

#include "bench.h"

#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

typedef struct {
  const char *section;
  void (*run)(BenchReport *);
} Section;

static const Section SECTIONS[] = {
    /* Memory runs first so its process-level baselines are not polluted by
     * large buffers other sections allocate and free. */
    {"memory", bench_memory_footprint},
    {"vt", bench_vt_throughput},
    {"snapshot", bench_snapshot_latency},
    {"search", bench_search_latency},
    {"resize", bench_resize_cost},
};

static void usage(const char *argv0) {
  fprintf(stderr,
          "usage: %s [--label NAME] [--library PATH] [--out FILE]\n"
          "          [--note key=value] [--only SECTION|all] [--quiet-spec]\n"
          "\n"
          "sections: all, memory, vt, snapshot, search, resize\n",
          argv0);
}

static void add_build_provenance(BenchReport *r) {
  GhosttyString version = {NULL, 0};
  if (ghostty_build_info(GHOSTTY_BUILD_INFO_VERSION_STRING, &version) ==
          GHOSTTY_SUCCESS &&
      version.ptr != NULL) {
    char buf[128];
    size_t n = version.len < sizeof(buf) - 1 ? version.len : sizeof(buf) - 1;
    memcpy(buf, version.ptr, n);
    buf[n] = '\0';
    bench_report_note(r, "library_version", buf);
  } else {
    bench_report_note(r, "library_version", "unavailable");
  }

  GhosttyOptimizeMode opt = (GhosttyOptimizeMode)-1;
  if (ghostty_build_info(GHOSTTY_BUILD_INFO_OPTIMIZE, &opt) == GHOSTTY_SUCCESS) {
    const char *s = "unknown";
    switch (opt) {
      case GHOSTTY_OPTIMIZE_DEBUG: s = "debug"; break;
      case GHOSTTY_OPTIMIZE_RELEASE_SAFE: s = "release-safe"; break;
      case GHOSTTY_OPTIMIZE_RELEASE_SMALL: s = "release-small"; break;
      case GHOSTTY_OPTIMIZE_RELEASE_FAST: s = "release-fast"; break;
      default: break;
    }
    bench_report_note(r, "library_optimize", s);
  }

  bool simd = false, kitty = false, tmux = false;
  if (ghostty_build_info(GHOSTTY_BUILD_INFO_SIMD, &simd) == GHOSTTY_SUCCESS) {
    bench_report_note(r, "library_simd", simd ? "true" : "false");
  }
  if (ghostty_build_info(GHOSTTY_BUILD_INFO_KITTY_GRAPHICS, &kitty) ==
      GHOSTTY_SUCCESS) {
    bench_report_note(r, "library_kitty_graphics", kitty ? "true" : "false");
  }
  if (ghostty_build_info(GHOSTTY_BUILD_INFO_TMUX_CONTROL_MODE, &tmux) ==
      GHOSTTY_SUCCESS) {
    bench_report_note(r, "library_tmux_control_mode", tmux ? "true" : "false");
  }
}

static void add_clock_provenance(BenchReport *r) {
  time_t now = time(NULL);
  struct tm local;
  struct tm utc;
  localtime_r(&now, &local);
  gmtime_r(&now, &utc);

  char buf[128];
  snprintf(buf, sizeof(buf), "%04d-%02d-%02d %02d:%02d:%02d",
           local.tm_year + 1900, local.tm_mon + 1, local.tm_mday,
           local.tm_hour, local.tm_min, local.tm_sec);
  bench_report_note(r, "date_local", buf);
  bench_report_note(r, "date_local_tz", tzname[0] ? tzname[0] : "unknown");

  snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02dZ",
           utc.tm_year + 1900, utc.tm_mon + 1, utc.tm_mday, utc.tm_hour,
           utc.tm_min, utc.tm_sec);
  bench_report_note(r, "date_utc", buf);

  snprintf(buf, sizeof(buf), "%lld", (long long)now);
  bench_report_note(r, "unix_time", buf);

  snprintf(buf, sizeof(buf), "%d", (int)getpid());
  bench_report_note(r, "harness_pid", buf);

  /* Machine load at start. Timing on a shared machine is load sensitive; the
   * recorded values let a reader judge whether a results file is comparable. */
  double load[3] = {0, 0, 0};
  if (getloadavg(load, 3) == 3) {
    snprintf(buf, sizeof(buf), "%.2f %.2f %.2f (1m 5m 15m)", load[0], load[1],
             load[2]);
    bench_report_note(r, "load_average_at_start", buf);
  }
  bench_report_note(r, "harness",
                    "bench/main.c linked against libghostty-vt (C, -O2)");
  bench_report_note(r, "timing_clock", "mach_absolute_time, nanosecond");
}

int main(int argc, char **argv) {
  BenchReport report;
  memset(&report, 0, sizeof(report));
  snprintf(report.label, sizeof(report.label), "khostty");
  const char *out_path = NULL;
  const char *only = "all";
  bool print_spec = true;

  for (int i = 1; i < argc; i++) {
    const char *a = argv[i];
    if (strcmp(a, "--label") == 0 && i + 1 < argc) {
      snprintf(report.label, sizeof(report.label), "%s", argv[++i]);
    } else if (strcmp(a, "--library") == 0 && i + 1 < argc) {
      snprintf(report.library, sizeof(report.library), "%s", argv[++i]);
    } else if (strcmp(a, "--out") == 0 && i + 1 < argc) {
      out_path = argv[++i];
    } else if (strcmp(a, "--note") == 0 && i + 1 < argc) {
      char *kv = argv[++i];
      char *eq = strchr(kv, '=');
      if (eq == NULL) {
        fprintf(stderr, "bench: --note expects key=value, got '%s'\n", kv);
        return 2;
      }
      *eq = '\0';
      bench_report_note(&report, kv, eq + 1);
    } else if (strcmp(a, "--only") == 0 && i + 1 < argc) {
      only = argv[++i];
    } else if (strcmp(a, "--quiet-spec") == 0) {
      print_spec = false;
    } else if (strcmp(a, "--help") == 0 || strcmp(a, "-h") == 0) {
      usage(argv[0]);
      return 0;
    } else {
      fprintf(stderr, "bench: unknown argument '%s'\n", a);
      usage(argv[0]);
      return 2;
    }
  }

  if (report.library[0] == '\0') {
    snprintf(report.library, sizeof(report.library), "unknown");
  }

  add_build_provenance(&report);
  add_clock_provenance(&report);

  bench_report_note(&report, "sections_run", only);

  uint64_t suite_start = bench_now_ns();
  if (print_spec) bench_report_header(&report, stdout);

  size_t ran = 0;
  for (size_t i = 0; i < sizeof(SECTIONS) / sizeof(SECTIONS[0]); i++) {
    if (strcmp(only, "all") != 0 && strcmp(only, SECTIONS[i].section) != 0) {
      continue;
    }
    printf("=== section start: %s ===\n", SECTIONS[i].section);
    /* Flush per section: a long-running or pathological section must be
     * visible in the captured raw log while it runs, not only at the end. */
    fflush(stdout);
    SECTIONS[i].run(&report);
    fflush(stdout);
    ran++;
  }
  if (ran == 0) {
    fprintf(stderr, "bench: no section matched '%s'\n", only);
    usage(argv[0]);
    return 2;
  }

  uint64_t suite_ns = bench_now_ns() - suite_start;
  size_t peak_rss = bench_rss_bytes();

  printf("=== suite summary ===\n");
  printf("sections run:      %zu\n", ran);
  printf("metrics recorded:  %zu\n", report.metric_count);
  printf("wall time:         %.3f s\n", (double)suite_ns / 1e9);
  printf("process rss after: %.1f MiB\n", (double)peak_rss / 1048576.0);

  if (out_path != NULL) {
    if (bench_report_write_json(&report, out_path) != 0) return 1;
    printf("json written to:   %s\n", out_path);
  }
  return 0;
}
