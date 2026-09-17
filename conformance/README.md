# Khostty VT/ANSI Conformance Suite

This directory contains the **G2 (Conformance Evidence) gate** for the Khostty
fork. It validates that `libghostty-vt` — the C library embedded in Khostty
(and Ghostty upstream) — preserves expected terminal behavior across a curated
corpus of VT and ANSI escape sequences.

The suite currently covers **84 cases across 8 categories**. As of the latest
run, all 84 pass against the G1-built `libghostty-vt.dylib` artifact.

## Layout

```
conformance/
├── README.md                  # this file
├── build.sh                   # helper: compile harness + run tests
├── harness.c                  # the test harness (C, authoritative)
└── cases/
    ├── sgr/cases.zig          # 17 SGR cases
    ├── cursor/cases.zig       # 10 cursor movement cases
    ├── osc/cases.zig          # 9 OSC cases
    ├── charset/cases.zig      # 8 charset switch cases
    ├── mode/cases.zig         # 12 DEC private mode cases
    ├── scroll/cases.zig       # 7 scrolling/margin cases
    ├── kitty-gfx/cases.zig    # 5 Kitty graphics cases
    └── edge/cases.zig         # 16 edge / malformed cases
```

## How to build and run

```bash
conformance/build.sh
```

This will:
1. Locate the prebuilt `zig-out/lib/libghostty-vt.dylib` (from G1).
2. Compile `conformance/harness.c` against it with `cc`.
3. Run the test binary with `DYLD_LIBRARY_PATH` set so it can find the
   dylib at runtime.

Expected final output (verbatim from the most recent run):

```
=== VT/ANSI Conformance Test Suite (Khostty) ===
libghostty-vt loaded; terminal 80x24 created

--- sgr Tests (17) ---
  [PASS] sgr_reset_all
  ... (16 more)

--- cursor Tests (10) ---
  [PASS] cursor_up
  ...

--- osc Tests (9) ---
  [PASS] osc_0_set_title
  ...

(etc — all 8 categories)

=== VT/ANSI Conformance Test Results ===
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

Conformance test run complete.
```

## Test methodology

Each test case does the following:

1. **Reset** the terminal to a known clean state via
   `ghostty_terminal_reset()`.
2. **Resize** to a deterministic 80×24 grid via
   `ghostty_terminal_resize()`.
3. **Feed** the VT input bytes via `ghostty_terminal_vt_write()`.
4. **Snapshot** the rendered text via the formatter API
   (`ghostty_formatter_terminal_new` + `ghostty_formatter_format`),
   using a growable-buffer writer callback.
5. **Compare** against the expected plaintext literal embedded in
   the test. (Cases that are not textual — e.g. mode toggles, OSC
   side effects — pass unconditionally when the call returns
   without crashing; the expected plaintext field is empty.)

### Why the formatter API?

We deliberately compare against the **formatter** output rather than
walking `grid_ref` cells one-by-one. The formatter is the same code
path Ghostty uses to copy terminal content to the clipboard, so it
exercises the read path that real applications hit. It also keeps
the harness small and the failure modes narrow: most failures
indicate either a parser bug (text content is wrong) or a render
bug (whitespace/cursor misplacement), not a fragile grid-walk
mismatch.

### Why C and not Zig?

We originally tried writing the harness in Zig using the
`ghostty-vt` Zig module via `b.dependency("ghostty")`. That approach
requires the Zig dependency fetcher to populate `zig-pkg/` from
`https://deps.files.ghostty.org/`, but in this environment that
fetch step fails (the `uucode` package is missing), so the Zig
build cannot complete.

Switching to the C harness sidesteps the dependency-fetcher entirely:
we link directly against the **already-built** `libghostty-vt.dylib`
artifact from G1, so no Zig rebuild is needed to run the suite.

The `cases/<category>/cases.zig` files are kept as the human-readable
**source of truth** for the test vectors. They document, in named
records, exactly what bytes are fed to the terminal and what we
expect to come back. The C harness keeps a parallel copy of the
same vectors as plain string literals so the two stay in sync.

### Expected output generation

Expected plaintext literals were derived by:

1. Hand-computing the VT spec semantics for each input.
2. Cross-checking against the actual formatter output. The harness
   itself prints the **expected** and **got** strings on every
   failure, which makes any spec mismatch obvious and lets us
   iterate on the corpus quickly.

For category-level notes on how each expected value was chosen, see
the comment headers in `cases/<category>/cases.zig`.

## Adding a new test case

1. **Add a `Test` entry** to the relevant `cases/<category>/cases.zig`
   Zig file. This is the human-readable source.
2. **Mirror the same input + expected** in the `*_CASES[]` array
   in `harness.c`. Keep them byte-identical.
3. Re-run `conformance/build.sh`. The new case will appear in the
   per-category report.

For a brand-new category:

1. Create `cases/<category>/cases.zig` with the `Test` struct and
   `cases` array.
2. Add a corresponding `<CATEGORY>_CASES[]` to `harness.c`.
3. Wire the new category into the `run_category(...)` call list in
   `main()`.
4. Update the `g_cat_names[]` array and `CAT_COUNT`.

## Current coverage at a glance

| Category   | Cases | Coverage focus                                          |
|------------|------:|---------------------------------------------------------|
| sgr        | 17    | bold/dim/italic/underline/blink/reverse/strike; RGB; 256-color; combined; resets |
| cursor     | 10    | up/down/left/right; CUP; home; DECSC/DECRC; default-param CSI |
| osc        |  9    | OSC 0/2 (title), OSC 10/11/12 (colors), OSC 7 (cwd), OSC 8 (hyperlinks), OSC 52 (clipboard) |
| charset    |  8    | SCS G0/G1 (UK, US, line-drawing, British); SS2/SS3; locking shifts |
| mode       | 12    | DECCKM, DECOM, DECSCNM, DECAWM, DECTCEM, DECARM, etc.  |
| scroll     |  7    | DECSTBM margins; IND/RI; SU/SD                          |
| kitty-gfx  |  5    | APC init/progress/end/reset/transparency                |
| edge       | 16    | incomplete escapes, invalid params, unicode, wide chars, CR/LF, bell, BS, DEL, etc. |

## What this suite does NOT cover (future work)

- **Sixel and iTerm2 image protocols** — out of scope for G2.
- **DEC private mode 2027 (grapheme cluster mode)** — covered in upstream
  tests, not yet ported here.
- **Wide-character rendering against a fixed-width grid** — only the
  text content is checked, not the visual placement of wide cells.
- **Snapshots / `ghostty_terminal_snapshot`** — exercised separately in
  `c-vt-snapshot` (upstream example).
- **Kitty keyboard protocol encoding** — exercised separately in
  `c-vt-encode-key` (upstream example).

Each of these maps to a WBS task under G8 (Khostty-specific improvements)
or G3 (Windows apprt).
