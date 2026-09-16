# Khostty Deep WBS — 2026-09-16

## Scope

Khostty is a Ghostty fork. The upstream already ships `libghostty-vt` with 32 C headers,
37 examples (C, Zig, C++, Swift, WASM), fuzz tests, and benchmarks. The fork's value
is not "building what upstream already has" but proving the embedding path works end-to-end
with Khostty-specific tooling and conformance evidence.

---

## G0: Fork Hygiene (DONE)

| ID | Task | Est | Status |
|----|------|-----|--------|
| 0.1 | Strip 7 boilerplate CI files | 10m | DONE |
| 0.2 | Replace with Zig-aware CI (fmt + build) | 10m | DONE |
| 0.3 | Fix Metal toolchain skip (-Demit-macos-app=false) | 10m | DONE |
| 0.4 | Commit assessment docs + handoff | 10m | DONE |

---

## G1: Native Build Validation (DONE)

| ID | Task | Est | Status |
|----|------|-----|--------|
| 1.1 | Verify libghostty-vt static + dynamic + xcframework | 10m | DONE |
| 1.2 | Verify WASM cross-compile (795KB MVP) | 10m | DONE |
| 1.3 | Run zig fmt --check on full src/ | 10m | DONE |

---

## G2: Conformance Evidence (NOT STARTED)

The dossier requires "no unacceptable terminal correctness regression." We must prove
the parser works via conformance tests, not just that it compiles.

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 2.1 | Run upstream Zig tests: `zig build test` | 10m | G0 | Tests exist in src/ |
| 2.2 | Run fuzz corpus: `test/fuzz-libghostty/` | 10m | G0 | Parse all seed inputs |
| 2.3 | Build + run c-vt example (OSC parser) | 10m | G1 | Proves C API works |
| 2.4 | Build + run c-vt-stream example | 10m | G1 | Proves streaming parse |
| 2.5 | Build + run c-vt-sgr example | 10m | G1 | Proves SGR handling |
| 2.6 | Build + run c-vt-modes example | 10m | G1 | Proves mode switching |
| 2.7 | Build + run c-vt-kitty-graphics example | 10m | G1 | Proves image protocol |
| 2.8 | Build + run zig-vt example | 10m | G1 | Proves Zig API works |
| 2.9 | Document conformance results in session doc | 10m | 2.1-2.8 | Pass/fail matrix |
| 2.10 | Identify any conformance gaps vs upstream | 10m | 2.9 | Delta analysis |

---

## G3: Embedding SDK — Rust FFI (NOT STARTED)

Target: a Rust crate (`khostty-vt`) that wraps the C headers, enabling agent-side
terminal state tracking without a running terminal.

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 3.1 | Scaffold Rust crate with build.rs + bindgen | 10m | G1 | Link libghostty-vt |
| 3.2 | Wrap ghostty_terminal_* (create, write, free) | 10m | 3.1 | Core lifecycle |
| 3.3 | Wrap ghostty_screen_* (read cells, cursor pos) | 10m | 3.1 | Screen state |
| 3.4 | Wrap ghostty_parser_* (init, next, deinit) | 10m | 3.1 | Raw parser access |
| 3.5 | Wrap ghostty_key_encoder_* (encode key events) | 10m | 3.1 | Input encoding |
| 3.6 | Wrap ghostty_wasm_* (alloc, free, type_json) | 10m | 3.1 | WASM helpers |
| 3.7 | Add safe Rust types (Terminal, Screen, Parser) | 10m | 3.2-3.6 | RAII wrappers |
| 3.8 | Write integration tests: parse VT -> read screen | 10m | 3.7 | End-to-end proof |
| 3.9 | Write integration tests: encode key -> parse output | 10m | 3.7 | Round-trip proof |
| 3.10 | Publish crate metadata (Cargo.toml, README) | 10m | 3.8-3.9 | Packaging |

---

## G4: Embedding SDK — WASM Bridge (NOT STARTED)

Target: a JavaScript/TypeScript wrapper that loads ghostty-vt.wasm and exposes
a clean API for browser and Node.js environments.

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 4.1 | Audit upstream wasm-vt example (HTML/JS) | 10m | G1 | Already exists |
| 4.2 | Audit upstream wasm-key-encode example | 10m | G1 | Already exists |
| 4.3 | Audit upstream wasm-sgr example | 10m | G1 | Already exists |
| 4.4 | Extract JS wrapper from examples into module | 10m | 4.1-4.3 | Reusable lib |
| 4.5 | Add TypeScript types for WASM exports | 10m | 4.4 | Type safety |
| 4.6 | Write Node.js integration test (no browser) | 10m | 4.4 | CI-friendly |
| 4.7 | Write browser integration test (Playwright) | 10m | 4.4 | Visual proof |
| 4.8 | Package as npm module (ghostty-vt-wasm) | 10m | 4.5-4.7 | Distribution |
| 4.9 | Benchmark: WASM parse vs native parse | 10m | 4.6 | Performance delta |
| 4.10 | Document embedding guide (README) | 10m | 4.8 | Usage docs |

---

## G5: Comparative Benchmarks (NOT STARTED)

The dossier requires comparative metrics. Upstream already has `src/benchmark/`.

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 5.1 | Run upstream Zig benchmarks (baseline) | 10m | G0 | Parser, stream, screen |
| 5.2 | Run benchmarks on Khostty WASM build | 10m | G4 | WASM overhead |
| 5.3 | Run benchmarks on WezTerm (if available) | 10m | G1 | Competitor |
| 5.4 | Run benchmarks on Kitty (if available) | 10m | G1 | Competitor |
| 5.5 | Build comparison table (correctness, latency, memory) | 10m | 5.1-5.4 | Dossier requirement |
| 5.6 | Document benchmark methodology | 10m | 5.5 | Reproducibility |
| 5.7 | Commit results to session docs | 10m | 5.6 | Evidence trail |

---

## G6: Khostty-Specific Improvements (NOT STARTED)

The fork must prove "a specific embedding/workflow improvement." These are candidates
that upstream does NOT have.

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 6.1 | Design: agent-side terminal state tracking API | 10m | G3 | Novel feature |
| 6.2 | Implement: TerminalSnapshot (serialize state to JSON) | 10m | 6.1 | Core improvement |
| 6.3 | Implement: TerminalReplay (replay VT captures) | 10m | 6.1 | Debug tooling |
| 6.4 | Implement: DiffEngine (compare two terminal states) | 10m | 6.2 | Change detection |
| 6.5 | Write tests for snapshot/replay/diff | 10m | 6.2-6.4 | Correctness |
| 6.6 | Write integration: capture VT -> snapshot -> diff | 10m | 6.5 | End-to-end |
| 6.7 | Package as standalone tool (khostty-snapshot CLI) | 10m | 6.6 | Usable artifact |
| 6.8 | Document the improvement with before/after examples | 10m | 6.7 | Dossier proof |
| 6.9 | Comparative: Khostty snapshot vs upstream (N/A) | 10m | 6.8 | Shows novelty |
| 6.10 | Commit with session docs | 10m | 6.9 | Evidence |

---

## G7: Documentation & Polish (NOT STARTED)

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 7.1 | Write Khostty README with build instructions | 10m | G0 | Per-fork branding |
| 7.2 | Write embedding guide (Rust) | 10m | G3 | Developer docs |
| 7.3 | Write embedding guide (WASM/JS) | 10m | G4 | Developer docs |
| 7.4 | Write conformance report | 10m | G2 | Quality evidence |
| 7.5 | Write benchmark report | 10m | G5 | Comparison evidence |
| 7.6 | Update first-handoff with all results | 10m | G2-G6 | Living doc |
| 7.7 | Create Khostty changelog (fork-specific) | 10m | All | Release notes |
| 7.8 | Final session overview update | 10m | All | Completion record |

---

## G8: Upstream Sync & Maintenance (NOT STARTED)

| ID | Task | Est | Depends | Notes |
|----|------|-----|---------|-------|
| 8.1 | Document rebase procedure | 10m | G0 | Ops runbook |
| 8.2 | Set up upstream remote tracking | 10m | G0 | Git config |
| 8.3 | Test rebase on next upstream release | 10m | 8.1-8.2 | Validation |
| 8.4 | Create sync CI step (check upstream delta) | 10m | 8.3 | Automation |

---

## Critical Path

```
G0 (done) -> G1 (done) -> G2 (conformance) -> G5 (benchmarks) -> G7 (docs)
                       \-> G3 (Rust FFI)   -> G4 (WASM bridge) -> G6 (improvements) -> G7
```

## Summary

| Gate | Tasks | Est Total | Status |
|------|-------|-----------|--------|
| G0 Fork Hygiene | 4 | 40m | DONE |
| G1 Native Build | 3 | 30m | DONE |
| G2 Conformance | 10 | 100m | NOT STARTED |
| G3 Rust FFI | 10 | 100m | NOT STARTED |
| G4 WASM Bridge | 10 | 100m | NOT STARTED |
| G5 Benchmarks | 7 | 70m | NOT STARTED |
| G6 Improvements | 10 | 100m | NOT STARTED |
| G7 Documentation | 8 | 80m | NOT STARTED |
| G8 Upstream Sync | 4 | 40m | NOT STARTED |
| **TOTAL** | **66** | **660m (~11h)** | **70m done, 590m remaining** |
