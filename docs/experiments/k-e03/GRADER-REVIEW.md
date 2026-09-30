# K-E03 grader review — 2026-09-30

Candidate: `experiment/mature-recovery-k-e03@1a146ee2e62d94e1ffa2308652365adc2060fe72`.
Baseline: `a29aa9c6553d9f42aa68e2919116c0f6d53f329d`.
Status: **PARTIAL / EXECUTION REQUIRED. No existence-gate decision.**

## Candidate strengths

Only two files differ from baseline: `khostty-vt/build.rs` and `khostty-vt/tools/k_e03_compare.py`. The candidate:
- adds fail-closed `KHOSTTY_VT_REQUIRE_LINK` evidence mode while preserving ordinary typecheck behavior;
- requires an explicit native artifact when evidence mode names one;
- builds an out-of-tree Rust consumer;
- executes create/write/resize/render/search/snapshot-restore;
- checks missing-library failure;
- includes a Rust lifetime misuse compile-fail control;
- builds and executes a direct C consumer against the same supplied native library;
- hashes the native artifact and records commands/stdout/stderr;
- explicitly labels source/origin claims unauthenticated and states that a true upstream-vs-Khostty comparison needs separately built artifacts.

The harness does not claim its own preferred winner.

## Blocking evidence gaps

### G-KE03-01 — no authenticated native-library provenance

`--library-source-sha` and `--library-origin` are caller strings. Native artifact SHA-256 authenticates bytes, not their source revision/build configuration. This is correctly disclosed by the harness but prevents an upstream-vs-Khostty architectural conclusion.

Closure: separate build receipt must bind source tree/commit, build command/toolchain/options, produced library hash and headers hash. Run at least once for frozen Khostty and once for the chosen upstream comparison revision.

### G-KE03-02 — direct C comparator is not yet the same functional journey

Rust exercises create/write/resize/render/search/snapshot-restore. Direct C only exercises create/write/free. Therefore current metrics cannot support a claim that the wrapper reduces application complexity for the same behavior.

Closure: direct C consumer must implement the same selected journey, or the comparison must explicitly restrict itself to create/write/free and shrink the Rust side to match. Compare like with like.

### G-KE03-03 — requested evidence dimensions are incomplete

The harness records wrapper LOC and unsafe mentions but does not yet measure generated-vs-handwritten drift result, install steps, package dependency footprint, or a native ABI mismatch failure. The compile-fail lifetime control is valuable and safer than intentionally dereferencing freed C state, but it covers only one safety dimension.

Closure: run the existing binding/ABI verification against the exact library/header pair; record install/build steps from a clean out-of-tree directory; add a deliberate header/library mismatch or other safe ABI/version incompatibility control.

### G-KE03-04 — no execution receipt for this exact candidate

Queried combined status exposes CodeRabbit only. No harness JSON receipt bound to `1a146ee…` was found. Source quality is not execution.

Closure: execute the harness in a native-capable environment with exact artifact/build receipts. A PASS_EXPERIMENT is still not a fork existence-gate pass until both upstream and Khostty artifacts are compared.

## Disposition

The candidate is a useful verifier/harness and is narrower than production wrapper changes. Keep experimental. Do not merge into main merely because the harness itself is sound.
