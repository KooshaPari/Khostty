/*
 * Khostty benchmark harness - timing, memory sampling, machine spec, and
 * JSON/human report serialization.
 *
 * Companion to bench/bench.h. Darwin-specific memory sampling uses mach
 * task_info plus the malloc zone statistics API; both report what the
 * process actually holds, not a modelled estimate.
 */

#include "bench.h"

#include <errno.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <malloc/malloc.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>

/* ---------- timing ---------- */

uint64_t bench_now_ns(void) {
  static mach_timebase_info_data_t tb;
  static bool have_tb = false;
  if (!have_tb) {
    mach_timebase_info(&tb);
    have_tb = true;
  }
  uint64_t t = mach_absolute_time();
  return (t * tb.numer) / tb.denom;
}

/* ---------- series ---------- */

void bench_series_init(BenchSeries *s) { s->n = 0; }

void bench_series_add(BenchSeries *s, double ms) {
  if (s->n < BENCH_SERIES_MAX) s->v[s->n++] = ms;
}

static int cmp_double(const void *a, const void *b) {
  double x = *(const double *)a;
  double y = *(const double *)b;
  if (x < y) return -1;
  if (x > y) return 1;
  return 0;
}

static void sorted_copy(const BenchSeries *s, double *out) {
  for (size_t i = 0; i < s->n; i++) out[i] = s->v[i];
  qsort(out, s->n, sizeof(double), cmp_double);
}

double bench_series_min(const BenchSeries *s) {
  if (s->n == 0) return 0.0;
  double m = s->v[0];
  for (size_t i = 1; i < s->n; i++)
    if (s->v[i] < m) m = s->v[i];
  return m;
}

double bench_series_max(const BenchSeries *s) {
  if (s->n == 0) return 0.0;
  double m = s->v[0];
  for (size_t i = 1; i < s->n; i++)
    if (s->v[i] > m) m = s->v[i];
  return m;
}

double bench_series_sum(const BenchSeries *s) {
  double total = 0.0;
  for (size_t i = 0; i < s->n; i++) total += s->v[i];
  return total;
}

double bench_series_mean(const BenchSeries *s) {
  if (s->n == 0) return 0.0;
  return bench_series_sum(s) / (double)s->n;
}

double bench_series_median(const BenchSeries *s) {
  if (s->n == 0) return 0.0;
  double tmp[BENCH_SERIES_MAX];
  sorted_copy(s, tmp);
  size_t mid = s->n / 2;
  if (s->n % 2 == 1) return tmp[mid];
  return (tmp[mid - 1] + tmp[mid]) / 2.0;
}

double bench_series_p95(const BenchSeries *s) {
  if (s->n == 0) return 0.0;
  double tmp[BENCH_SERIES_MAX];
  sorted_copy(s, tmp);
  size_t idx = (size_t)(0.95 * (double)(s->n - 1));
  return tmp[idx];
}

/* ---------- report ---------- */

void bench_report_note(BenchReport *r, const char *key, const char *value) {
  if (r->note_count >= BENCH_NOTE_MAX) {
    r->truncated = true;
    return;
  }
  BenchNote *n = &r->notes[r->note_count++];
  snprintf(n->key, sizeof(n->key), "%s", key);
  snprintf(n->value, sizeof(n->value), "%s", value);
}

void bench_metric(BenchReport *r, const char *section, const char *name,
                  double value, const char *unit, const char *note) {
  if (r->metric_count >= BENCH_METRIC_MAX) {
    r->truncated = true;
    return;
  }
  BenchMetric *m = &r->metrics[r->metric_count++];
  snprintf(m->section, sizeof(m->section), "%s", section);
  snprintf(m->name, sizeof(m->name), "%s", name);
  m->value = value;
  snprintf(m->unit, sizeof(m->unit), "%s", unit);
  snprintf(m->note, sizeof(m->note), "%s", note ? note : "");
}

/* ---------- machine spec ---------- */

static bool sysctl_str(const char *name, char *out, size_t out_len) {
  size_t len = out_len;
  if (sysctlbyname(name, out, &len, NULL, 0) != 0) return false;
  if (len > 0) out[len - 1 < out_len ? len - 1 : out_len - 1] = '\0';
  return true;
}

static bool sysctl_u64(const char *name, uint64_t *out) {
  size_t len = sizeof(*out);
  return sysctlbyname(name, out, &len, NULL, 0) == 0;
}

static void format_bytes(uint64_t bytes, char *out, size_t out_len) {
  double gib = (double)bytes / (1024.0 * 1024.0 * 1024.0);
  snprintf(out, out_len, "%.1f GiB (%llu bytes)", gib,
           (unsigned long long)bytes);
}

void bench_report_header(const BenchReport *r, FILE *out) {
  char chip[128] = "unknown";
  char model[128] = "unknown";
  char os_release[128] = "unknown";
  char os_version[128] = "unknown";
  uint64_t memsize = 0;
  uint64_t ncpu = 0;
  uint64_t pcores = 0;
  uint64_t ecores = 0;

  sysctl_str("machdep.cpu.brand_string", chip, sizeof(chip));
  sysctl_str("hw.model", model, sizeof(model));
  sysctl_u64("hw.memsize", &memsize);
  sysctl_u64("hw.ncpu", &ncpu);
  sysctl_u64("hw.perflevel0.physicalcpu", &pcores);
  sysctl_u64("hw.perflevel1.physicalcpu", &ecores);
  sysctl_str("kern.osproductversion", os_version, sizeof(os_version));
  sysctl_str("kern.osrelease", os_release, sizeof(os_release));

  char mem_str[64] = "unknown";
  if (memsize > 0) format_bytes(memsize, mem_str, sizeof(mem_str));

  fprintf(out, "=== Khostty libghostty-vt benchmark harness ===\n");
  fprintf(out, "label:        %s\n", r->label);
  fprintf(out, "library:      %s\n", r->library);
  fprintf(out, "machine:      %s (%s)\n", chip, model);
  fprintf(out, "memory:       %s\n", mem_str);
  if (pcores > 0 || ecores > 0) {
    fprintf(out, "cpus:         %llu logical (%llu performance + %llu efficiency)\n",
            (unsigned long long)ncpu, (unsigned long long)pcores,
            (unsigned long long)ecores);
  } else {
    fprintf(out, "cpus:         %llu logical\n", (unsigned long long)ncpu);
  }
  fprintf(out, "os:           macOS %s (Darwin %s)\n", os_version, os_release);

  struct utsname u;
  if (uname(&u) == 0) {
    fprintf(out, "kernel:       %s %s %s\n", u.sysname, u.release, u.machine);
  }

  for (size_t i = 0; i < r->note_count; i++) {
    fprintf(out, "%-13s %s\n", r->notes[i].key, r->notes[i].value);
  }
  if (r->truncated) {
    fprintf(out, "warning:      metric/note capacity exceeded, JSON truncated\n");
  }
  fprintf(out, "\n");
}

/* ---------- JSON ---------- */

static void json_escape(const char *in, char *out, size_t out_len) {
  size_t j = 0;
  for (size_t i = 0; in[i] != '\0' && j + 2 < out_len; i++) {
    unsigned char c = (unsigned char)in[i];
    if (c == '"' || c == '\\') {
      out[j++] = '\\';
      out[j++] = (char)c;
    } else if (c == '\n') {
      out[j++] = '\\';
      out[j++] = 'n';
    } else if (c < 0x20) {
      /* drop other control characters */
    } else {
      out[j++] = (char)c;
    }
  }
  out[j] = '\0';
}

int bench_report_write_json(const BenchReport *r, const char *path) {
  FILE *f = fopen(path, "w");
  if (f == NULL) {
    fprintf(stderr, "bench: cannot open %s: %s\n", path, strerror(errno));
    return -1;
  }

  char chip[128] = "unknown";
  char model[128] = "unknown";
  char os_version[128] = "unknown";
  uint64_t memsize = 0;
  uint64_t ncpu = 0;
  sysctl_str("machdep.cpu.brand_string", chip, sizeof(chip));
  sysctl_str("hw.model", model, sizeof(model));
  sysctl_str("kern.osproductversion", os_version, sizeof(os_version));
  sysctl_u64("hw.memsize", &memsize);
  sysctl_u64("hw.ncpu", &ncpu);

  char esc[BENCH_TEXT_MAX * 2];
  json_escape(r->label, esc, sizeof(esc));
  json_escape(chip, esc, sizeof(esc));

  fprintf(f, "{\n");
  fprintf(f, "  \"label\": \"%s\",\n", esc);
  json_escape(r->library, esc, sizeof(esc));
  fprintf(f, "  \"library\": \"%s\",\n", esc);
  json_escape(chip, esc, sizeof(esc));
  fprintf(f, "  \"machine\": {\n    \"chip\": \"%s\",\n", esc);
  json_escape(model, esc, sizeof(esc));
  fprintf(f, "    \"model\": \"%s\",\n", esc);
  json_escape(os_version, esc, sizeof(esc));
  fprintf(f, "    \"os\": \"macOS %s\",\n", esc);
  fprintf(f, "    \"memory_bytes\": %llu,\n", (unsigned long long)memsize);
  fprintf(f, "    \"logical_cpus\": %llu\n  },\n", (unsigned long long)ncpu);

  fprintf(f, "  \"notes\": {\n");
  for (size_t i = 0; i < r->note_count; i++) {
    char k[BENCH_TEXT_MAX * 2], v[BENCH_TEXT_MAX * 2];
    json_escape(r->notes[i].key, k, sizeof(k));
    json_escape(r->notes[i].value, v, sizeof(v));
    fprintf(f, "    \"%s\": \"%s\"%s\n", k, v,
            (i + 1 < r->note_count) ? "," : "");
  }
  fprintf(f, "  },\n");

  fprintf(f, "  \"metrics\": [\n");
  for (size_t i = 0; i < r->metric_count; i++) {
    const BenchMetric *m = &r->metrics[i];
    char s[96], n[BENCH_TEXT_MAX * 2], u[64], note[BENCH_TEXT_MAX * 2];
    json_escape(m->section, s, sizeof(s));
    json_escape(m->name, n, sizeof(n));
    json_escape(m->unit, u, sizeof(u));
    json_escape(m->note, note, sizeof(note));
    fprintf(f,
            "    {\"section\": \"%s\", \"name\": \"%s\", \"value\": %.6g, "
            "\"unit\": \"%s\", \"note\": \"%s\"}%s\n",
            s, n, m->value, u, note, (i + 1 < r->metric_count) ? "," : "");
  }
  fprintf(f, "  ]\n}\n");
  fclose(f);
  return 0;
}

/* ---------- process memory ---------- */

size_t bench_rss_bytes(void) {
  mach_task_basic_info_data_t info;
  mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
  kern_return_t kr = task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                               (task_info_t)&info, &count);
  if (kr != KERN_SUCCESS) return 0;
  return (size_t)info.resident_size;
}

size_t bench_phys_footprint_bytes(void) {
  task_vm_info_data_t info;
  mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
  kern_return_t kr = task_info(mach_task_self(), TASK_VM_INFO,
                               (task_info_t)&info, &count);
  if (kr != KERN_SUCCESS) return 0;
  return (size_t)info.phys_footprint;
}

static bool task_vm_info(task_vm_info_data_t *out) {
  mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
  return task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)out, &count) ==
         KERN_SUCCESS;
}

size_t bench_internal_bytes(void) {
  task_vm_info_data_t info;
  if (!task_vm_info(&info)) return 0;
  return (size_t)info.internal;
}

size_t bench_internal_peak_bytes(void) {
  task_vm_info_data_t info;
  if (!task_vm_info(&info)) return 0;
  return (size_t)info.internal_peak;
}

size_t bench_compressed_bytes(void) {
  task_vm_info_data_t info;
  if (!task_vm_info(&info)) return 0;
  return (size_t)info.compressed;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

size_t bench_malloc_in_use_bytes(void) {
  vm_address_t *zones = NULL;
  unsigned int count = 0;
  if (malloc_get_all_zones(mach_task_self(), NULL, &zones, &count) !=
          KERN_SUCCESS ||
      zones == NULL) {
    return 0;
  }
  size_t total = 0;
  for (unsigned int i = 0; i < count; i++) {
    malloc_statistics_t st;
    malloc_zone_statistics((malloc_zone_t *)zones[i], &st);
    total += st.size_in_use;
  }
  return total;
}

#pragma clang diagnostic pop

/* ---------- shared helpers ---------- */

void bench_die(const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  fprintf(stderr, "bench: fatal: ");
  vfprintf(stderr, fmt, ap);
  fprintf(stderr, "\n");
  va_end(ap);
  exit(1);
}

GhosttyTerminal bench_terminal_new(uint16_t cols, uint16_t rows,
                                   bool unlimited_scrollback,
                                   bool continuation_tracking) {
  return bench_terminal_new_with(NULL, cols, rows, unlimited_scrollback,
                                 continuation_tracking);
}

GhosttyTerminal bench_terminal_new_with(const GhosttyAllocator *alloc,
                                        uint16_t cols, uint16_t rows,
                                        bool unlimited_scrollback,
                                        bool continuation_tracking) {
  GhosttyTerminal t = NULL;
  GhosttyResult rc = ghostty_terminal_new(alloc, &t, cols, rows);
  if (rc != GHOSTTY_SUCCESS || t == NULL) {
    bench_die("ghostty_terminal_new(%ux%u) failed: %d", (unsigned)cols,
              (unsigned)rows, (int)rc);
  }
  if (unlimited_scrollback) {
    /* NULL pointer removes the byte limit; keeps 10k-line corpi resident. */
    rc = ghostty_terminal_set(t, GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_BYTES,
                              NULL);
    if (rc != GHOSTTY_SUCCESS) {
      bench_die("scrollback max bytes (unlimited) failed: %d", (int)rc);
    }
  }
  if (continuation_tracking) {
    size_t limit = 4096;
    rc = ghostty_terminal_set(t, GHOSTTY_TERMINAL_OPT_CONTINUATION_MAX_BYTES,
                              &limit);
    if (rc != GHOSTTY_SUCCESS) {
      bench_die("continuation max bytes failed: %d", (int)rc);
    }
  }
  return t;
}

size_t bench_feed_log_lines(GhosttyTerminal t, size_t lines, const char *marker,
                            unsigned marker_stride) {
  char buf[192];
  size_t total = 0;
  for (size_t i = 0; i < lines; i++) {
    bool marked = marker != NULL && marker_stride > 0 &&
                  (i % (size_t)marker_stride) == 0;
    int n = snprintf(buf, sizeof(buf),
                     "[%05zu] compiling module %05zu ... %s\r\n"
                     "        elapsed 0.%03zu s  cache %s\r\n",
                     i, i, marked ? marker : "ok", (size_t)(i % 1000),
                     (i % 7 == 0) ? "miss" : "hit");
    if (n <= 0) continue;
    size_t len = (size_t)n;
    if (len > sizeof(buf)) len = sizeof(buf);
    ghostty_terminal_vt_write(t, (const uint8_t *)buf, len);
    total += len;
  }
  return total;
}
