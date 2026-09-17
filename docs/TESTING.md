# Testing

**Observed:** 2026-09-17 · How to verify Khostty, what each suite actually proves,
and how test results map onto the Deep WBS gates.

A test count is not coverage. A green run is not a fresh run. Every result in this
document carries the date it was observed.

---

## 1. Test inventory

| Suite | Command | Scope | Cases | Status |
|---|---|---|---|---|
| **Conformance** | `conformance/build.sh` | VT/ANSI behaviour via the C library | **84** | **PASSED 2026-09-17** |
| Zig unit tests | `zig build test` | Upstream core (289 files contain tests) | many | Not run in this session |
| libghostty-vt tests | `zig build test-lib-vt` | The C library's own tests | — | Not run in this session |
| ABI type manifest | `zig build test-lib-vt-schema` | The type manifest the wrappers consume | — | Not run in this session |
| Rust integration | `cd khostty-vt && cargo test` | Safe wrappers against the real library | — | Not run in this session |
| Rust ABI layout | `cd khostty-vt && cargo test` (`tests/abi_layout.rs`) | Struct layout vs the manifest | — | Not run in this session |
| Rust FFI drift | `cargo test --features bindgen` | Hand-written bindings vs bindgen output | — | Requires libclang |
| WASM runtime + ABI | `cd wasm && npm test` | JS API against the built `.wasm` | 52 | Not run in this session |
| WASM header sync | `cd wasm && npm run test:header` | Consolidated header vs real headers | — | Not run in this session |
| WASM types | `cd wasm && npm run typecheck` | `.d.ts` covers the real surface | — | Not run in this session |
| Fuzz corpus | `test/fuzz-libghostty/` | Parser crash-freedom (AFL++) | 4,002 seed files | Not run in this session |
| Benchmarks | *(none)* | Throughput / latency vs upstream | — | **G8 NOT STARTED** |

`bench/` does not exist. `-Demit-bench` builds **upstream's** bench tooling and is
not the G8 deliverable; do not cite it as benchmark evidence.

---

## 2. Conformance suite (the primary gate)

`conformance/` is the G2 evidence. It validates that the VT library preserves
expected terminal behaviour across a curated corpus.

### Running it

Build the library first — the harness links the prebuilt artifact.

```bash
zig build -Demit-lib-vt -Doptimize=ReleaseSafe

conformance/build.sh           # build and run
conformance/build.sh build     # build only
conformance/build.sh run       # run only (assumes build done)
```

What the script does:

1. Requires `zig-out/lib/libghostty-vt.dylib`; exits with a clear error if absent.
2. Locates the macOS SDK (`SDK` env var overrides; falls back to the newest
   `MacOSX2*.sdk`, excluding 27).
3. Compiles `conformance/harness.c` with `cc -Iinclude -O2`.
4. Runs `zig-out/bin/conformance_test` with `DYLD_LIBRARY_PATH=zig-out/lib`.

### Coverage

84 cases across 8 categories:

| Category | Cases | Focus |
|---|---:|---|
| `sgr` | 17 | bold/dim/italic/underline/blink/reverse/strike; RGB; 256-colour; combined; resets |
| `cursor` | 10 | up/down/left/right; CUP; home; DECSC/DECRC; default-parameter CSI |
| `osc` | 9 | OSC 0/2 title; OSC 10/11/12 colours; OSC 7 cwd; OSC 8 hyperlinks; OSC 52 clipboard |
| `charset` | 8 | SCS G0/G1 (UK, US, line-drawing, British); SS2/SS3; locking shifts |
| `mode` | 12 | DECCKM, DECOM, DECSCNM, DECAWM, DECTCEM, DECARM, and others |
| `scroll` | 7 | DECSTBM margins; IND/RI; SU/SD |
| `kitty-gfx` | 5 | APC init/progress/end/reset/transparency |
| `edge` | 16 | incomplete escapes, invalid params, unicode, wide chars, CR/LF, bell, BS, DEL |
| **Total** | **84** | |

### Methodology

Each case performs the same five steps:

1. **Reset** via `ghostty_terminal_reset()`.
2. **Resize** to a deterministic 80×24 via `ghostty_terminal_resize()`.
3. **Feed** the VT input via `ghostty_terminal_vt_write()`.
4. **Snapshot** the rendered text via the formatter API
   (`ghostty_formatter_terminal_new` + `ghostty_formatter_format`) with a
   growable-buffer writer callback.
5. **Compare** against the expected plaintext literal.

Non-textual cases (mode toggles, OSC side effects) pass when the call returns
without crashing; their expected plaintext is empty.

**Why the formatter and not a grid walk?** The formatter is the same code path
Ghostty uses to copy terminal content to the clipboard, so it exercises the read
path real applications hit. It also keeps failure modes narrow: a failure means
either a parser bug (wrong text) or a render bug (wrong whitespace/cursor
placement), not a fragile grid-walk mismatch.

**Why C and not Zig?** The Zig harness needs `zig-pkg/` populated from
`deps.files.ghostty.org`, and that fetch can fail for packages the C harness does
not need. Linking the already-built dylib sidesteps the dependency fetcher.

### Source of truth and duplication

`conformance/cases/<category>/cases.zig` holds the human-readable vectors.
`harness.c` holds a parallel copy as string literals. **The two must stay
byte-identical.** This duplication is deliberate (the Zig files document intent;
the C harness runs without the Zig dependency graph) but it is a real maintenance
hazard: changing a vector means changing both files.

### Adding a case

1. Add a `Test` entry to the relevant `cases/<category>/cases.zig`.
2. Mirror the same input and expected output in the matching `*_CASES[]` array in
   `harness.c`.
3. Run `conformance/build.sh`. The new case appears in the per-category report.

For a new category, also wire it into `run_category(...)` in `main()` and update
`g_cat_names[]` / `CAT_COUNT`.

### Known coverage gaps

Declared in `conformance/README.md` rather than discovered later:

- **Sixel and iTerm2 image protocols** — out of scope for G2.
- **DEC mode 2027 (grapheme cluster mode)** — covered in upstream tests, not ported here.
- **Wide-character visual placement** — only text content is checked, not cell placement.
- **Snapshots** — exercised separately by the upstream `c-vt-snapshot` example.
- **Kitty keyboard protocol encoding** — exercised by `c-vt-encode-key`.

Each maps to a G8 or G3 task.

### Verified result

Observed **2026-09-17**, against `zig-out/lib/libghostty-vt.dylib` built
2026-09-16 16:46:

```
Passed: 84
Failed: 0
Total:  84
Success Rate: 100%

--- Per Category ---
  sgr        17/17 (100%)
  cursor     10/10 (100%)
  osc        9/9 (100%)
  charset    8/8 (100%)
  mode       12/12 (100%)
  scroll     7/7 (100%)
  kitty-gfx  5/5 (100%)
  edge       16/16 (100%)
```

This satisfies the G2 acceptance criteria: 84/84 corpus cases pass, no crash, and
a per-category matrix is recorded.

---

## 3. Zig test suite

```bash
zig build test                              # everything (slow)
zig build test -Dtest-filter='terminal'     # targeted; strongly preferred
```

`-Dtest-filter` exists because the full suite is slow. Prefer it while iterating;
run the full suite before claiming completion.

If you changed a `libghostty-vt` file, use the library-scoped steps:

| Step | Purpose |
|---|---|
| `zig build test-lib-vt` | Run the library's tests |
| `zig build test-lib-vt-build` | Compile them without running (fast signal) |
| `zig build test-lib-vt-schema` | Validate the ABI type manifest |
| `zig build test-valgrind` | Run tests under Valgrind (requires Valgrind) |

`valgrind.supp` at the repository root supplies the suppression list.

Approximately 289 Zig source files contain `test "..."` blocks.

---

## 4. Rust crate

```bash
cd khostty-vt
cargo test
cargo clippy --all-targets
cargo fmt --check
```

Integration tests are gated on the `ghostty_vt_linked` cfg, which `build.rs` sets
only when it actually located a prebuilt `libghostty-vt`. Without one, the files
compile to nothing rather than failing at link time. `cargo check
--no-default-features` typechecks without the native library.

### ABI layout guard

`tests/abi_layout.rs` asserts the crate's declared struct layout against the
library's `ghostty_type_json()` manifest. `tests/abi_layout.txt` is the recorded
expectation; `tools/dump_abi_layout.py` regenerates it.

This test is the reason the crate can use a checked-in `src/ffi.rs` instead of
running bindgen on every build. If a C struct changes, this fails loudly rather
than corrupting memory silently.

### FFI drift check

```bash
cargo test --features bindgen
```

Regenerates bindings into `$OUT_DIR/bindings.rs` from the C headers and compares
them against `src/ffi.rs`. Requires libclang, which is why the feature is off by
default.

---

## 5. WASM package

```bash
cd wasm
./build.sh                    # produce khostty-vt.wasm (needed first)
npm run test:header           # consolidated header in sync and compiles
npm test                      # 52 runtime + ABI tests
npm run typecheck             # tsc --strict over declarations + type test
npm run exports               # dump import/export sections
npm run check                 # all of the above
```

No npm dependencies. The runtime tests use `node:test`; the wasm section parser is
written from the binary-format spec; `typecheck` fetches TypeScript on demand.

### What each test proves

| Test | Proves |
|---|---|
| `test/smoke.test.mjs` | The object model works end to end: write, read text/html, snapshot, search |
| `test/abi-exports.test.mjs` | The exported function set equals the consolidated header minus an explicit reasoned list (currently only the 16 `ghostty_kitty_graphics_*`) |
| `test/types.test-d.ts` | Every declared method is visible to a strict-mode TypeScript consumer |
| `test:header` | Regenerating the consolidated header changes nothing, it compiles under clang and `zig cc`, and its function set matches the union of the real headers (203 functions) |

Because the module is freestanding and the bindings are plain ESM, Node exercises
the same code path a browser would. There is no jsdom or headless-browser
dependency — and correspondingly, **no browser was actually exercised**. That is a
real gap for the G7 "browser smoke test" criterion.

### Runtime limits to test around

- Kitty graphics is excluded on freestanding targets; sequences are parsed and
  safely ignored.
- No PTY, filesystem, timestamps, or clock.

---

## 6. Fuzz corpus

`test/fuzz-libghostty/` runs [AFL++](https://aflplus.plus/) harnesses against
three targets:

| Target | Binary | Coverage |
|---|---|---|
| `osc` | `fuzz-osc` | OSC parser with allocator; seeds cover OSC 52, 66, 133, 3008, 1337, 5522 |
| `parser` | `fuzz-parser` | VT parser only, byte at a time |
| `stream` | `fuzz-stream` | Full terminal stream through the readonly handler |

4,002 seed files are present in `corpus/`. `replay-crashes.nu` replays recorded
crashes. G2's acceptance criterion is "fuzz corpus produces zero new crashes" —
that requires running the harness, which was not done in this session.

---

## 7. The WBS gate structure

Tests exist to close gates, not for their own sake. Each gate has its own
acceptance criteria and its own evidence.

| Gate | Objective | Primary evidence | Status (2026-09-17) |
|---|---|---|---|
| G0 | Fork hygiene | CI present and fork-appropriate | DONE |
| G1 | Native build validation | Artifacts produced (static, shared, xcframework, wasm) | DONE |
| G2 | Conformance evidence | 84/84 conformance pass, dated | **DONE** |
| G3 | Windows app runtime | Cross-compile + run on Windows/Wine | IN PROGRESS (scaffold only) |
| G4 | Agent/IPC surface | Pane commands + concurrency test + auth | IN PROGRESS |
| G5 | Rust FFI | `cargo test` green, RAII wrappers, clippy clean | IN PROGRESS |
| G6 | Go + Python FFI | `go test ./...`, `pytest` | IN PROGRESS (Go present, no Python) |
| G7 | WASM cross-compilation | WASM builds, JS API works, browser smoke test | IN PROGRESS |
| G8 | Improvements + benchmarks | Benchmark JSON + `bench/results/` with date | NOT STARTED |
| G9 | Docs + packaging | Docs committed, installers verified | IN PROGRESS |
| G10 | Release artifacts | Tagged release, checksums, smoke tests | NOT STARTED |

### Gate-closing rules

1. **Acceptance criteria are the definition.** A gate is not closed because its
   code is written; it is closed when every listed criterion has been observed.
2. **Re-run before you rely.** G2's 84/84 is a pass for the library built
   2026-09-16. Change the parser and that pass is void until re-run.
3. **Record the date and the machine.** The WBS requires benchmark results to
   carry a date and machine spec for exactly this reason.
4. **Unknown is a valid answer.** "Not run in this session" is honest; an inferred
   pass is not.
5. **Package ≠ pass.** A clean `git status` is not readiness; a build exit code is
   not a passing scenario.

---

## 8. Recording results

Where evidence goes:

| Evidence | Location |
|---|---|
| Gate pass/fail matrix | `docs/sessions/<date>-<name>/` |
| Conformance run output | The session folder, with the library build timestamp |
| Benchmark JSON + report | `bench/results/` (once G8 exists) |
| Claimed status in `docs/` | An `Observed: <date>` line at the top of the doc |

Rules:

- Never retroactively date a result. The observation date is when it was run.
- Never upgrade a historical pass to a fresh one. Re-run, or label it historical.
- Include the command, not just the outcome.
- If a suite could not be run, say so and why. `docs/BUILD.md` is the escalation
  path for environment problems.

---

## 9. Verified results log

| Date | Check | Result | Notes |
|---|---|---|---|
| 2026-09-17 | `conformance/build.sh run` | **PASS** 84/84, 100% | Against the dylib built 2026-09-16 16:46 |
| 2026-09-17 | `zig build -Demit-lib-vt` (repo cache) | **FAIL** | Stale build runner, `uucode` `FileNotFound` |
| 2026-09-17 | `zig build -Demit-lib-vt` (fresh cache), working tree | **FAIL** | Unhandled `Runtime.windows` arm in `src/build/SharedDeps.zig` |
| 2026-09-17 | `zig build -Demit-lib-vt`, detached worktree at `a4bf9e98f` | **FAIL** | `src/apprt/ipc/mod.zig` relative imports resolve to missing files; 50/64 steps succeeded, 2 compile errors |
| 2026-09-17 | WASM artifact | Present | 813,670 bytes, sha256 `08ac8ed8…`, mtime 2026-09-16 04:35 |
| 2026-09-17 | `cargo test`, `npm run check`, `zig build test` | **NOT RUN** | Not executed in this session |

### Consequence for this document

**No suite can be re-run from source until the build blocker is fixed.** The
conformance pass above is valid for the 2026-09-16 library and cannot currently be
reproduced from a fresh build, because `zig build -Demit-lib-vt` fails.

The blocker is a two-line fix in `src/apprt/ipc/mod.zig`, caused by commit
`e1277bea2` renaming `src/apprt/ipc.zig` into a directory without updating relative
imports. Full diagnosis and the exact fix are in
[BUILD.md](BUILD.md#unable-to-load-mainzig-filenotfound--unable-to-load-quirkszig).

Related: the working tree also fails earlier, at build-graph construction, because
`Runtime.windows` was added without updating the exhaustive switch in
`src/build/SharedDeps.zig`. See
[BUILD.md](BUILD.md#switch-must-handle-all-possibilities--unhandled-enumeration-value).

Because `src/` is outside this documentation change's authorised scope and is under
active concurrent edit, both defects are reported rather than fixed here.

---

## See also

- [BUILD.md](BUILD.md) — producing the artifacts these suites consume
- [PLATFORMS.md](PLATFORMS.md) — which platforms have verified results
- [CONFORMANCE detail](../conformance/README.md) — the corpus's own README
- [CONTRIBUTING.md](CONTRIBUTING.md) — which suite to run for a given change
- Deep WBS: [`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](sessions/20260916-fork-assessment/02_DEEP_WBS.md)
