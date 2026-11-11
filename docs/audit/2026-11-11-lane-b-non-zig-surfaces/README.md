# Lane B — non-Zig test surfaces in khostty

> **Provenance.** Written 2026-11-10/11 as a read-only audit against `HEAD` `9f3e31fa2`; preserved
> here so it survives its original scratch directory. Measurements were taken against that tree, so
> line numbers are those of `9f3e31fa2`, not of current `main`. The two CI fixes it produced are
> already merged: PR #99 (`26635b6f9`, the Rust gate) and the `example/` harness wiring that shipped
> with `#100`/`#98`. Section 11 records what changed when those gates were made real. Paths
> under `/Users/...` and `~/CodeProjects/...` are the audit host's, quoted verbatim where they
> were part of the command that produced the evidence.

Repo: `/Users/kooshapari/CodeProjects/Phenotype/repos/khostty` (fork of ghostty).
Method: static reading only — grep / sed / awk / python parsing of source. **No builds, no test
executions, no network.** Every claim carries `file:line`, or the exact command run plus its
result. Where a fact could not be established by reading, it is marked **UNKNOWN** with the
command that would settle it.

**Tree state these counts were taken against:** `HEAD` = `9f3e31fa2` on branch
`test/ipc-task-state-machine`, with exactly **one dirty file for the whole audit**:
`src/apprt/ipc/task.zig` (+42 lines, 3 new `test` declarations, mtime 03:20, authored by the
concurrent IPC-coverage lane, not this one). Every non-Zig figure below was measured in `tests/`,
`khostty-vt/`, `khostty-go/`, `conformance/`, `wasm/`, `example/` and the workflow files, none of
which is dirty, so those counts are exact for this tree. The Zig-corpus column in section 8 is
quoted from other lanes and may be off by those 3 declarations.

## Summary

| Surface                            | Files                        | Cases                                                                                                           | Tier                                |
| ---------------------------------- | ---------------------------- | --------------------------------------------------------------------------------------------------------------- | ----------------------------------- |
| Python `khostty-python/tests`      | 8 tests + `conftest.py`      | **124** functions = **162** collected cases                                                                     | integration (in-process FFI)        |
| Rust `khostty-vt`                  | 9 in `tests/` + 23 in `src/` | **199** (195 `#[test]` + 4 doc-tests)                                                                           | unit + integration (in-process FFI) |
| Go `khostty-go`                    | 11 `*_test.go`               | **45** functions = **70** cases                                                                                 | integration (linked DLL/dylib)      |
| `conformance/`                     | `harness.c` only             | **84** (57 assert nothing, 34 of them structurally)                                                             | conformance                         |
| `wasm/test`                        | 2 `.mjs`                     | **54**                                                                                                          | integration (in-process wasm)       |
| `example/`                         | 35 dirs                      | 16 of 27 C mains use `assert(...)`; **1 of 27 executed in CI** (`test.yml:998`, exit code printed not asserted) | build verification                  |
| Root `Makefile` / `CMakeLists.txt` | —                            | **ZERO TESTS**                                                                                                  | —                                   |

### Counting units — read this before comparing surfaces

The `Cases` column is not one unit. Counted two ways, as bare definitions and as cases the runner
would actually collect, **two surfaces expand**:

| Surface     | Definitions                 | Collected cases | Why they differ                                                                                                                               |
| ----------- | --------------------------- | --------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------- |
| Python      | 124 `def test_`             | **162**         | 10 `@pytest.mark.parametrize` decorators turn 10 functions into 38 extra cases; one list is a module constant (`ROUND_TRIP_CASES`, 5 entries) |
| Rust        | 195 `#[test]` + 4 doc-tests | **199**         | no `#[test]` inside a loop or macro; the 4 doc-tests are the `//!` code blocks in `src/lib.rs`                                                |
| Go          | 45 `func Test`              | **70**          | 5 table-driven functions wrap `t.Run` in `for _, tc := range cases`, adding 30 subtests                                                       |
| conformance | 84 struct entries           | **84**          | static C array (`harness.c:80-160`)                                                                                                           |
| wasm        | 54 `test(` blocks           | **54**          | no generator: `grep -cE 'test\.each                                                                                                           | forEach' wasm/test/\*.mjs` -> 0 |

So the honest cross-surface comparison in case units is **162 / 199 / 70 / 84 / 54**, not
124/199/45/84/54. Python was measured by an `ast` walk that multiplies the length of each
`parametrize` positional list per function (no `argvalues=` keyword form is used anywhere in the
suite, so the positional walk is complete): `test_key.py` 18 defs -> 35 cases, `test_mouse.py`
19 -> 29, `test_terminal.py` 30 -> 33, `test_formatter.py` 14 -> 16, `test_snapshot.py` 8 -> 13,
`test_examples.py` 3 -> 4, `test_ffi.py` 16 -> 16, `test_search.py` 16 -> 16. Go by a tab-aware awk
over each `cases := []struct` block (`ghostty_key_test.go:81` 13 cases,
`ghostty_snapshot_test.go:12` 4, `ghostty_mouse_test.go:34` 5, `:67` 3, `:121` 5); one further table
block, `ghostty_vt_test.go:187-197` (4 inline rows), has no `t.Run`, so it stays a single Go case
with 4 internal checks.

_Method warning, learned the hard way:_ the first Go attempt returned **0 cases for all five
blocks**. BSD `awk` does not interpret `\t` inside a regex, so `/^\t\t\{/` was really matching
`^tt{`, and the table entries are two tabs deep. Passing a literal tab through `-v` fixed it. A zero
that arrives without a positive control — "does this pattern match something I can see by eye in
that file?" — is not a measurement.

**True e2e (launches a real app, or talks to a real socket): NONE among the six audited surfaces,
with one process-boundary exception inside Python.** All five real surfaces drive an in-process
`libghostty-vt` (C ABI, wasm module, or Rust/cgo wrappers). None spawns a terminal binary or an IPC
peer. The exception is `khostty-python/tests/test_examples.py`, which runs the shipped Python
examples in **subprocesses** and asserts on their exit code and stdout (`test_examples.py:21-31`,
`:40-58`); it is a real process boundary and it sits inside the hard-gated pytest job, but what it
spawns is a Python interpreter running an example, not a terminal emulator or an external program
under a PTY. The repo's only fork/exec/PTY harness is out-of-lane `test/esctest`
(`test/esctest/src/main.zig:67,74,81`), so the "no PTY" result is a property of these six surfaces,
not of the repository. See sections 1 and 7.

## 1. `khostty-python/tests` — Python, 124 functions / 162 collected cases

### Files and per-file test counts

Counted with `grep -c "def test_" <file>` and `wc -l <file>`:

| File                                     | Lines    | `def test_`  |
| ---------------------------------------- | -------- | ------------ |
| `khostty-python/tests/test_terminal.py`  | 340      | 30           |
| `khostty-python/tests/test_mouse.py`     | 322      | 19           |
| `khostty-python/tests/test_key.py`       | 367      | 18           |
| `khostty-python/tests/test_search.py`    | 195      | 16           |
| `khostty-python/tests/test_ffi.py`       | 163      | 16           |
| `khostty-python/tests/test_formatter.py` | 155      | 14           |
| `khostty-python/tests/test_snapshot.py`  | 129      | 8            |
| `khostty-python/tests/test_examples.py`  | 59       | 3            |
| `khostty-python/tests/conftest.py`       | 76       | 0 (fixtures) |
| **Total**                                | **1806** | **124**      |

`conftest.py` is fixtures only: its `library` fixture (`khostty-python/tests/conftest.py:23`, session
scope) loads the real `libghostty-vt` shared object, and the module docstring states at `:4` that it
"therefore _fails_ the suite when no library can be found", so every one of the 124 tests is
an **integration** test against the native library, not a mocked unit test.

- **One file is not in-process at all, and it is the strongest check in this suite.**
  `test_examples.py` (59 lines, 3 functions / 4 cases) runs the shipped Python examples as **child
  processes**: `subprocess.run([sys.executable, str(EXAMPLES / name)], capture_output=True,
text=True, timeout=120, check=False)` (`test_examples.py:21-27`), then `assert result.returncode
== 0` (`:28-31`) and asserts on the child's stdout (`test_basic_example_runs` `:40-45`,
  `test_agent_example_runs` `:48-58`, 10 stdout assertions in total). Its own docstring states the
  intent (`:1-5`): "Smoke tests that run the shipped examples end to end … Each runs in a
  subprocess, which also proves the checkout bootstrap in them works without an install." The
  children are `khostty-python/examples/basic.py` (`from khostty_vt import ...` at `:28`) and
  `agent.py`, and both are inside the merge gate because CI runs `python -m pytest tests/ -q`
  (`ci.yml:340`). This is the only process boundary among the six audited surfaces.
- **Parametrized:** 10 `@pytest.mark.parametrize` decorators across 7 files mean the 124 functions
  collect as **162 cases** (`test_key.py` alone goes 18 -> 35). See "Counting units" above.
- **124 is scoped to `tests/` on purpose — a whole-directory grep returns 140.**
  `grep -rno 'def test_' khostty-python --include='*.py' | wc -l` -> **140**, of which **16** are
  inside `khostty-python/.venv-gate/` (a real `uv` virtualenv: `pyvenv.cfg` says `uv = 0.11.29`),
  i.e. vendored `_pytest` source plus one comment showing the pattern `#   def test_foo(x, y): pass`
  in `_pytest/mark/structures.py:172`. Pytest collects none of it, because
  `pyproject.toml:71` declares `testpaths = ["tests"]`. Anyone re-running this audit should expect
  140 from a naive grep and 124 from the real surface.

### How they are run

- Pytest config: `khostty-python/pyproject.toml:70` `[tool.pytest.ini_options]`,
  `khostty-python/pyproject.toml:71` `testpaths = ["tests"]`.
- Test dependency is an optional extra, not a default:
  `khostty-python/pyproject.toml:23` `test = ["pytest>=7"]` (runtime dep `cffi>=1.15` at line 20;
  interpreter floor `requires-python = ">=3.8"` at line 10).
- `khostty-python/requirements-ci.txt` exists for the CI environment.
- CI job: the blocking job is `.github/workflows/ci.yml:286` (`pytest:`, "Python Tests"), whose
  run step is `:340` — `working-directory: khostty-python` then `run: python -m pytest tests/ -q`.
  So `python -m pytest tests/ -q` inside `khostty-python/` is the runner command. Note the separate
  `python:` job at `ci.yml:268` is **advisory** (`continue-on-error: true`, `:273`) and only runs
  ruff; the tests live in the `pytest:` job, which carries no such escape hatch.

### Tier

**Integration.** Tests import the cffi bindings and drive the native VT library in-process; they
cross the Python/C boundary but launch no application and open no socket.

## 2. `khostty-vt` — Rust, 199 cases (195 `#[test]` + 4 doc-tests)

### Layout: one crate, unit + integration split

- Exactly one `Cargo.toml` in the crate: `khostty-vt/Cargo.toml`, 50 lines.
  `name = "khostty-vt"` (:2), `[lib]` (:15) with `name = "khostty_vt"` (:16) and
  `path = "src/lib.rs"` (:17), `[dependencies]` (:33) and `[dev-dependencies]` (:35) are both
  **empty** — the crate is a hand-written FFI wrapper with no third-party deps.
- `build.rs` present. `[features]` (:19) sets `default = ["link"]` (:20) to emit linker directives
  for a prebuilt `libghostty-vt`; `--no-default-features` typechecks without the native library.
  The opt-in `bindgen` feature (:28) regenerates bindings and cross-checks them against the
  checked-in `src/ffi.rs`.
- `[[example]]` (:40) `name = "screen_dump"` (:41) and `[[example]]` (:44)
  `name = "agent_session"` (:45), both `required-features = ["link"]`, bodies gated on the
  `ghostty_vt_linked` cfg that `build.rs` sets only when a prebuilt library was actually found.
- Because the default feature links the native lib, most of the suite is gated: **7 of the 9**
  integration files open with `#![cfg(ghostty_vt_linked)]` — `end_to_end.rs:17`, `key_encoding.rs:5`,
  `mouse_encoding.rs:9`, `render.rs:5`, `search.rs:5`, `snapshot.rs:5`, `terminal.rs:9`. Without a
  built `libghostty-vt` those compile to nothing and silently pass as 0 tests.
- **The other 2 files are ungated**, and that is the good news in this section: `ffi_coverage.rs`
  (5 tests) and `abi_layout.rs` (4 tests) carry no `#![...]` attribute at all
  (`grep -n '^#!\[' ... ` -> no matches), so those 9 tests always run.

### Counts with `grep -c "#\[test\]"`

| Location                                             | Files  | `#[test]`                                     |
| ---------------------------------------------------- | ------ | --------------------------------------------- |
| `khostty-vt/tests/*.rs` (integration)                | 9      | 130                                           |
| `khostty-vt/src/**/*.rs` (unit, in-file `mod tests`) | 23     | 65                                            |
| **Total**                                            | **32** | **195 `#[test]`** (+ 4 doc-tests = 199 cases) |

Integration files with counts: `terminal.rs` 29, `snapshot.rs` 17, `mouse_encoding.rs` 16,
`render.rs` 16, `search.rs` 16, `key_encoding.rs` 14, `end_to_end.rs` 13, `ffi_coverage.rs` 5,
`abi_layout.rs` 4. Unit tests are concentrated in `src/error.rs` 9, `src/sys.rs` 9,
`src/mouse/types.rs` 7, `src/style.rs` 6, `src/key/types.rs` 5, `src/selection.rs` 5,
`src/snapshot/encode.rs` 5, `src/terminal/types.rs` 5, `src/color.rs` 4, and 3-1 each in
`render/*`, `search/types.rs`, `terminal/mod.rs`. Note `src/ffi.rs` (2127 lines) has 0 tests, and
`src/search/mod.rs` (489), `src/mouse/mod.rs` (318), `src/key/mod.rs` (351) have 0 in-file tests —
their coverage comes from `tests/`.

`tests/` is integration-only; there is **no `benches/` directory** (the two `[[example]]` targets
are demos, not benchmarks). No `#[tokio::test]` anywhere — the crate is synchronous.

### The one real golden fixture in the whole non-Zig surface

`khostty-vt/tests/abi_layout.txt` is a **42-line golden file**, generated by
`tools/dump_abi_layout.py` and compiled into the test binary via
`const ABI_SNAPSHOT: &str = include_str!("abi_layout.txt");` (`tests/abi_layout.rs:23`). It records
the observed size and alignment for every marshalled type, with provenance headers on lines 1-5
(generator, `observed: 2026-09-17T10:25:52Z`, the compiler string, the header root). The 4 tests in
that file re-derive the C-side numbers and compare, failing with
`"tests/abi_layout.txt and the MIRRORED table have drifted apart"` (`:290`) and reporting any type
missing from the fixture at `:265`.

This matters for the verdict: **the expected-output file that `conformance/` lacks, Rust already
has** — for ABI layout. It is a checked-in, drift-detecting snapshot, not an inline literal. So the
repository demonstrably knows how to express an expectation as a durable fixture; conformance just
does not do it.

`khostty-vt/tests/end_to_end.rs` is the file named like e2e. Its own header (doc comments, lines
1-15) defines its claim precisely: it composes the public surface (parse bytes -> render state ->
row/cell iteration -> snapshot -> search -> write-pty replies) and compares extracted text. That is
a **compositional integration test in-process**; it starts no application and opens no socket.

### How it is run in CI

- `.github/workflows/ci.yml:162-164` — the Rust job runs
  `cargo test --workspace --no-fail-fast 2>&1 || echo "::warning::test failures (advisory)"`, i.e.
  **advisory only**: a genuine test failure prints a warning and does not fail the workflow. The
  same job carries `continue-on-error: true` at `ci.yml:151`.
- The one _required_ Rust-adjacent gate is binding freshness:
  job `binding-freshness` (`ci.yml:181-182`), name "Rust binding freshness", with its step at
  `:195-199` running `python3 tools/gen_ffi.py --check`. A stale `src/ffi.rs` fails the build, but
  the 199 cases themselves are not a merge gate.
- **The Rust job has already been silently skipped in a shipped state.** `ci.yml:99-104` documents
  its own past bug: the detection step used `[ -f "**/Cargo.toml" ]`, a literal string test that
  `sh` never glob-expands, "so it never matched and the Rust job was silently skipped on every
  run". The current form is `find . -name Cargo.toml ... | head -1 | grep -q .` (`:103`), which
  matches `khostty-vt/Cargo.toml` in every checkout, so the job runs. This is a second, upstream-
  authored instance of the undetected-non-execution pattern this section is about, and it is why
  the `if: needs.detect.outputs.has_rust == 'true'` guard at `ci.yml:149` is not a path filter in
  practice: it is a whole-tree existence check that is always true.
- **The repository says so itself.** `ci.yml:167-188` is a maintainer comment on the
  `binding-freshness` job: "the `rust` job is `continue-on-error: true` and wraps `cargo test` in
  `|| echo "::warning::..."`, so a stale binding could not fail CI there - and it did not.
  khostty-vt 0.1.0 shipped with src/ffi.rs stale against include/: 198/179/794 versus 199/196/884
  after regeneration, with `ghostty_osc_set` (`include/ghostty/vt/osc.h:330`) absent entirely."
  That is an independently documented instance of this exact gate failing to catch a shipped defect,
  which is stronger evidence for the finding than any inference of mine.
- Consequence: **199 Rust cases exist and none of them block a merge.**

### Tier

**Unit (65) + integration (130).** Both link the native library in-process.

## 3. `khostty-go` — Go, 45 functions / 70 cases

Counted with `grep -cE "^func (Test|Benchmark|Example)"` per file and `wc -l`:

| File                                       | Lines    | Test funcs         |
| ------------------------------------------ | -------- | ------------------ |
| `khostty-go/ghostty_vt_test.go`            | 270      | 8                  |
| `khostty-go/ghostty_keyencoder_test.go`    | 349      | 6                  |
| `khostty-go/ghostty_key_test.go`           | 254      | 6                  |
| `khostty-go/ghostty_mouse_test.go`         | 179      | 5                  |
| `khostty-go/ghostty_search_test.go`        | 224      | 5                  |
| `khostty-go/ffi_test.go`                   | 171      | 4                  |
| `khostty-go/ghostty_render_test.go`        | 139      | 4                  |
| `khostty-go/ghostty_mouseevent_test.go`    | 225      | 4                  |
| `khostty-go/ghostty_snapshot_test.go`      | 132      | 3                  |
| `khostty-go/ghostty_test.go`               | 29       | 0 (package smoke)  |
| `khostty-go/ghostty_mouse_fixture_test.go` | 53       | 0 (fixture loader) |
| **Total**                                  | **2025** | **45**             |

Single `go.mod` at `khostty-go/go.mod`. The package is cgo bindings, so tests need a built
`libghostty-vt` DLL/dylib on the loader path.

### How it is run, and whether CI gates on it

- **Advisory:** `.github/workflows/ci.yml:357-358` runs `go test ./...` in `khostty-go` with a
  trailing `|| echo "::warning::test failures (advisory)"` — failures do not fail the workflow, and
  the job itself is `continue-on-error: true` at `:347`.
- **Required (Windows only):** `.github/workflows/go-windows.yml:59-63` runs
  `go test -count=1 -v ./...` in `khostty-go` after `. ./tools/windows-env.ps1`, with an explicit
  `if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }`. The same job builds the DLL first
  (`zig build -Demit-lib-vt -Doptimize=ReleaseFast`, :44-45) and runs `go build ./...` (:49-53) and
  `go vet ./...` (:55-58).
- Net: the Go suite is a hard gate **only on the Windows runner**; on Linux/macOS it is advisory.

### Tier

**Integration.** cgo calls into the real native library in-process. No subprocess, no socket.

## 4. `conformance/` — C harness, 84 cases

### What `conformance/build.sh` actually does (94 lines, read in full)

`build.sh` is a **build-and-exec wrapper, not a test definition**. It compiles
`conformance/harness.c` against the **prebuilt** `zig-out/lib/libghostty-vt.dylib` and emits
`zig-out/bin/conformance_test`, then optionally runs that binary. Its three modes are documented in
its own usage header: `build.sh` (build + run, the default), `build.sh build`, `build.sh run`.
**`build.sh` contains no assertions of its own** — searching it for expect/assert/diff returns
nothing. It never starts a terminal and never reads a recorded corpus file: the corpus is compiled
into `harness.c` as static arrays.

Mechanics, with line numbers: platform branch `uname -s` at `build.sh:23-61` (Darwin -> dylib +
`DYLD_LIBRARY_PATH` + `-isysroot` from a MacOSX2x SDK, Linux -> `.so` + `LD_LIBRARY_PATH`);
missing-library fallback glob at `:65-78`; the single compile+link is `:84-87`
(`cc -I include -O2 [isysroot] conformance/harness.c $LIB_PATH -o zig-out/bin/conformance_test`);
run is gated by `if [[ "${1:-run}" == "run" ]]` at `:91-94`.

**Documented mode semantics are wrong.** The usage header (`build.sh:15-17`) says
`build.sh run # run only (assumes build done)`, but the `cc` at `:84-87` is unconditional —
`build.sh run` recompiles the harness every time. The only difference between the modes is whether
the binary is executed afterwards. This matters for anyone trying to time or cache the run step.

### Where the corpus lives and its size

Cases are inline C initialisers, one `TestCase` struct per case, with an optional expected string
field declared at `conformance/harness.c:27`
(`const char *expected_plain; /* empty means no plaintext assertion */`).
Eight category arrays begin at `conformance/harness.c:47` (`SGR_CASES`), `:67` (`CURSOR_CASES`),
`:80` (`OSC_CASES`), `:93` (`CHARSET_CASES`), `:104` (`MODE_CASES`), `:119` (`SCROLL_CASES`),
`:132` (`KITTY_CASES`), `:141` (`EDGE_CASES`). Note the array is `KITTY_CASES`, not
`KITTY_GFX_CASES`, while its directory is `conformance/cases/kitty-gfx/`.

Counted with an awk scan of each `*_CASES[]` initialiser:

| Category  | Cases  |
| --------- | ------ |
| SGR       | 17     |
| CURSOR    | 10     |
| OSC       | 9      |
| CHARSET   | 8      |
| MODE      | 12     |
| SCROLL    | 7      |
| KITTY     | 5      |
| EDGE      | 16     |
| **Total** | **84** |

These per-category numbers match the documented counts in `conformance/README.md:19-26`
exactly, which is a useful cross-check that no array has drifted.

### What `conformance/build.sh run` actually ASSERTS

The work is done by `run_category()` at `conformance/harness.c:187`. Per case it:

1. Resets the terminal and resizes it to 80x24 (`harness.c:192-194`) — a fixed default geometry, so
   any scrolling/margin case inherits 80x24 unless it resizes itself.
2. Feeds the case bytes with `ghostty_terminal_vt_write(...)` (`harness.c:196-197`). This is the
   only input path; there is no keystroke, no PTY, no key encoder.
3. **Gates the entire comparison on non-emptiness**: `if (strlen(tc->expected_plain) > 0) {`
   (`harness.c:201`). When the field is `""`, nothing is compared and `ok` stays true.
4. Inside the guard it formats the screen, fails if the formatter allocation fails
   (`harness.c:212-215`) or formatting returns non-success (`:221-224`), then compares length and
   bytes: `bw.len != strlen(tc->expected_plain) || memcmp(bw.data, tc->expected_plain, bw.len) != 0`
   (`harness.c:225-226`).
5. Counters `g_passed` / `g_failed` / `g_total` live at `harness.c:30-32`, with per-category copies
   at `harness.c:35-37`; `run_category` prints `--- %s Tests (%zu) ---` per category
   (`harness.c:187`+).
6. The process exit code is the verdict: `return (g_failed == 0) ? 0 : 1` (`harness.c:297`).

**This is the single most important quality finding of the lane.** Only 27 of the 84 cases carry a
non-empty `expected_plain`; the other **57 cases assert nothing beyond "did not crash"**.
Measured by counting the literal `, ""}` within each array body
(`awk` over `conformance/harness.c`, cases counted at each `^\s*{"` opener):

| Category  | Cases  | Crash-only | Content asserted |
| --------- | ------ | ---------- | ---------------- |
| SGR       | 17     | 1          | 16               |
| CURSOR    | 10     | 7          | 3                |
| OSC       | 9      | 9          | **0**            |
| CHARSET   | 8      | 8          | **0**            |
| MODE      | 12     | 12         | **0**            |
| SCROLL    | 7      | 2          | 5                |
| KITTY     | 5      | 5          | **0**            |
| EDGE      | 16     | 13         | 3                |
| **Total** | **84** | **57**     | **27**           |

```
$ awk '<per-array range scan of ^\s*{" openers and , ""} closers>' conformance/harness.c
TOTAL cases=84  crash_only=57  asserted=27
```

Four of the eight categories — **OSC, CHARSET, MODE and KITTY, 34 of the 84 cases** — assert nothing
at all. Every Kitty graphics case (`harness.c:133-138`: `kitty_init`, `kitty_progress`,
`kitty_end`, `kitty_reset`, `kitty_transparency`) checks only that feeding the sequence does not
crash. The one strongly-asserted category is SGR (16 of 17), because its cases are trivially
plain-text (`{"sgr_bold", ESC "[1mText", "Text"}` at `harness.c:49`).

So a green `conformance/build.sh run` means **27 real output comparisons plus 57 no-crash probes**,
not 84 verified behaviours. SGR attributes are additionally _not_ verified: the case struct has
only `expected_plain`, so bold/italic/underline/reverse outcomes are never compared
(`harness.c:27`) — `sgr_bold` and `sgr_dim` both expect the same `"Text"`.

_A prior line-based estimate in this report said 55/29; it missed multi-line case initialisers
(e.g. `harness.c:133-134`) and is superseded by the 57/27 table above._

**Independent per-array confirmation** (entry-buffering awk over `harness.c`, each `{...}` block
tested for an empty string field):

| array                   | cases  | empty  | asserted |
| ----------------------- | ------ | ------ | -------- |
| `SGR_CASES` (`:47`)     | 17     | 1      | 16       |
| `CURSOR_CASES` (`:67`)  | 10     | 7      | 3        |
| `OSC_CASES` (`:80`)     | 9      | **9**  | **0**    |
| `CHARSET_CASES` (`:93`) | 8      | **8**  | **0**    |
| `MODE_CASES` (`:104`)   | 12     | **12** | **0**    |
| `SCROLL_CASES` (`:119`) | 7      | 2      | 5        |
| `KITTY_CASES` (`:132`)  | 5      | **5**  | **0**    |
| `EDGE_CASES` (`:141`)   | 16     | 13     | 3        |
| **total**               | **84** | **57** | **27**   |

This reproduces all three headline numbers independently of the earlier scan: 84 cases, 57 empty,
27 asserted, and the four silent categories at exactly 9 + 8 + 12 + 5 = **34**.

**Confirmed by a second, structurally different implementation.** The table above came from a
line-buffered awk. A brace-balanced Python parse (isolate each `static const TestCase ...[] = {`
body, walk braces to split entries, take the _last_ string literal in each entry as
`expected_plain`) reproduces it exactly: SGR 17/1, CURSOR 10/7, OSC 9/9, CHARSET 8/8, MODE 12/12,
SCROLL 7/2, KITTY 5/5, EDGE 16/13 -> **84 / 57 / 27**. Two caveats, both of which nearly produced a
false alarm and are recorded so the next reader trusts the _method_, not a bare result:

- A first version of the Python parse reported **81 / 1 / 80** and looked like a serious
  disagreement. It was wrong: it required an entry to be on a single line, so the one multi-line
  entry (`osc_8_hyperlink_open`, `harness.c:87-88`) was silently dropped, and it read `strs[1]` as
  `expected_plain` when the input field is a _concatenation_ of adjacent literals (`ESC "..." "\x07"`),
  so the expected value is the **last** literal, not the second.
- A zero-row result must never be read as a clean result. The same trap fired twice more in this
  audit (an awk field split and a BSD `paste -sd+`). Both times the fix was to debug the parser, not
  to believe the number.

**The 27 assertions really can fail CI.** The full chain was traced end to end rather than inferred
from the `strlen` gate alone:

1. `harness.c:201` `if (strlen(tc->expected_plain) > 0)` selects an asserted case.
2. A formatter alloc failure prints `[FAIL]` and sets `ok = false` (`:212-215`).
3. A format failure does the same (`:221-224`).
4. A length mismatch or `memcmp` difference prints the expected/got pair and sets `ok = false`
   (`:225-226`).
5. `ok == false` increments `g_failed` (`:243`).
6. `main` returns `(g_failed == 0) ? 0 : 1` (`:297`).
7. `build.sh:20` is `set -euo pipefail` and the runner invocation is unguarded (`:91-94`), so a
   non-zero binary exit fails CI, and the `conformance` job has no `continue-on-error`.

So the 27 are genuine hard gates, and a wrong-but-non-crashing result in the other 57 is invisible
by construction: those cases can only fail by crashing the process. Also worth noting,
`run_category` is `static void` and tallies failures instead of returning early, so one mismatch
does not hide the ones after it.

### The real blocker: `""` is overloaded (this corrects the obvious reading)

It is tempting to read the 57 as "someone forgot to write the assertions". That is wrong, and a
delegated follow-up analysis (`lane-b2-conformance-assert-fill.md`, 34 cases checked case-by-case)
shows why: **for all 34 zero-assert cases in OSC/CHARSET/MODE/KITTY the correct plaintext is the
empty string**, because OSC payloads, charset designators, mode toggles and kitty graphics commands
are consumed by the parser and never rendered.

That companion file is a separate artifact and was **verified, not trusted**: all 34 case names were
checked mechanically against `harness.c`, and each cited `harness.c:<line>` was confirmed to hold the
case it points at (34 rows, 0 problems). It carries the per-case tables this report summarises
(input bytes, plaintext-assertable verdict, proposed C literal or required assertion type) in
`sections 2-5`, plus a defect list in `section 6` and the ranked fixes in `section 8`. Two of the
UNKNOWNs it declares are **now resolved here**: its `UNKNOWN 2` (whether the C API can read back
title/clipboard/pwd/mode/charset/kitty state) is answered by the API list below, and its `UNKNOWN 5`
(whether `ghostty_grid_ref_hyperlink_uri` is exported from `include/`) is answered yes, at
`include/ghostty/vt/grid_ref.h:187`.

So `""` means two incompatible things at once:

- "the terminal should print nothing" (a real assertion), and
- "we have no assertion" (the sentinel).

`harness.c:201` cannot distinguish them, so a case whose correct output _is_ empty can never be
asserted with this struct. `conformance/README.md:93-96` documents that as intended: "Cases that are
not textual ... pass unconditionally when the call returns without crashing; the expected plaintext
field is empty."

The minimum fix is structural, not per-case: make "assert empty" distinct from "no assertion"
(`expected_plain == NULL` vs `""`, or an `assert_kind` enum beside the payload).

### The typed expectations and the readback APIs both already exist

The C struct kept only `expected_plain`, but the Zig case files carry the typed expectations the
categories actually need:

| Zig file                                | typed expectation fields                                                     | lines  |
| --------------------------------------- | ---------------------------------------------------------------------------- | ------ |
| `conformance/cases/osc/cases.zig`       | `expected_title`, `expected_clipboard`, `expected_pwd`, `expected_hyperlink` | `:3-9` |
| `conformance/cases/charset/cases.zig`   | `expected_charset`                                                           | `:3-6` |
| `conformance/cases/mode/cases.zig`      | `expected_active_mode`, `expected_mode_reversed`                             | `:3-7` |
| `conformance/cases/kitty-gfx/cases.zig` | `expected_action`, `expected_uri`, `expected_width`, `expected_height`       | `:3-9` |

`conformance/README.md:145-146` requires these to be mirrored byte-identically into
`harness.c` — "Mirror the same input + expected in the `*_CASES[]` array ... Keep them byte-identical"
— a rule the C harness cannot satisfy because it has no field to mirror into.

Crucially, the C API needed to _observe_ those states is already exported, so this is not a
"blocked on upstream" problem:

- `ghostty_terminal_get()` (`include/ghostty/vt/terminal.h:3317`) supports querying a mode value
  (`GHOSTTY_TERMINAL_DATA_...` "Get the current value of a terminal mode",
  `include/ghostty/vt/terminal.h:2900`). That makes the **12 MODE cases assertable today**.
- `ghostty_grid_ref_hyperlink_uri()` (`include/ghostty/vt/grid_ref.h:187`) exposes the URI of a
  hyperlinked cell, making the **OSC 8 cases assertable today**.
- The standalone OSC parser API — `ghostty_osc_new` / `_set` / `_next` / `_end` / `_command_type` /
  `_command_data` (`include/ghostty/vt/osc.h:284-414`) — exposes
  `GHOSTTY_OSC_COMMAND_CHANGE_WINDOW_TITLE`, `..._CLIPBOARD_CONTENTS`, `..._REPORT_PWD`,
  `..._HYPERLINK_START/END` (`osc.h:113-123`) and `GHOSTTY_OSC_DATA_CHANGE_WINDOW_TITLE_STR`
  (`osc.h:230`). That makes the remaining **OSC cases assertable from a second parser instance**
  without needing terminal-level readback.
- **CHARSET: no readback accessor exists, but an indirect path does.** The entire public include tree
  contains exactly one `charset` reference, `include/ghostty/vt/formatter.h:61` — `bool charsets;`
  inside `GhosttyFormatterScreenExtra`, documented as "Emit character set designations and
  invocations" (`:59-60`). That is a formatter **emit** option, not a query. So the 8 CHARSET cases
  cannot be asserted from terminal state, and cannot be mirrored literally either: the Zig cases
  expect symbolic names (`expected_charset = "UK"` / `"US"`, `cases/charset/cases.zig:3-6,11-12`)
  that no C API returns. The workable route is to enable that formatter flag and assert the emitted
  designation bytes, which tests the round trip rather than the stored state.

### Full `conformance/` inventory (11 files, 1262 lines, ZERO fixture files)

| Path                                    | Lines     | Role                                           |
| --------------------------------------- | --------- | ---------------------------------------------- |
| `conformance/harness.c`                 | 297       | the entire runner **and** all 84 cases, inline |
| `conformance/README.md`                 | 185       | documents the corpus                           |
| `conformance/build.sh`                  | 94        | compile, link, run                             |
| `conformance/cases/<cat>/cases.zig` × 8 | 686 total | never compiled                                 |

Per-category Zig line counts: `sgr` 116, `cursor` 110, `mode` 101, `edge` 95, `osc` 93,
`scroll` 68, `kitty-gfx` 53, `charset` 50 (`297+185+94+686 = 1262`).

There are **no expected-output fixture files at all**: `find conformance -type f` returns exactly
11 files, none of them a `.txt`, `.expected`, or golden file. So "corpus files" and "expected
outputs" are not two directories here. The corpus is the 84 inline structs, and the expected values
are string literals inside them: 27 usable, 57 empty. Fixture count: **ZERO**.

### Ownership: the `.zig` case files are dead weight, and already drifted

`conformance/cases/<category>/cases.zig` exists for all eight categories. They are **never
compiled**:

```
$ grep -rnE 'conformance/cases|cases/sgr|cases\.zig' build.zig .github/workflows/ conformance/ | grep -v Binary
conformance/harness.c:45:/* ---------- Cases (mirror conformance/cases/<category>/cases.zig) ---------- */
conformance/README.md:19:    ├── sgr/cases.zig          # 17 SGR cases
...
conformance/README.md:122:The `cases/<category>/cases.zig` files are kept as the human-readable
```

The only references are the mirror comment and the README. `conformance/README.md:122` concedes the
files are "kept as the human-readable" mirror of the C arrays. **Two copies of the corpus exist,
only the C one executes, and they have already diverged.** Measured both sides
(`name = "..."` occurrences in each `.zig` vs `{"name"` entries in the matching C array):

| Category  | Zig file lines | Zig cases | C cases | Drift  |
| --------- | -------------- | --------- | ------- | ------ |
| sgr       | 116            | 15        | 17      | **-2** |
| cursor    | 110            | 13        | 10      | **+3** |
| osc       | 93             | 10        | 9       | +1     |
| charset   | 50             | 8         | 8       | 0      |
| mode      | 101            | 15        | 12      | **+3** |
| scroll    | 68             | 8         | 7       | +1     |
| kitty-gfx | 53             | 5         | 5       | 0      |
| edge      | 95             | 17        | 16      | +1     |
| **Total** | **686**        | **91**    | **84**  | **+7** |

A name-level diff of the SGR category proves this is real drift, not a counting artefact:

```
$ diff of case names, conformance/cases/sgr/cases.zig vs SGR_CASES in harness.c
zig-only: sgr_reset_specific_bold
C-only:   sgr_reset_bold, sgr_reset_default_bg, sgr_resets_all
```

`conformance/README.md:19` advertises "17 SGR cases", which is the **C** count (17); the Zig file it
points at holds 15. So the README describes the executing corpus while naming the dead one.
Recommendation: generate `harness.c` from the Zig files (single source of truth) or delete the Zig
tree. Today nothing checks parity, so neither choice is forced by tooling.

### No terminal, no socket

`conformance/harness.c` includes only `<ghostty/vt.h>`, `<ghostty/vt/formatter.h>`,
`<ghostty/vt/build_info.h>`, `<stddef.h>`, `<stdio.h>`, `<stdlib.h>`, `<string.h>`
(`harness.c:14-20`). A grep for `socket|ipc|fork|exec|spawn|pty` returns exactly 2 hits, both false
positives from the substring "pty" inside the word "e**mpty**" (`harness.c:27`, `:145`).
There is **no** subprocess, **no** PTY, **no** IPC.

That makes the CI a mismatch worth flagging, and the mismatch is two layers deep.
`ci-conformance.yml:84-85` explains that the build exists "so the conformance run can spawn it as a
black-box child", and `:87` names the step `Build agent-ipc` — but `:88` runs
`nix develop -c zig build -Demit-lib-vt`, which builds the **VT library**, not an `agent-ipc`
binary. So the intent is not implemented at the build step either, and `build.sh` then spawns
nothing. The IPC binary the comment describes is never produced by this job and never used by the
conformance run. The `conformance` job itself (`:68`) runs on `ubuntu-latest` with
`timeout-minutes: 15` and no `continue-on-error`, so it genuinely gates; and `:90` is the only
invocation in the repo of `./conformance/build.sh run`.

### Tier

**Conformance** — differential/behavioural comparison of VT byte streams to expected plain text
through the real C library, in-process. Not e2e.

## 5. `wasm/` — 54 node:test cases

- Tests live in `wasm/test/*.test.mjs` and use **only** `node:test` + `node:assert/strict` — no
  jsdom, no vitest, no browser driver (import lines across both files are `node:test`, `node:assert/strict`,
  `node:fs`, `node:url` and local `js/` modules). `wasm/test/smoke.test.mjs` (359 lines) holds **35**
  `test(`/`it(` blocks and `wasm/test/abi-exports.test.mjs` (313 lines) holds **19**, for **54** total.
  `wasm/test/types.test-d.ts` (168 lines) is a **type-level** suite: never executed, only compiled.
  It holds **68** `expectType`/`expectAssignable` assertions (`grep -cE 'expectType|expectAssignable'
wasm/test/types.test-d.ts` -> 68), so it contributes **0 runtime cases and 68 compile-time
  assertions**. Its own header (`:1-8`) states the failure mode it owns: "This file is only
  typechecked, never executed … should be a compile error here rather than a runtime surprise."
- **The 54 figure is corroborated by the repo's own CI comment**, which states that on Node 22 the
  suite "silently runs 20 tests instead of 54" (`zig-fork-tests.yml:174`). Note an unresolved
  one-case gap rather than smoothing it: that comment says **20**, and `abi-exports.test.mjs` holds
  **19** blocks by two independent counts (line-anchored `^\s*(test|it)\(` and a bare
  `(^|[^.\w])(test|it)\(` occurrence count both give 19). So either one test in `smoke.test.mjs`
  registers before the parse error, or `node --test` reports a count that does not map 1:1 to source
  blocks. **UNKNOWN**; settling it needs `node --test` run on Node 22, which this lane cannot do.
  What is not in doubt: the suite loses roughly two thirds of its cases on Node 22 while still
  reporting success.
- `wasm/package.json` supplies six scripts: `build` (`./build.sh`), `test`
  (`node --test test/*.test.mjs`), `test:header` (`./tools/verify-header.sh`), `typecheck`
  (`npx -p typescript@5 tsc -p tsconfig.json`), `exports`
  (`node tools/wasm-exports.mjs khostty-vt.wasm`), and `check`, which chains **four** gates:
  `npm run test:header && npm run typecheck && npm test && npm run exports`.
- `wasm/test/smoke.test.mjs` loads `wasm/khostty-vt.wasm` and **fails with the build command in the
  message** if the module is missing — `missing ${WASM}; build it with: wasm/build.sh` (`:42`, and
  the intent is documented at `:10`), so these tests cannot silently skip when unbuilt.
- CI is **two separate jobs in `ci-conformance.yml`**, and neither has an escape hatch — the file
  contains **no `continue-on-error` at all** (`grep -n continue-on-error` -> no matches):
  - `conformance` (`:68`) builds the library and runs `./conformance/build.sh run` (`:90`).
  - `wasm` (`:92`) is `ubuntu-latest`, `timeout-minutes: 15`, and runs `./wasm/build.sh` (`:115-116`)
    then a per-file loop `for f in ./wasm/test/*.test.mjs; do node --test "$f"; done` (`:123-125`)
    rather than `npm test` (the comment at `:118-121` explains the loop keeps per-file failure order).
    So **wasm is a genuine hard gate**, unlike Rust and Linux/macOS Go.
- `.github/workflows/zig-fork-tests.yml:179-183` repeats it in the shared fork workflow: build the
  module (`:180`) then `npm run check` (`:183`) in `wasm/`, with node pinned to 24 (`:177-179`) so
  the `await using` parse in the test bundle does not abort the file. That workflow is **nightly,
  not per-push** (its own header, `:17-22`: "Why nightly rather than per-push"). The consequence is
  worth stating exactly: the 54 runtime cases are gated on **every push** by `ci-conformance.yml`,
  but the 68 type assertions — and the header check and export check in the same chain — are gated
  only **nightly**. `ci-conformance.yml` never runs `typecheck`.
- **Documented silent-partial-run hazard (Node 22).** `ci-conformance.yml:100-104` explains that the
  bundle uses `await using` (Explicit Resource Management), "which Node 24 is the first release to
  parse. The runner's default Node is 22, where every `await using` is a SyntaxError, so the version
  has to be pinned here rather than inherited." `zig-fork-tests.yml:170-175` quantifies the damage:
  Node 22 "fails at parse time ... and the file aborts before its assertions, so the suite silently
  runs **20** tests instead of **54**. Verified: node 24.22.0 and 26.12.0 both give 54/54;
  node 22.23.3 fails." Both jobs therefore pin Node 24. This is the wasm analogue of the Rust
  `#![cfg]` silent-zero and the conformance silent-crash-only modes: **all three large suites have a
  documented way to report success while running fewer tests than it appears to.**
- **Skip-marker audit (measured, not assumed).** Because a headline count is a count of
  _definitions_, the four language suites were separately swept for tests that are declared but
  skipped, since those would quietly shrink what can actually fail: Rust `#[ignore]` -> **0**,
  `#[should_panic]` -> **0** (over `khostty-vt/tests` + `khostty-vt/src`); Go `t.Skip` -> **0** (over
  all 11 `*_test.go`); wasm `test.skip` / `skip:` -> **0** (over `wasm/test/*.mjs`; re-checked with
  the explicit path — `wasm/*.test.mjs` matches nothing, since the files live in `wasm/test/`, and
  that wrong glob silently returns 0); Python
  `pytest.mark.skip|skipif|xfail` -> **0**. So 199 / 70 / 54 / 162 are counts of cases that run and
  can fail. The one qualification is Python's opt-in escape hatch: `conftest.py:30` calls
  `pytest.skip(...)` _only_ when `KHOSTTY_VT_SKIP_IF_MISSING=1` (`conftest.py:20`), and by default
  the missing-library path raises `AssertionError` instead (`:31-36`) precisely so that "a green run
  against nothing would prove nothing" (`:5-6`). That env var is **not set in any workflow**
  (`grep -rn KHOSTTY_VT_SKIP_IF_MISSING .github/` -> no match), so the fail-closed default is what
  CI gets; the hatch is documented for a lint-only job at `khostty-python/README.md:228`.
- **Tier: integration.** Instantiates the compiled wasm module and calls its exported ABI
  in-process. Nothing is spawned, nothing is served.

## 6. `example/` — ZERO test assertions run in CI

- 35 example directories (`find example -maxdepth 1 -mindepth 1 -type d | wc -l` -> 35).
- No test framework anywhere. **27 C programs** exist, every one of them has an `int main`, and
  **16 of the 27 use `assert(...)`** (`grep -rl 'assert(' example --include=*.c | wc -l` -> 16).
  The other **11 mains assert nothing** (`c-vt-build-info`, `c-vt-color-scheme`, `c-vt-colors`,
  `c-vt-effects`, `c-vt-encode-focus`, `c-vt-kitty-graphics`, `c-vt-modes`, `c-vt-paste`,
  `c-vt-size-report`, `c-vt-static`, `c-vt`). Those are runnable smoke checks, and **one of them is
  actually executed in CI**: `example/c-vt-effects/src/main.c` runs as `./zig-out/bin/c_vt_effects.exe`
  on a Windows runner (`test.yml:998`, in job `build-libghostty-vt-windows` at `:957`). It still
  asserts nothing about the result: the step captures `$LASTEXITCODE` and formats it into a string
  (`test.yml:999-1000`), so a non-zero exit is _printed_ while the step passes anyway.
- 28 Zig examples declare a `build.zig`; exactly **3** declare a real test step, and each does it the
  same way: `const test_step = b.step("test", "Run unit tests")` at line 8 of
  `example/zig-formatter/build.zig`, `example/zig-vt-stream/build.zig` and `example/zig-vt/build.zig`,
  backed by `b.addTest(` (`:34`, `:34`, `:45`) and `test_step.dependOn(...)` (`:38`, `:38`, later in
  the file). No job invokes that step: both `example/` CI sites run a plain `zig build` and never
  `zig build test` — `test.yml:260-263` (`cd example/${{ matrix.dir }}`) and `test.yml:293-295`
  (`working-directory: example/zig-vt`, "Build Example without SDK", `nix develop -c env
DEVELOPER_DIR=/nonexistent zig build`). Neither reaches the `test` step, so those 3 test
  harnesses are dead code. **And empty:** `grep -c '^test "' example/zig-vt/src/main.zig
example/zig-vt-stream/src/main.zig example/zig-formatter/src/main.zig` returns `0`, `0`, `0`, and
  each `b.addTest(.{ .root_module = exe_mod })` points at that same `src/main.zig`, so the test
  binary has no cases. Wiring the step (done in PR #99, §11.5) produces a green that proves the
  example still compiles and nothing more.
  _Method warning:_ the obvious pattern `grep -rl 'b.step("test")' example --include=build.zig`
  returns **0**, because the real call has a second argument and the closing paren never follows
  `"test"`. The pattern that produces the 3 is `grep -rl 'b\.step("test"'`. A quoted command in a
  report has to be the command that actually produced the number.
- `example/swift-vt-xcframework/Package.swift` has **no `testTarget`** (grep for `testTarget|test`
  returns nothing) — ZERO Swift tests.
- CI almost only _builds_ examples: `.github/workflows/test.yml` has a `list-examples` job (`:217-228`)
  that enumerates dirs by `build.zig.zon` / `CMakeLists.txt` / `Package.swift`, then
  `build-examples-zig` (`:230+`), `build-examples-cmake` (`:296+`) and Windows variants run
  `zig build` or `cmake --build build` (`:259-263`, `:294-296`, `:330-331`). Compilation is the only
  assertion, **with exactly one exception**: the Windows `c_vt_effects.exe` run above (`:998`).
- **Tier: build verification.** **ZERO TESTS** executed.

## 7. Root `Makefile` and `CMakeLists.txt` — ZERO TESTS

- `Makefile` (root, 28 lines) has **six rule lines and no test target**: three `.PHONY` convenience
  targets (`init` at `Makefile:1`/`:3`, `glad` at `:9`/`:10`, `clean` at `:23`/`:28`) plus three
  file rules that refresh the vendored GLAD loader (`vendor/glad` `:12`, `.../gl.h` `:14`,
  `.../glad.h` `:20`). The word `test` does not appear in the file at all (`grep -ci test Makefile`
  -> `0`), so the earlier "three targets" phrasing counted only the `.PHONY` ones; six rule lines is
  the complete count.
- `CMakeLists.txt` (root, 377 lines): a grep for `test|add_test|ctest|enable_testing` returns
  **nothing**. **ZERO TESTS.** No first-party CMake target registers a test, which is consistent
  with `conformance/build.sh` hand-rolling its own harness instead of registering with CTest.
- **Correction to an earlier draft of this report:** the vendored dependencies under `zig-pkg/`
  _do_ register CTest tests. **Seven vendored CMake projects register `add_test()` cases, 54 in
  total** (26 + 21 + 2 + 2 + 1 + 1 + 1), each project also calling `enable_testing()`. An earlier
  draft said "61 registrations (27 + 22 + 4 + 3 + 3 + 1 + 1)", which is wrong and worth recording:
  61 is the count of matches for a combined `add_test|enable_testing` pattern (54 + 7
  `enable_testing()` calls), not a count of registrations, and the per-project split was misassigned.
  Verified by enumerating all 31 `CMakeLists.txt` under `zig-pkg/` and counting `add_test(` in each;
  no `.cmake` file contributes any. **No workflow invokes the `ctest`
  tool**. Beware the obvious check: `grep -rn ctest .github/workflows/` returns **12 hits in one
  file and none of them is the tool** — every match is the substring inside "esctest"
  (`test.yml:1560` `test-esctest:`, `:1589` `working-directory: test/esctest`, and siblings). Read
  that command's output rather than its exit status, or it will look like this claim is false. So
  the accurate statement is "no first-party
  CTest wiring, and 54 inherited vendored registrations that nothing runs", not "no CTest wiring
  anywhere in the tree".

### `test/` — an out-of-lane surface that changes the verdict

Lane B was scoped to Python, Rust, Go, `conformance/`, `wasm/`, `example/`, and root build files, so
this tree was not audited in detail. It is listed here because omitting it would misrepresent the
verdict, and because it is the one place in the repository that really does use a PTY:

| Dir                                         | Files | Owning language                             | Note                                           |
| ------------------------------------------- | ----- | ------------------------------------------- | ---------------------------------------------- |
| `test/esctest/`                             | 4     | Zig (`build.zig`, `src/main.zig` 281 lines) | **real PTY harness** — see below               |
| `test/fuzz-libghostty/`                     | 4014  | Zig                                         | fuzzing corpus (seed inputs), not a test suite |
| `test/egl-platform-display/`                | 3     | Zig                                         | platform probe                                 |
| `test/windows/`                             | 3     | Zig                                         | Windows helpers                                |
| `test/ucs-detect.sh`, `test/wasm-alloc.mjs` | 2     | shell / JS                                  | loose scripts                                  |

`test/README.md` states the intent: "anything related to testing Ghostty that doesn't fit within
the standard Zig testing framework".

**`test/esctest` is materially different from everything in sections 1-6.** Its README says: "esctest
runs under a pty. Everything it writes is fed through a libghostty-vt `Terminal`, and the terminal's
replies (DECRQCRA checksums, device attributes, cursor position and size reports) are written back
to it." The source matches the claim: `forkpty` (`test/esctest/src/main.zig:67`), `execvp` (`:74`),
and a process-global pty master fd (`:81`). It drives an external conformance suite (esctest2)
against the library and round-trips real terminal replies.

So the repo **does** contain a fork/exec/PTY harness with reply verification. It is Zig-owned and
`build.zig`-driven, which is why it belongs to the Zig lane rather than this one, but two
consequences for Lane B are unavoidable:

1. Any repo-level sentence of the form "nothing in this repository spawns a PTY" is false. Only the
   six audited surfaces can be described that way.
2. It is **report-only in CI**: `test.yml:1557-1559` documents the job as "Report-only: many tests
   fail today", and the run step is `nix develop -c zig build run > esctest.log || true`
   (`test.yml:1590`). The `|| true` means a total failure produces a green build. So the most
   end-to-end surface in the repo cannot block anything.

## 8. CI gate summary (which suites can actually block a merge)

`.github/workflows/` holds 27 workflow files. For the surfaces in this lane:

| Suite               | Workflow / line                                                                                                                                     | Blocking?                                                                                                                                                                                                                                                                                                                                                                                      |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Python 124          | `ci.yml:286` job, run step `:340`                                                                                                                   | **yes** (ruff job at `:268` is not the tests)                                                                                                                                                                                                                                                                                                                                                  |
| Go 45 fn / 75 cases | `ci.yml` Go job, fixed in PR #117 (§11.8)                                                                                                           | **yes** on `ubuntu-latest` as of #117; before it, this job ran **zero tests** and reported green                                                                                                                                                                                                                                                                                               |
| Go 45 fn / 75 cases | `go-windows.yml:59-63` `go test -count=1 -v ./...`                                                                                                  | yes, **Windows runner only**                                                                                                                                                                                                                                                                                                                                                                   |
| Rust 199            | `ci.yml:162-164` `cargo test ... \|\| echo`, job `continue-on-error` at `:151`                                                                      | **no** before PR #99; now **yes** (see §11)                                                                                                                                                                                                                                                                                                                                                    |
| Rust bindings       | `ci.yml:181` job, step `:195-199` `gen_ffi.py --check`                                                                                              | yes (not a test)                                                                                                                                                                                                                                                                                                                                                                               |
| conformance 84      | `ci-conformance.yml:68` job, `:90` run                                                                                                              | **yes** (no escape hatch)                                                                                                                                                                                                                                                                                                                                                                      |
| wasm 54             | `ci-conformance.yml:92`, `zig-fork-tests.yml:183`                                                                                                   | yes                                                                                                                                                                                                                                                                                                                                                                                            |
| example/            | `test.yml:259-263` etc. build; `:998` **executes** one; `zig-fork-tests.yml` `example-tests` now runs `zig build test` for the 3 harnesses (PR #99) | **no** for the C mains. The one run step (`c-vt-effects`, `test.yml:994-1001`) does end in `exit $code`, but every job in that workflow skips in this fork (run `42782592087`: 51 of 52 jobs `skipped`, the 52nd being the cancelled `Required Checks: Test` aggregator), so it never executes. The 3 Zig harnesses declare **0** tests as audited, so their new green proves compilation only |

**The largest suite in the repo was the least protected one.** 199 Rust cases, including the
compositional `tests/end_to_end.rs`, could not fail a merge. PR #99 makes them blocking and proves
it: the same job that had never started now runs 199 cases green (§11.1-11.2), and the first run of
the real gate was red on a genuine platform assumption (§11.3).

## 9. Verdict — is any non-Zig surface true e2e?

**No. Not one of the six audited surfaces launches a real application or talks to a real socket.**

One qualification up front, because it is the largest thing this audit could have got wrong. The
repository _does_ contain a fork/exec/PTY harness: `test/esctest/src/main.zig` uses `forkpty`
(`:67`), `execvp` (`:74`) and a pty master fd (`:81`) to drive the external esctest2 suite against
the library and verify round-tripped replies. It is Zig-owned and out of Lane B's scope (section 7),
and it is report-only (`test.yml:1590` ends in `|| true`), so it blocks nothing. The verdict below
is therefore a statement about the six audited surfaces only.

| Surface                        | Real app spawned?                        | Socket / PTY?       | What it really is                                                                                                                                             |
| ------------------------------ | ---------------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Python 124                     | no                                       | no                  | in-process dlopen of `libghostty-vt` via cffi                                                                                                                 |
| Rust 199                       | no                                       | no                  | in-process linked FFI (gated on `ghostty_vt_linked`)                                                                                                          |
| Go 45                          | no                                       | no                  | in-process cgo into the DLL/dylib                                                                                                                             |
| conformance 84                 | no                                       | no                  | in-process C calls on byte arrays compiled into `harness.c`                                                                                                   |
| wasm 54                        | no                                       | no                  | in-process wasm module instantiation                                                                                                                          |
| example/                       | no                                       | no                  | 26 of 27 compiled only; `c-vt-effects` has a run step (`test.yml:994-1001`, ending `exit $code`) that never executes, because every `test.yml` job skips here |
| _(out of lane)_ `test/esctest` | **yes**, esctest2 via `forkpty`+`execvp` | **yes, a real PTY** | report-only PTY conformance harness (Zig-owned)                                                                                                               |

The strongest surface, `khostty-vt/tests/end_to_end.rs`, is the only one that calls itself e2e, and
its own doc comment (lines 1-15) defines the claim narrowly: compose the public wrappers
(parse -> render -> rows -> cells -> graphemes -> snapshot -> search -> write-pty replies) and check
the extracted screen text. That is a real and valuable **compositional integration** test. It is
not e2e, because the terminal library is the entire system under test and nothing above it exists
in the process.

A genuine non-Zig e2e would need: spawn the `khostty` binary (or an `agent-ipc` server) as a
child, write bytes down a real PTY or IPC socket, and assert on what the app renders. The repo has
the raw material — `ci-conformance.yml:84-86` says the build exists "so the conformance run can
spawn it as a black-box child. The same build target is what an external integration test would
link against" — but the step is named `Build agent-ipc` (`:87`) while running
`zig build -Demit-lib-vt` (`:88`), which builds the library, and `conformance/build.sh` never spawns
anything. So both halves of the intended wiring are missing, and restoring them is the shortest
path to a real non-Zig e2e.

## 10. Open questions (and the command that would settle each)

1. **Do the 199 Rust cases pass right now?** **Answered, dynamically: yes, 199 passed / 0 failed** in
   run `42965360788` (job `130341253043`), 11 targets, after `working-directory: khostty-vt` and a
   `zig build -Demit-lib-vt` that reported `linking .../libghostty-vt.so` and `collected Rust tests:
199`. See §11.2. The first run of that gate was red on one case (§11.3); the failure was a macOS
   assumption in `tests/key_encoding.rs`, not a broken library call.
   Still open from that run: **`set_alt_esc_prefix(true)` alone emits `ESC a` on Linux and `a` on
   macOS.** Whether that divergence is intended is a library question. Settle it by reading the
   `option_as_alt`/`alt_esc_prefix` handling in the linked C source and deciding whether the
   platform split is deliberate; the test now records both behaviours rather than assuming one.
2. **How much of the 57 crash-only conformance cases is intentional?** **Answered: all 57 are
   intentional in the sense that the correct plaintext is `""`; the defect is that the struct has
   no way to say "assert empty".** The fix is `assert_kind`/`NULL` disambiguation plus typed fields
   that are already present in `conformance/cases/*/cases.zig`. Resolved since: MODE and OSC are
   assertable with shipped APIs, CHARSET only indirectly via `formatter.h:61` (see above). Nothing
   blocks the fix.
3. ~~Are the `conformance/cases/*.zig` arrays in sync with `harness.c`?~~ **Answered: no.** 91 Zig
   cases vs 84 C cases, and the SGR mismatch is exactly: the two lists share 13 names
   (`sgr_reset_all` … `sgr_combined_bold_underline`), one case is **renamed**
   (`sgr_reset_specific_bold` in `cases/sgr/cases.zig` vs `sgr_reset_bold` in `harness.c`), both keep
   `sgr_reset_default_fg`, and the C array carries **two cases the Zig array lacks**
   (`sgr_reset_default_bg`, `sgr_resets_all`) — 15 Zig vs 17 C, which is where the 91/84 gap partly
   lives. Nothing enforces parity today.
4. **Does `go test ./...` pass on macOS/Linux today?** Only the Windows path is enforced.
5. ~~Is `example/*` ever executed?~~ **Answered: yes, exactly once.** `example/c-vt-effects` is run
   on a Windows runner at `test.yml:998` (`./zig-out/bin/c_vt_effects.exe`, job
   `build-libghostty-vt-windows` at `:957`), and `example/c-vt-static` is built there too
   (`:975-976`). The other 25 of the 27 C mains and all 28 Zig examples are build-only. What the run
   proves is that the DLL loads and the program executes; it does not verify behaviour, because the
   exit code is formatted into a string rather than tested (`test.yml:999-1000`).
6. **Do the suites pass? Measured one lane over, at a different commit.** `QUALITY-RUN.md` in this
   same directory (commit `8c189ad7b`, window 2026-11-10T07:28-09:52Z) records PASS with evidence
   for all five language gates: Python `162 passed in 3.00s` at 97% coverage, Rust `199 tests
passed, 0 failed, across 11 binaries` at 88.15% regions / 89.52% lines, Go `ok ... coverage:
71.7% of statements`, conformance `Passed: 84  Failed: 0  Success Rate: 100%`, wasm `54/54 node
tests`. That answers items 1 and 4 for the `main` line, so the program as a whole is not
   unmeasured. `git diff --stat 8c189ad7b 9f3e31fa2` is **empty for both `khostty-python` and
   `khostty-vt`**, so those results describe exactly the sources counted here.
7. **Both count conflicts are now resolved, and one was an error in this report.** They had appeared
   as a symmetric +4/+4 gap.
   - **Python: 162 is correct.** The earlier figure of 158 in this report was wrong. The `ast` walk
     behind it read only _literal_ `parametrize` lists, and
     `khostty-python/tests/test_snapshot.py` parametrizes over a module constant:
     `ROUND_TRIP_CASES = [...]` with **5** entries, so that file is 8 defs -> **13** cases, not 8 -> 9. Resolving every parameter source to a real length gives exactly **162**, which matches the
     measured `162 passed in 3.00s` to the case. Two independent methods, one dynamic, agree.
   - **Rust: 199, and this report's 195 was the error.** QUALITY-RUN's figure was right. The
     static count `git grep -E '^[[:space:]]*#\[test\]'` is **195 in 23 files** (130 in `tests/`,
     65 in `src/`) — that part holds — but it is not the case count. `src/lib.rs` carries **8 fence
     lines in `//!` module docs, i.e. 4 code blocks**, and rustdoc compiles those as 4 doctests. My
     earlier check looked for ` ``` ` under `///` and reported zero, which was wrong twice:
     the fences are `//!`, not `///`, and there are four blocks. 195 + 4 = **199 across 11 binaries**
     (1 lib + 9 integration targets + `Doc-tests`), exactly what QUALITY-RUN measured. This lane
     then confirmed it dynamically, from CI rather than from reading: the job log for this branch's
     first run printed `collected Rust tests: 199` after listing all ten binaries plus `Doc-tests`.
     So both counts are now settled, both errors were mine, and both were the same error — treating
     a literal-pattern scan as a case count.

---

\*Lane B, read-only on the audited tree. No file in the khostty checkout was modified by the audit
itself, and no build or test run was performed **locally**. Every count above came from reading the
tree, with two exceptions established from CI logs on a separate worktree/branch
(`fix/ci-rust-test-gate`, PR #99, which is §11): the Rust figure of 199 (`collected Rust tests: 199`,
then 199 passed / 0 failed across 11 targets), and the observation that the three example harnesses
build and pass a test step containing **0** declared tests.

- _Original method note: all counts
  come from static reading and the greps quoted above._

  _Provenance and directory hygiene._ The output directory mandated for this audit
  (`~/CodeProjects/temp/khostty-e2e-20261110/`) held **143** files, of which only 3 were lane-B
  deliverables. All three are preserved next to this file: this report,
  `CONFORMANCE-ASSERT-FILL.md` (19,250 B, the per-case assert-fill table cited in section 4) and
  `INDEPENDENT-RECOUNT.md` (9,585 B, a blind recount that never opened either sibling file, whose
  five headline totals agree with mine). The other **140** files were pre-existing and unrelated to
  this lane. The deviation worth recording is that a shared directory was reused rather than a
  per-lane subdirectory, so any consumer of the original output had to filter on the `lane-b*` prefix
  rather than read the directory; that problem is what this directory removes.
  Cross-check performed at close: every `file:line` citation in this report was machine-validated for
  existence and range (**41** distinct files, **0** unresolved, **0** out-of-range).

## 11. What happened when the two gates were made real (PR #99)

This section is not part of the read-only audit. It records what the audit's two headline
defects did once they were actually fixed, because the results correct this report in one place
and add a finding that no static read could have produced.

Branch `fix/ci-rust-test-gate`, base `9f3e31fa2`, worktree
`~/CodeProjects/phenotype/repos/khostty-space/fix/wtree`, PR
<https://github.com/KooshaPari/Khostty/pull/99>. The audited main checkout was not touched.

### 11.1 The Rust job had never executed a single test

Removing `continue-on-error` and the `|| echo "::warning::"` wrapper was not enough. The next run
of the job failed with:

```
cargo test  ... error: could not find `Cargo.toml` in `/home/runner/work/Khostty/Khostty` or any parent directory
```

There is **no root `Cargo.toml`** in this repository:

```
$ ls Cargo.toml ../Cargo.toml ~/CodeProjects/Phenotype/Cargo.toml
ls: Cargo.toml: No such file or directory
ls: ../Cargo.toml: No such file or directory
ls: ~/CodeProjects/Phenotype/Cargo.toml: No such file or directory
$ find . -maxdepth 2 -name Cargo.toml -not -path './.git/*'
./khostty-vt/Cargo.toml
```

and the pre-fix job ran its cargo steps at the workspace root with no `working-directory`
(`git show 9f3e31fa2:.github/workflows/ci.yml` lines 156-164). With no manifest in the working
directory or any ancestor, every one of those steps exits 101 before compiling, and the `|| echo`
converted that exit into a green tick. The signature in the pre-fix log is exactly what a job that
never started looks like: `! cargo fmt issues (advisory)` and `! clippy issues (advisory)` on a job
marked successful.

So the earlier framing in this report was too generous to the job. "The advisory wrapper hides
failing tests" understates it: **the wrapper hid a job that could not start.** Fix: commit
`1ae5a4675` adds `working-directory: khostty-vt` to the fmt, clippy and test steps.

### 11.2 With the job able to run, 199 is confirmed dynamically

Once the directory was right, the suite compiled and ran, and the log states the total:

```
build.rs: linking .../zig-out/lib/libghostty-vt.so (dylib)
collected Rust tests: 199
```

and, from the same log, `11` targets reporting `test result: ok` summing to **199 passed, 0
failed** (`gh run view --job 130341253043 --log`). That is the count this report argued about for
several rounds, now measured by the tool that actually runs it: 65 unit + 4 doc-tests + 130
integration, across 1 lib + 9 integration targets + `Doc-tests`.

Two independent confirmations of the same number by two different methods is why §10.7 records the
conflict as a retraction rather than an open question.

### 11.3 The first real run found a real failure, and it was a macOS assumption

`cargo test` on the correct directory failed exactly one case of 199:

```
thread 'alt_escape_prefix_needs_both_the_prefix_option_and_option_as_alt' panicked at
    tests/key_encoding.rs:135
assertion `left == right` failed: the prefix option alone is not enough on this platform
  left: [27, 97]      right: [97]
```

The test asserts that `set_alt_esc_prefix(true)` alone leaves `Alt+a` as the plain byte `a`. That
is what the library does on macOS, where the probe behind the test was taken. On Linux the same
call already emits `ESC a`. `option-as-alt` is an Apple-only concept, so the prefix option alone
carries the behaviour there and option-as-alt stays inert.

The test was therefore a macOS observation asserted as a universal one, and the assertion message
said "on this platform" while checking a single platform. Commit `e0cec2bcf` selects the expected
bytes with `cfg!(target_os = "macos")` and records the divergence in a comment, so a genuine
library change in either direction is still visible.

What this demonstrates about the report's central claim is not that 199 tests were broken. It is
that **a suite with 199 cases and a `state_machine` fuzzer was running in a job that had never
started, and a platform-specific assertion was never checked on the only platform CI uses.** The
behaviour of `set_alt_esc_prefix` differing between macOS and Linux is itself a library question
this branch does not answer, and it is listed in §10 as such.

The gate is now real, and the pair of runs proves it: run `42964745618` at head `1ae5a4675` (job
`130339278793`) is **red** on this one case, and run `42965360788` at head `e0cec2bcf` is
**SUCCESS** with 199 passed. The two heads differ by `e0cec2bcf`, which changes one test file and
nothing else.

### 11.4 `test.yml` cannot run in this fork, so the first example fix was dead code

The first attempt at the dead example harnesses added `zig build test` to `test.yml`
(commit `97abfc332`). That was wrong for a reason the repo states in its own first three lines:

```
$ sed -n '2p' .github/workflows/test.yml
# FORK: DISABLED for automatic triggers. Manual dispatch only.
```

`test.yml:25` is `workflow_dispatch: {}` and it is the only trigger - parsing the file gives
`on: {'workflow_dispatch': {}}`. Of its 52 jobs, **50** have a `runs-on` naming
`namespace-profile-ghostty-*` (`python3 -c "import yaml; d=yaml.safe_load(open(...)); ..."` over the
same file), which this fork does not have. A step added there never runs on a push and never appears on a PR.
Committing it would have been the same class of defect the branch exists to remove - a green that
means nothing - so those hunks were reverted.

### 11.5 The three example harnesses are now wired, and they still contain ZERO tests

Commit `0b9e19d92` reverts the `test.yml` hunks and puts the work in
`.github/workflows/zig-fork-tests.yml`, which is live in this fork (cron, manual dispatch, and a
path-scoped `pull_request`). A new `example-tests` matrix covers the only three projects that
declare a `test` step - `example/zig-vt`, `example/zig-vt-stream`, `example/zig-formatter` - and
re-checks `build.zig` for `b.step("test"` at run time so deleting the step fails instead of
silently shrinking the matrix. `example/**` was added to the `pull_request` paths so the change is
exercised on the PR, not only on the nightly cron.

All three jobs pass (run `42966091519`):

```
success   example zig build test (zig-formatter)
success   example zig build test (zig-vt)
success   example zig build test (zig-vt-stream)
```

**That green does not mean what it sounds like.** None of the three declares any test:

```
$ grep -c '^test "' example/zig-vt/src/main.zig example/zig-vt-stream/src/main.zig example/zig-formatter/src/main.zig
0
0
0
```

Each build.zig is

```zig
const exe_unit_tests = b.addTest(.{ .root_module = exe_mod });
```

where `exe_mod.root_source_file` is `src/main.zig` - so the test binary is compiled from a source
file with no `test` block and contains zero cases. `zig build test` succeeds by compiling. The
harness entries in §6 should be read as **ZERO TESTS**, and the audit's original finding stands
with a sharper edge: these three were not merely uninvoked, they were uninvoked _and empty_. A
wiring change cannot fix an absent test; only writing one can - see §11.5.1 for the follow-up that
does.

The other 25 example projects declare no `test` step at all, and `zig build test` exits non-zero on
a project without one, so the matrix is an explicit list rather than a glob. Adding an example to
it requires it to declare a step first.

Empirically, from the job log for `example/zig-vt` (job `130343649507`): the `zig build test` step
opens its group at `05:30:00.506`, and the next log line is `Post Run actions/checkout@v4` at
`05:30:51.431`. Fifty-one seconds of compilation and **not one line of test output** - no
`All 0 tests passed`, nothing - and exit code 0. That is what a passing test step with no tests
looks like, and it is why the guard checks `build.zig` for the step rather than trusting the green.

#### 11.5.1 Follow-up: the three harnesses now contain tests

The claim above ("only writing one can") is implemented for all three projects. Each
`b.addTest(.{ .root_module = exe_mod })` still points at the same `src/main.zig`, which now declares
tests that assert terminal behaviour rather than print it:

| Project                 | Tests | What they assert                                                                                                                                                                     |
| ----------------------- | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `example/zig-vt`        | 2     | at `cols = 3`, `printString("abcd")` wraps to `"abc\nd"` while the unwrapped dump is `"abcd"`; a `\n` in `printString` behaves as carriage return + linefeed, not as a bare linefeed |
| `example/zig-vt-stream` | 1     | stream-fed text lands on successive rows; `ESC[1;1H` positions the cursor so following text overwrites the first row instead of appending; `ESC[2K` clears the row it is applied to  |
| `example/zig-formatter` | 1     | the HTML emit escapes markup: fed `a<b>&c`, the output contains `&lt;`, `&gt;` and `&amp;`                                                                                           |

Expected values were measured before being written down, not assumed:

- `printString` (`src/terminal/Terminal.zig:526`) is a codepoint printer - only `\n` is special
  (carriage return + linefeed) - so an SGR sequence passed to it becomes literal cells. Escape
  sequences have to go through `vtStream()`, which is why the formatter and stream projects feed
  the stream and the `zig-vt` project only uses `printString`.
- `plainString` and `plainStringUnwrapped` (`src/terminal/Terminal.zig:4993,4998`) differ exactly as
  their doc comments say: `cols = 3` with `"abcd"` yields `"abc\nd"` and `"abcd"`.

Local evidence, `zig 0.16.0`, each project run as `zig build test --summary all`:

```
zig-vt         Build Summary: 42/42 steps succeeded; 2/2 tests passed
zig-vt-stream  Build Summary: 42/42 steps succeeded; 1/1 tests passed
zig-formatter  Build Summary: 42/42 steps succeeded; 1/1 tests passed
```

Each line is a real test execution - `run test 2 pass (2 total)` and so on - which is the thing the
job log in §11.5 never contained.

`zig-fork-tests.yml` now enforces that distinction rather than trusting it: the example jobs run
`zig build test --summary all` and require a `run test N pass` line, so a harness that regresses to
an empty test binary fails the job instead of reporting green. Negative control for the guard: with
the `test` blocks stripped, Zig prints `run test success 228ms` - no count - and the guard rejects
it, while the test-bearing build prints `run test 2 pass (2 total)` and is accepted.

**Gotcha for the next author:** a test that writes to stderr makes the build log lie. With one
`std.debug.print` inside a test, every run printed

```
failed command: ./.zig-cache/o/.../test --cache-dir=./.zig-cache --seed=0x... --listen=-
```

and then, in the same run, ended `Build Summary: 42/42 steps succeeded; 3/3 tests passed`. Seven runs
with a printing test all emitted it; the exit code was captured in five of them and was 0 in all
five (the two earliest were piped through `grep`, so their status was never measured and is not
claimed). Removing the print removes the line. The harness is therefore not broken, only
misleading: a reader who greps for `failed command` will conclude the job failed while every test
passed. The same binary run by hand without `--listen=-` prints normally and exits 0. Assert, do not
print.

### 11.6 One more surface this branch does not fix — closed since, by #100

`zig build test` - the repo's own Zig unit suite, the ~3900-test tree - was invoked only from
`test.yml` (`:277`, `:317`, `:1747`, `:1822`, `:2207`), the workflow established in §11.4 as
unrunnable here, and `zig-fork-tests.yml` reached the tree only through `test-agent-ipc`. So the
largest Zig suite had the same status as the Rust suite before this branch: present, invoked, and
unable to report anything. That is Lane A's surface, and this branch left it alone on purpose.

It is closed there now. PR #100 (`49c2d521b`) adds a `zig-test` job to `zig-fork-tests.yml`,
named `test (zig build test)`, running
`nix develop -c zig build -Dapp-runtime=none test --summary all` on `ubuntu-latest` with
`timeout-minutes: 60` and the same Zig `0.16.0` pin as its neighbours. `--summary all` is what
makes the job mean something: `zig build test` prints nothing on success, which is the
silent-green failure mode of §11.5. Verified first-hand rather than quoted: run `42975266230` job
`130372774981` logs `Build Summary: 101/101 steps succeeded; 3935/3978 tests passed (43 skipped)`.

Two follow-ups finished the gate. PR #106 (`08141794c`) adds a `push`-to-`main` trigger, so the
job runs on the default branch as well as on PRs - run `42980815076` on `08141794c` shows
`test (zig build test)` **success** among its seven green jobs. PR #108 (`2ba3da153`) then deletes
the `pull_request` `paths:` filter outright, superseding #100's widening to `src/**` +
`build.zig.zon`: a path-filtered workflow emits **no check-run at all** on a non-matching PR, so
the job could never be made a required status check without deadlocking every unrelated PR, and
protected nothing in the meantime. `push` keeps its 18 paths, so main-side cost is unchanged.

Precision on "blocking": the job carries no `continue-on-error` and no test-level retries, so a
failure reddens the run on both PRs and `main`. It is **not** a required status check - branch
protection requires only `ci / lint` and `ci / test` - so it does not currently prevent a merge.
Making it required is an owner-only settings change and is tracked separately.

### 11.7 Landed

PR #99 was squash-merged to `main` as `26635b6f9` on 2026-11-11T06:25:37Z, after the branch was
updated onto the then-current `main` (`0d826f90d`) and CI re-ran green on the merged head
`dc64db2a4` (`Rust` job `130359546012` success; `Python`, `Python Tests`, `Go`, `TS/JS`, `Zig Fmt`,
`Workflow lint`, `Rust binding freshness`, `wasm ABI + data table` all success).

The gate is therefore live on `main`, not merely proposed, and it was verified there rather than
inferred from the PR: the first post-merge `ci.yml` run is `42972345372` on `26635b6f9`, **success**,
with `Rust` job `130368074392` reporting `collected Rust tests: 199` and 11 `test result: ok` targets
summing to **199 passed, 0 `FAILED`** (`grep -o 'test result: ok\. [0-9]* passed' | paste -sd+ | bc`
-> `199`). That is the first time the real gate has run on the default branch.

The two findings that no static read could have produced are §11.1 (a job that never started) and
§11.5 (three harnesses that pass without containing a test). Both are now stated where a reviewer
will see them: the PR body calls the example green "compiles, not tested" in bold.

One caveat on reachability, partly closed since this was written: at the time, `zig-fork-tests.yml`
had no `push` trigger (cron + dispatch + a path-scoped `pull_request`), so the example harnesses ran
nightly at 05:20 UTC rather than on every merge. PR #106 (`08141794c`) added `push: branches:
[main]` with the same `paths:` list as the `pull_request` trigger, so the pre-merge and post-merge
gates now select the same changes and a merge no longer waits up to a day for coverage. Before that,
the merged tree was dispatched by hand on `main` to confirm default-branch execution (`42974499103`,
`26635b6f9`, `workflow_dispatch`) and finished **success**, all six jobs: the three `example zig
build test` entries plus `test-agent-ipc`, `test-windows-apprt` and `wasm ABI + data table`. So the
workflow that could not run before PR #99 runs on the default branch too.

### 11.8 The Linux Go gate executed zero tests, and reported success

`ci.yml`'s Go job was decorative in the same way the Rust job was (§11.1), and for a reason no static
read of the YAML shows: **every command ran at the repository root, and there is no Go module
there.** The only module in the tree is `khostty-go/go.mod` (`git ls-files '*go.mod'` returns one
path), so `go test ./...` failed before it collected anything:

```
$ cd <repo root> && go test ./...
pattern ./...: directory prefix . does not contain main module or its selected dependencies
$ echo $?
1
```

Reproduced 2026-11-11 on `a620c7a` with go1.23.4. The exit 1 never reached the job: the step ended
`|| echo "::warning::test failures (advisory)"` and the job carried `continue-on-error: true`. So the
Linux Go row of §8 was not merely "swallowed twice", it was **a gate that executed no tests at all**,
and it could not have caught a compile error either. `go vet ./...` at the root exits 1 on the same
missing module; `gofmt -l .` prints nothing because there are no Go files at the root. The remaining
Go gate, `go-windows.yml`, is Windows-only, so on Linux PRs the whole Go surface was ungated.

The fix (PR #117) copies the three things `go-windows.yml` already does correctly:
`defaults.run.working-directory: khostty-go`; a `zig build -Dapp-runtime=none` before any Go command
(cgo links `-lghostty-vt` from `../zig-out/lib`, so no Go command can link before the library
exists); and exit codes that are allowed to fail the step. `gofmt` / `go vet` / `go test` lose their
advisory wrappers, all three being clean on the current tree, so nothing needed grandfathering. It
also carries the zero-test guard from §11.5.1: the step requires at least one `=== RUN` line, so a
green run over zero tests cannot pass again.

Local evidence for the new step body, run before pushing:

| Check                            | Result                                                                                 |
| -------------------------------- | -------------------------------------------------------------------------------------- |
| the real module, in `khostty-go` | `ok github.com/KooshaPari/Khostty/khostty-go`, prints `ran 45 top-level tests`, exit 0 |
| a module with no `_test.go` file | `::error::go test reported success but ran zero tests`, exit 1                         |
| a module with one failing test   | exit 1, carried by `pipefail` rather than by an `\|\| echo`                            |

**Count reconciliation.** The Go surface is **45 test functions** and **75 cases** once `t.Run`
subtests expand: `go test -count=1 -v ./...` emits 45 top-level `--- PASS` lines, 30 indented ones,
and 75 `=== RUN` lines. The "70 cases" this report previously carried in its closing summary does not
reproduce under any of those three measures, so it is corrected rather than explained away. §8 now
reads "45 fn / 75 cases".

**Two claims corrected here**, both from §8's `example/` row:

1. `c-vt-effects`' run step does **not** merely print an exit code. `test.yml:994-1001` captures
   `$LASTEXITCODE` and ends `exit $code`, so a nonzero exit would fail the step. "Exit code printed,
   never asserted" was wrong about the assertion.
2. It nevertheless never executes: run `42782592087` (2026-11-10, `test.yml` on `21d06d0c`) shows
   **51 of 52 jobs `skipped`** (the 52nd is the `Required Checks: Test` aggregator, which `cancelled`). So
   "no C main is actually asserted" is the right conclusion, for a different reason than the one
   given.

One over-correction to avoid in the other direction: the vendored `zig-pkg/` CMake projects of §7 do
register 54 CTest cases, but **no tracked `CMakeLists.txt` registers any test** (`git grep -l
'add_test(' -- '*CMakeLists.txt'` returns 0 of the 4 tracked files). The first-party CTest surface is
genuinely empty, and wiring `ctest` would run third-party packages fetched at build time rather than
this repository.

## Closing summary (6 lines)

1. **Totals:** Python 124 functions / **162 cases**, Rust **199** (195 `#[test]` + 4 doc-tests), Go 45 functions / **75 cases** (§11.8 measured 45 top-level `--- PASS` plus 30 indented subtests), conformance **84**, wasm **54** runtime cases + **68** type-level assertions, `example/` 16 assert-bearing mains (of 27; the one with a run step, `c-vt-effects`, ends `exit $code` at `test.yml:1001` but never executes because all `test.yml` jobs skip), root `Makefile`/`CMakeLists.txt` **ZERO TESTS**; and no suite hides cases behind a skip marker (`#[ignore]`/`t.Skip`/`test.skip`/`pytest.mark.skip` all **0**), so these are counts of cases that can actually fail. **Cross-check:** a sibling measured run (`QUALITY-RUN.md`, commit `8c189ad7b`, byte-identical trees) reports all five gates PASS, and its Python `162 passed` matches this count to the case; its Rust `199 across 11 binaries` also matches once the 4 doc-tests in `src/lib.rs` are counted — both conflicts were errors in this report, see §10.6-10.7.
2. **Fixtures:** **ZERO** golden or expected-output files anywhere in `conformance/` — expected values are inline literals, 27 usable and 57 empty (`harness.c:27,201`). The repo does have exactly one such fixture, in Rust: `khostty-vt/tests/abi_layout.txt` (42 lines, `include_str!` at `tests/abi_layout.rs:23`), so the technique exists here; conformance just does not use it.
3. **What `build.sh run` asserts:** all 84 cases parse without crashing, plus a `memcmp` of rendered plaintext for only 27 of them (`harness.c:201`, `:225-226`) — the other 57 cannot assert at all because `""` is overloaded (`:254-273`).
4. **Largest suite could not block a merge; fixed on `fix/ci-rust-test-gate` (PR #99), see §11:** Rust 199 runs as `cargo test --workspace ... || echo "::warning::test failures (advisory)"` (`ci.yml:162-164`) under `continue-on-error: true` (`ci.yml:151`), and `ci.yml:167-188` records a shipped stale-binding defect that this arrangement let through. The same job has already been silently skipped for a whole release cycle by a broken detection test (`ci.yml:99-104`: `[ -f "**/Cargo.toml" ]` never glob-matched), so both the gate and the trigger have failed here before.
5. **Hard gates only:** Python tests (`ci.yml:286` job, run step `:340`), Go on Linux (`ci.yml` Go job, §11.8, PR #117) and on Windows (`go-windows.yml:59-63`), conformance (`ci-conformance.yml:68,90`), wasm (`ci-conformance.yml:92,115-125`, no `continue-on-error` in that file), and `gen_ffi.py --check` (`ci.yml:181,195-199`).
6. **True e2e: none of the six audited surfaces, with one process-boundary exception.** Five drive an in-process `libghostty-vt` (cffi dlopen, linked FFI, cgo, direct C calls, wasm instantiate), but `khostty-python/tests/test_examples.py:21-31` runs the shipped Python examples in **subprocesses** and asserts exit code plus stdout — a real process boundary, inside the merge gate (`ci.yml:340`), though it is a child interpreter rather than a PTY or an external app. `example/` is build-only for 26 of its 27 C mains (the 27th, `c-vt-effects`, ends `exit $code` at `test.yml:1001`, so it would assert, but 51 of its 52 jobs are `skipped` and the run is `cancelled` in this fork: run `42782592087`), and the three Zig example harnesses run `zig build test` in `zig-fork-tests.yml` (PR #99) but declared **zero** tests as audited, so their green was a compile result (§11.5); they now carry 2/1/1 asserting tests (§11.5.1); the `agent-ipc` child the CI comment promises is neither built by that step nor spawned (`ci-conformance.yml:87-88`, `build.sh`). The repo's only fork/exec/PTY harness is out of lane and report-only: `test/esctest` (`test/esctest/src/main.zig:67,74,81`, run at `test.yml:1590` ending `|| true`).
