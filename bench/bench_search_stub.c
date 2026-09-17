/*
 * G8 task 8.4 fallback - scrollback search reported as unavailable.
 *
 * Some upstream revisions of libghostty-vt do not export the ghostty_search_*
 * API at all. bench/build.sh selects this translation unit instead of
 * bench_search.c when the target library lacks ghostty_search_new(), so the
 * harness still links and the missing capability is reported as a measurement
 * that could not be made. Nothing is estimated or interpolated.
 */

#include "bench.h"

#include <stdio.h>

void bench_search_latency(BenchReport *r) {
  printf("[8.4] scrollback search / UNAVAILABLE\n");
  printf("      the linked libghostty-vt does not export ghostty_search_new, "
         "so the search API cannot be measured for this build.\n");
  printf("      no values are reported for this section.\n\n");

  bench_report_note(r, "search_status",
                    "unavailable: library does not export ghostty_search_*");
  bench_metric(r, "search", "search_available", 0, "bool",
               "0 = ghostty_search_new absent from the linked library");
}
