# Khostty benchmark suite (G8)

Benchmarks that measure `libghostty-vt` directly, so Khostty's performance claims
are backed by numbers that can be reproduced on any machine rather than by
assertions.

The harness is plain C compiled against the prebuilt shared library, following
the same pattern as `conformance/`. That means the measurements exercise the
shipped library through its public C ABI: no reimplementation, no test doubles.

## Layout

| File | Purpose | WBS task |
|------|---------|----------|
| `bench.h` | Shared declarations for the harness | 8.1 |
| `main.c` | Runner: argument parsing, provenance, section dispatch, JSON output | 8.1, 8.7 |
| `bench_util.c` | Timing, memory sampling, machine spec, report serialization | 8.1 |
| `bench_vt.c` | VT ingest throughput (plain text, escape-heavy, OSC-only; bounded and unbounded scrollback) | 8.2 |
| `bench_snapshot.c` | Snapshot encode/decode/round-trip latency at 80x24 and 200x50 | 8.3 |
| `bench_search.c` | Scrollback search latency (cold, rescan, warm) plus a scaling sweep | 8.4 |
| `bench_search_stub.c` | Compiled instead of `bench_search.c` when the target library has no search API | 8.4 |
| `bench_memory.c` | Memory footprint with a counting allocator plus process counters | 8.5 |
| `bench_resize.c` | Resize cost with and without retained scrollback | 8.6 |
| `build.sh` | Compiles the harness against a chosen library | 8.1 |
| `run.sh` | Builds, runs, and captures results with provenance | 8.1, 8.7 |
| `results/` | Captured runs and the written report | 8.7, 8.8 |

## Prerequisites

1. `zig` 0.16.0 (the version pinned by `build.zig.zon`) on `PATH`.
2. A built library:

   ```bash
   zig build            # produces zig-out/lib/libghostty-vt.dylib
   ```

   Only `libghostty-vt` is required by the harness. If a full `zig build` fails
   later on unrelated targets (the macOS app bundle, the XCFramework, Metal
   shaders), the VT library is still produced and the benchmarks still run.

3. Xcode command line tools (`cc`, and an SDK under `/Applications/Xcode.app`).

## Running

```bash
bench/run.sh                      # build if needed, run everything, capture
bench/run.sh --only search        # one section: memory|vt|snapshot|search|resize
bench/run.sh --upstream           # measure the upstream library instead
bench/build.sh                    # build only
bench/build.sh upstream           # build only, against the upstream library
```

`run.sh` writes two files under `results/`, both named from the label and the
Pacific date:

* `<label>-<YYYYMMDD>.txt` - the raw stdout of the run, human readable.
* `<label>-<YYYYMMDD>.json` - the same metrics in machine form, with the machine
  spec, toolchain, library build info, git revision, and load average.

Both are captured in one invocation, so the report and the JSON cannot drift
apart.

## Comparing against upstream

`build.sh upstream` links the same source and the same compiler flags against a
second checkout's `libghostty-vt.dylib`. Point it at any checkout:

```bash
UPSTREAM_REPO=/path/to/ghostty bench/run.sh --upstream
```

Notes:

* The compile always uses **Khostty's** headers, so linking succeeds only if the
  other library is ABI compatible for the functions used. That is itself a
  useful ABI check.
* If the target library does not export `ghostty_search_new`, `build.sh`
  substitutes `bench_search_stub.c` and section 8.4 records "unavailable"
  instead of failing to link. Nothing is estimated.
* Both binaries report their own version, optimization mode, SIMD support, and
  kitty-graphics support from `ghostty_build_info()`, so a results file cannot
  silently describe the wrong binary.

## Measurement discipline

* Timing uses `mach_absolute_time` (nanosecond monotonic clock).
* Each reported figure is a median over repeated samples; min/max and p95 are
  reported alongside so tail behaviour is visible.
* Every timed region includes the full lifetime cost an embedder pays for the
  operation being measured (allocation and free included).
* Benchmarks do not print inside timed regions.
* Memory is measured three independent ways, and the section documents which
  counter covers which bytes. See `results/README.md` for the caveats.

## Machine load matters

Absolute numbers are sensitive to machine load. Every run records the 1/5/15
minute load average in both the text and JSON output. Compare runs only at
similar load, and prefer the paired Khostty-versus-upstream comparison, which is
measured back to back under the same conditions, for load-independent claims.

A run on a quiet machine is required for the numbers to mean anything: the
observed medians on this fleet machine moved by more than 3x between a loaded
and an idle window.
