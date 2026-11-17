# Coverage on macOS arm64

## Proven mechanism

kcov 43 can trace Zig 0.16.0 Debug test binaries on this host using Mach
breakpoints. It is not Linux-only. A 20-line probe compiled with:

```
zig test probe.zig -O Debug -femit-bin=probe-test --test-no-exec
kcov --debug=31 --include-path="$PWD" "$PWD/kcov-debug-output" "$PWD/probe-test"
```

returned exit 0, all three tests passed, and Cobertura reported
`lines-covered="10" lines-valid="10" line-rate="1.000"`.
An initial non-debug invocation exited 255 without a report, so failures must
remain fatal. After changing the second test to exercise the first branch again,
the same real measurement gave **9/10 (90.00%)**, proving missed-line detection.
The helper also rejects a failing `/usr/bin/false` target with exit 1.

## Build integration, not yet suite-validated

```
zig build coverage -j2
```

Requires `kcov` on PATH and Python 3.9 or later. The step passes the existing VT,
VT C, main, host-runnable Windows runtime, and agent IPC test artifacts to kcov.
It uses the configured build graph, including existing lib-only and test-filter
options. For a full configured suite do not pass a test filter or lib-only mode.
Reports go into fresh `zig-out/coverage/run-*` directories. Aggregation unions
(filename, line) observations across binaries, avoiding double-counting overlaps.
Missing reports, empty measurements, compilation failures and tracer/test failures
fail the step. Old reports cannot supply a successful result for a new run.

The first `zig build coverage -j2` attempt was bounded at 420 seconds and timed
out (exit 124) during compilation, before any suite reports. **There is no measured
Khostty suite percentage yet.** The step is an unvalidated integration until an
unfiltered invocation completes and emits its summary. No threshold was added.

## What the number means

This measures executed / emitted executable debug source lines under `src/`, not
all repository source lines, branch coverage, UI coverage, platform coverage or
assurance. Zig's lazy analysis omits unused declarations, including the deliberately
unused function in the toy probe. Even 100% here cannot mean full source coverage.
Xcode, UI, Valgrind, schema and distcheck checks are not traced by this step.
Existing build warnings about missing Metal/Xcode do not constitute successful
validation of those paths. This change adds no test skips.

`zig test --help` exposes LLVM IR/bitcode emission and backend selection but no
native source coverage flags. `zig build --help` likewise has no native coverage
option, and `zig env` has no coverage setting. The actual command
`zig test probe.zig -fprofile-instr-generate -fcoverage-mapping --test-no-exec`
failed with `error: unrecognized parameter: '-fprofile-instr-generate'`.
IR emission alone is not coverage instrumentation.

## Honest nearest additional measurements

Report test counts and outcomes per binary, inventory the build roots, and audit
source files without test declarations or test references as separate static
indicators. Neither test count nor reference presence measures executed lines.
The next closure test is an unfiltered `zig build coverage -j2` completing with
exit 0 and a nonempty measured line summary, followed by review of its denominator.
Until then suite coverage is NOT_RUN, not zero and not the probe's percentage.

Full host evidence: `/Users/kooshapari/CodeProjects/temp/khostty-coverage.md` and
`/Users/kooshapari/CodeProjects/temp/khostty-cov-probe/` (volatile).
