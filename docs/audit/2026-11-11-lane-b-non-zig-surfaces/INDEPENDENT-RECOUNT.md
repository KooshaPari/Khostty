# Lane B3 — Independent Recount of Test Surfaces (khostty)

Repo: /Users/kooshapari/CodeProjects/Phenotype/repos/khostty
Role: bounded READ-ONLY counting worker. Two independent methods per surface. No build, no test
execution, no repo modifications, no pushes, no search outside the repo. The lane-b / lane-b2 files
were never opened.

Method: every number below was produced by a command that is quoted verbatim. Where two methods
disagreed, both numbers are reported with the cause, and the disagreement was resolved by
identifying the specific construct that caused it (not by preference).

---

## Results table

| Surface                                                | Count   | Method 1 (exact command)                                                                                                                     | Method 2 (exact command)                                                                                            | Agree?                                                                                                    | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ------------------------------------------------------ | ------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Python (pytest test functions under `khostty-python/`) | **124** | `grep -cE '^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+test_' khostty-python/tests/*.py \| awk -F: '{s+=$2} END{print s+0}'` → 124       | `awk '/^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+test_/{c++} END{print c+0}' khostty-python/tests/*.py` → 124 | YES (3rd method also 124: `grep -rnoE 'def test_' khostty-python/tests/ --include='*.py' \| wc -l` → 124) | **Naive whole-directory counting disagrees: 139/140.** See "Disagreement D1" below. Authoritative count is 124. Per file: test*terminal 30, test_mouse 19, test_key 18, test_ffi 16, test_search 16, test_formatter 14, test_snapshot 8, test_examples 3, conftest.py 0. No `async def test*`anywhere.`khostty-python/pyproject.toml`sets`testpaths = ["tests"]`, `addopts = "-ra"`.                                                                                                                                                                                                       |
| Rust (`#[test]` in `khostty-vt/`, tests/ + src/)       | **195** | `grep -rno '#\[test\]' khostty-vt --include='*.rs' \| wc -l` → 195                                                                           | `awk '/#\[test\]/{w=1;next} w&&/fn /{c++;w=0} END{print c+0}' $(find khostty-vt -name '*.rs' \| sort)` → 195        | YES                                                                                                       | Split: `khostty-vt/tests/` = 130, `khostty-vt/src/` = 65 (23 files carry `#[test]`). No `#[tokio::test]`, `#[test_*]`, or `proptest!` variants exist (checked with `grep -rnoE '#\[(tokio::)?test\]\|#\[test_[a-z_]+\]\|proptest!'` → 195 `#[test]`, 0 others), so no attribute-style test was missed.                                                                                                                                                                                                                                                                                     |
| Go (`func Test...` in the Go module)                   | **45**  | `grep -rn '^func Test' khostty-go --include='*_test.go' \| wc -l` → 45                                                                       | `awk '/^func[[:space:]]+Test/ {c++} END {print c+0}' $(find khostty-go -name '*_test.go' \| sort)` → 45             | YES                                                                                                       | **The module is at `khostty-go/`, not the repo root** (`khostty-go/go.mod`: `module github.com/KooshaPari/Khostty/khostty-go`). `find . -maxdepth 2 -name '*.go' -not -path './khostty-go/*'` → empty, so there are no Go files outside `khostty-go/`. 0 receiver-style test methods (`grep -rnE '^func \([^)]*\) Test'` → 0), so no `func (x) TestFoo` was missed. Per file: ghostty_vt 8, ghostty_key 6, ghostty_keyencoder 6, ghostty_mouse 5, ghostty_search 5, ffi 4, ghostty_mouseevent 4, ghostty_render 4, ghostty_snapshot 3, ghostty_test.go 0, ghostty_mouse_fixture_test.go 0. |
| C conformance (`conformance/harness.c`)                | **84**  | `awk '/_CASES\[\] *= *\{/{inarr=1;next} inarr&&/^\}/{inarr=0;next} inarr&&/^[[:space:]]*\{/{c++} END{print c+0}' conformance/harness.c` → 84 | `grep -cE '^[[:space:]]*\{[[:space:]]*"' conformance/harness.c` → 84                                                | YES                                                                                                       | 8 category arrays, per-category: sgr 17, edge 16, mode 12, cursor 10, osc 9, charset 8, scroll 7, kitty 5 = **84**. Both patterns verified against visible source (`{"sgr_reset_all", ESC "[0m", ""},` at line 48) — a zero would have been visible, so neither is a silent-failure pattern. Multi-line entries (e.g. `kitty_init` at 133-134, `mixed_sequences` at 148-150) each open with exactly one `{"name"` line, so they are counted once. See "Disagreement D2".                                                                                                                   |
| wasm (`*.test.mjs`)                                    | **54**  | `grep -oE "\btest\(" wasm/test/*.test.mjs \| wc -l` → 54                                                                                     | `grep -cE "^[[:space:]]*test\(" wasm/test/*.test.mjs` → `abi-exports.test.mjs:19`, `smoke.test.mjs:35` (sum 54)     | YES                                                                                                       | **Files are at `wasm/test/*.test.mjs`, not `wasm/*.test.mjs`** (only 2 exist; `find wasm -name '*.test.mjs'` → `wasm/test/abi-exports.test.mjs`, `wasm/test/smoke.test.mjs`). Framework is `node:test` (`import { test, describe, before } from "node:test";`). No `it(` alias (`grep -cE '(^\|[^A-Za-z_.])it\('` → 0/0) and no `.test(` member calls (`grep -oE '\.test\(' \| wc -l` → 0), so neither method inflates. `describe()` blocks are containers, not test cases, and are not counted.                                                                                           |

---

## Disagreements found, and their cause

### D1 — Python: 124 vs 139/140 (RESOLVED by locating the cause)

Two whole-directory methods disagreed with each other and with the project-scoped count:

- `grep -rno 'def test_' khostty-python --include='*.py' | wc -l` → **140**
- `awk '/^[[:space:]]*def[[:space:]]+test_/ {c++} END {print c+0}' $(find khostty-python -name '*.py' | sort)` → **139**

The +1 was isolated exactly: the only match in the entire tree that is _not_ at the start of a line
is a **comment inside vendored pytest source**:

```
khostty-python/.venv-gate/lib/python3.14/site-packages/_pytest/mark/structures.py:172:
    #   def test_foo(x, y): pass
```

`khostty-python/.venv-gate/` is a real `uv` virtualenv (`pyvenv.cfg`: `uv = 0.11.29`,
`version_info = 3.14`, `CACHEDIR.TAG` present), i.e. third-party pytest source, not this project's
tests. It contributes **15** line-start `def test_` matches inside `_pytest/*.py`
(capture.py 5, mark/structures.py 2, pytester.py 2, junitxml.py 2, mark/**init**.py 1,
monkeypatch.py 1, legacypath.py 1, fixtures.py 1) plus the 1 comment occurrence.
124 (project) + 15 (venv) + 1 (comment) = 140.

So the three candidate numbers for "pytest test functions under khostty-python/" are 140, 139 and
124, and they are **not** three estimates of the same thing:

- **140** = every textual occurrence of the string `def test_` anywhere under `khostty-python/`,
  including a comment and the vendored pytest package.
- **139** = every line that _starts_ with `def test_` anywhere under `khostty-python/`, still
  including the vendored pytest package.
- **124** = the project's own pytest test functions, i.e. what pytest actually collects, since
  `khostty-python/pyproject.toml` declares `[tool.pytest.ini_options] testpaths = ["tests"]`.

**Reported answer: 124**, because the vendored virtualenv is not the project's test surface and
pytest would not collect it. The 139/140 numbers are reported above as the literal whole-directory
reading, with their cause attached.

### D2 — C conformance: harness.c = 84 vs the Zig cases of record = 91 (NOT a method disagreement)

The C harness's own header comment (line 45) says the arrays "mirror
conformance/cases/<category>/cases.zig". They do **not** fully mirror. Counting the Zig source
(`grep -cE '^\s*\.\s*name = '` over the 8 `cases.zig` files) gives **91**, versus **84** in
`harness.c`. Per category:

| category  | harness.c | cases.zig | delta  |
| --------- | --------- | --------- | ------ |
| sgr       | 17        | 15        | -2     |
| cursor    | 10        | 13        | +3     |
| osc       | 9         | 10        | +1     |
| charset   | 8         | 8         | 0      |
| mode      | 12        | 15        | +3     |
| scroll    | 7         | 8         | +1     |
| kitty-gfx | 5         | 5         | 0      |
| edge      | 16        | 17        | +1     |
| **total** | **84**    | **91**    | **-7** |

This is not a counting-method disagreement — both C methods (awk state machine over the
`*_CASES[]` arrays, and grep for entry lines opening with `{"`) independently return 84, and the
per-category awk breakdown sums to 84 exactly. The C harness simply carries fewer cases than the
Zig source it claims to mirror, and it also carries two cases the Zig side does not (sgr +2).

**Reported answer for the asked question (test cases in `conformance/harness.c`): 84.**

### D3 — No other disagreements

Rust (195/195) and wasm (54/54) agreed between methods on the first pass, and no attribute alias,
receiver-style method, `it(` alias, or `.test(` member call was found that would have caused a
silent undercount on any surface.

---

## What I could not count with full confidence

- **The Python number is a scoping judgement, not a measurement.** 124 is what pytest collects
  under the project's declared `testpaths`; a strict literal reading of "under khostty-python/"
  yields 139/140. I am confident the _cause_ of the gap (the `.venv-gate` uv virtualenv) and that
  124 is the project surface, but a reader who wants the literal string-match number should use
  140 and read D1.
- **The Go module is not at the repo root** as the task assumed — it is at `khostty-go/`. There are
  no other `.go` files in the repo (verified at depth 2 outside `khostty-go/`), so 45 is the
  complete Go total, but if a third `.go` tree were ever added outside `khostty-go/`, this count
  would need re-running.
- **The wasm count of 54 covers only `*.test.mjs`.** `wasm/test/types.test-d.ts` is a separate
  type-level test file containing 68 `expectType`/`expectAssignable` assertions
  (`grep -cE 'expectType|expectAssignable' wasm/test/types.test-d.ts` → 68). Those are not
  `*.test.mjs` and are excluded from 54, but if the intent was "all wasm test assertions" the
  figure would be 54 runtime cases + 68 type assertions. I did not verify that the 68 assertions
  all pass, only that they exist.
- **Counts are of test _definitions_, not executed cases.** `pytest.mark.parametrize` combinations
  and Rust/Go table-driven subcases would multiply the number of executed cases at runtime. I
  counted definitions only, as asked, and did not inspect whether any parametrized expansion would
  change the runtime case count.
- **No surface was executed.** Nothing here was built, run, or type-checked; these are static
  source counts, so they describe what is _written_, not what compiles or passes.
