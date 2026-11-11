# Conformance assert-fill analysis (complete)

Repo: `/Users/kooshapari/CodeProjects/Phenotype/repos/khostty`
Scope: the 34 conformance cases in the four categories whose `expected_plain` is `""` in
`conformance/harness.c` — OSC (9), CHARSET (8), MODE (12), KITTY (5).
Method: read-only source reading. No build, no test run, no repo mutation.

---

## 0. TL;DR

**0 of the 34 cases have a non-empty correct `expected_plain` derivable from the input bytes.**
For all 34, the _correct_ plaintext is the empty string — and the empty string is exactly the
sentinel that disables the assertion (`conformance/harness.c:27`, gate at `conformance/harness.c:201`).
So the honest answer for every one of the 34 is: **no plaintext assertion is possible today; each needs a
different assertion type** — and, helpfully, the correct typed assertion already exists in the Zig
source-of-truth files that the C harness was supposed to mirror.

| category  |  cases | correct plaintext | non-empty plaintext assertable today |                        needs different assertion type |
| --------- | -----: | ----------------- | -----------------------------------: | ----------------------------------------------------: |
| osc       |      9 | `""` for all 9    |                                    0 | 9 (title 2, color 3, pwd 1, hyperlink 2, clipboard 1) |
| charset   |      8 | `""` for all 8    |                                    0 |                                     8 (charset state) |
| mode      |     12 | `""` for all 12   |                                    0 |                                       12 (mode state) |
| kitty-gfx |      5 | `""` for all 5    |                                    0 |                                   5 (graphics action) |
| **total** | **34** |                   |                                **0** |                                                **34** |

---

## 1. The structural blocker (read this first)

`conformance/harness.c:24-28`

```c
typedef struct {
    const char *name;
    const char *input;
    const char *expected_plain; /* empty means no plaintext assertion */
} TestCase;
```

`conformance/harness.c:201` — `if (strlen(tc->expected_plain) > 0) {` — the plaintext comparison
(and only that comparison) is inside this guard. `conformance/harness.c:225-226` is the actual
`strlen`/`memcmp` comparison.

Consequence: `""` is overloaded. It means both "the terminal should print nothing" and
"we do not know how to assert this". A case whose _correct_ expected output is the empty string
therefore **cannot be asserted at all** with this struct. This is the single change that unlocks
the other 33: make "no assertion" and "assert empty" distinguishable (e.g. `expected_plain == NULL`
means "assert empty", or add an `assert_kind` enum alongside the payload).

`conformance/README.md:93-96` already states the current behaviour as intended:
"Cases that are not textual — e.g. mode toggles, OSC side effects — pass unconditionally when the
call returns without crashing; the expected plaintext field is empty."

### The answers were never lost — they are in the Zig files

The four Zig case files do **not** have an `expected_plain` field. They carry typed expectation
fields that the C struct dropped:

| file                                    | `Test` struct fields                                                         | line    |
| --------------------------------------- | ---------------------------------------------------------------------------- | ------- |
| `conformance/cases/osc/cases.zig`       | `expected_title`, `expected_clipboard`, `expected_pwd`, `expected_hyperlink` | `:3-10` |
| `conformance/cases/charset/cases.zig`   | `expected_charset`                                                           | `:3-7`  |
| `conformance/cases/mode/cases.zig`      | `expected_active_mode`, `expected_mode_reversed`                             | `:3-8`  |
| `conformance/cases/kitty-gfx/cases.zig` | `expected_action`, `expected_uri`, `expected_width`, `expected_height`       | `:3-10` |

`conformance/README.md:145-146` states the rule: "Mirror the same input + expected in the
`*_CASES[]` array in `harness.c`. Keep them byte-identical." That rule is currently **violated**:
the typed fields have no C representation at all. (See §6 for the drift this has already produced.)

---

## 2. OSC — 9 cases (`conformance/harness.c:80-90`)

All nine inputs are OSC strings (`ESC ] ... ` terminated by `BEL` or `ST`). An OSC payload is
control data consumed by the OSC parser; it is never written to the screen. Therefore the correct
plaintext is `""` for all nine.

The one case that superficially looks like it prints text is `osc_8_hyperlink_open`: the bytes
`Click Here` sit **inside** the OSC string (between the second `;` and the `ST`), so they are
hyperlink payload, not screen text. Evidence that the payload is consumed rather than printed:
`src/terminal/stream.zig:124` (`start_hyperlink: StartHyperlink`), `src/terminal/stream.zig:433`
(`pub const StartHyperlink`), `src/termio/stream_handler.zig:352`
(`.start_hyperlink => try self.startHyperlink(value.uri, value.id)`), `src/termio/stream_handler.zig:817-819`.

| case name                                  | input bytes                                          | plaintext assertable                                  | proposed C string literal or alternative assertion                                                                                                                                                                                                                                                                                                                    |
| ------------------------------------------ | ---------------------------------------------------- | ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `osc_0_set_title` (`harness.c:81`)         | `ESC ] 0 ; Test Window Title BEL`                    | no                                                    | title assertion: `expected_title = "Test Window Title"` (`cases/osc/cases.zig:16`)                                                                                                                                                                                                                                                                                    |
| `osc_2_set_title` (`harness.c:82`)         | `ESC ] 2 ; Another Title BEL`                        | no                                                    | title assertion: `expected_title = "Another Title"` (`cases/osc/cases.zig:24`)                                                                                                                                                                                                                                                                                        |
| `osc_10_set_fg` (`harness.c:83`)           | `ESC ] 10 ; #ff0000 BEL`                             | no                                                    | foreground-colour assertion; Zig file records **no** expectation for it (`cases/osc/cases.zig:32-35`, all `null`) — needs a new typed field, e.g. `expected_fg = "#ff0000"`                                                                                                                                                                                           |
| `osc_11_set_bg` (`harness.c:84`)           | `ESC ] 11 ; #00ff00 BEL`                             | no                                                    | background-colour assertion; no Zig expectation (`cases/osc/cases.zig:40-43`) — new typed field needed                                                                                                                                                                                                                                                                |
| `osc_12_set_cursor` (`harness.c:85`)       | `ESC ] 12 ; #0000ff BEL`                             | no                                                    | cursor-colour assertion; no Zig expectation (`cases/osc/cases.zig:48-51`) — new typed field needed                                                                                                                                                                                                                                                                    |
| `osc_7_set_pwd` (`harness.c:86`)           | `ESC ] 7 ; file:///home/user/documents BEL`          | no                                                    | pwd-report assertion: `expected_pwd = "file:///home/user/documents"` (`cases/osc/cases.zig:58`); terminal side is `report_pwd` (`src/termio/stream_handler.zig:349`)                                                                                                                                                                                                  |
| `osc_8_hyperlink_open` (`harness.c:87-88`) | `ESC ] 8 ; url=https://example.com;Click Here ESC \` | **no** — `Click Here` is OSC payload, not screen text | hyperlink-URI assertion: `expected_hyperlink = "https://example.com"` (`cases/osc/cases.zig:75`). **UNKNOWN:** the Zig value implies the repo's parser strips a `url=` prefix; standard OSC 8 splits `OSC 8 ; params ; URI` so the URI would be `Click Here`. The OSC-8 payload-split code was not read. Either way the payload is consumed, so plaintext stays `""`. |
| `osc_8_hyperlink_close` (`harness.c:89`)   | `ESC ] 8 ; ; ESC \`                                  | no                                                    | hyperlink-end assertion: `expected_hyperlink = ""` (`cases/osc/cases.zig:83`); terminal side is `end_hyperlink` (`src/terminal/stream.zig:117`, `src/termio/stream_handler.zig:345`, `:821-822`)                                                                                                                                                                      |
| `osc_52_clipboard_copy` (`harness.c:90`)   | `ESC ] 52 ; c ; SGVsbG8gV29ybGQ= BEL`                | no                                                    | clipboard assertion: `expected_clipboard = "Hello World"` (base64-decoded, `cases/osc/cases.zig:89`); terminal side is `clipboard_contents` (`src/termio/stream_handler.zig:353`)                                                                                                                                                                                     |

Reachability caveat for the OSC assertions: title, clipboard and pwd are dispatched at the **termio**
layer (`src/termio/stream_handler.zig:349`, `:353`), whereas the C harness drives only the
**terminal** API (`ghostty_terminal_reset` / `_resize` / `_vt_write`, `conformance/harness.c:190-197`).
Whether `libghostty-vt` exposes title/clipboard readback at the terminal layer is **UNKNOWN**
(not verified; `conformance/harness.c` never calls such an API).

---

## 3. CHARSET — 8 cases (`conformance/harness.c:93-101`)

Each input is a designator / locking-shift control with no printable payload, so the screen stays
empty: correct plaintext `""` for all eight. The observable effect is terminal _state_
(`configure_charset`, `src/termio/stream_handler.zig:359`; charset tables in `src/terminal/charsets.zig`).

| case name                                  | input bytes   | plaintext assertable | proposed C string literal or alternative assertion                                          |
| ------------------------------------------ | ------------- | -------------------- | ------------------------------------------------------------------------------------------- |
| `charset_g0_uk` (`harness.c:94`)           | `ESC ( A`     | no                   | charset-state assertion: `expected_charset = "UK"` (`cases/charset/cases.zig:13`)           |
| `charset_g0_us` (`harness.c:95`)           | `ESC ( B`     | no                   | charset-state assertion: `expected_charset = "US"` (`cases/charset/cases.zig:19`)           |
| `charset_g1_line_drawing` (`harness.c:96`) | `ESC ) 0`     | no                   | charset-state assertion: `expected_charset = "Line Drawing"` (`cases/charset/cases.zig:23`) |
| `charset_g1_british` (`harness.c:97`)      | `ESC ) 1`     | no                   | charset-state assertion: `expected_charset = "British"` (`cases/charset/cases.zig:28`)      |
| `charset_ss2` (`harness.c:98`)             | `0x0E` (SS2)  | no                   | charset-state assertion: `expected_charset = "G1"` (`cases/charset/cases.zig:33`)           |
| `charset_ss3` (`harness.c:99`)             | `0x0F` (SS3)  | no                   | charset-state assertion: `expected_charset = "G2"` (`cases/charset/cases.zig:38`)           |
| `charset_lock_g1` (`harness.c:100`)        | `ESC ~` (LS1) | no                   | charset-state assertion: `expected_charset = "G1 Lock"` (`cases/charset/cases.zig:43`)      |
| `charset_lock_g0` (`harness.c:101`)        | `ESC n` (LS0) | no                   | charset-state assertion: `expected_charset = "G0 Lock"` (`cases/charset/cases.zig:48`)      |

Alternative for this category that yields a **real plaintext** assertion: extend the input by one
printable probe byte and assert the transliterated glyph (e.g. `ESC ) 0` + `a` → the line-drawing
codepoint for `a`; `ESC ( A` + `#` → the UK-charset pound sign). The exact mapping is **UNKNOWN**
here — `src/terminal/charsets.zig` was located but not read.

---

## 4. MODE — 12 cases (`conformance/harness.c:104-116`)

All twelve are DEC private mode set/reset controls with no printable payload: correct plaintext
`""` for all twelve. The observable effect is mode state.

| case name                                  | input bytes                           | plaintext assertable | proposed C string literal or alternative assertion                                                                                      |
| ------------------------------------------ | ------------------------------------- | -------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `mode_decckm_horiz` (`harness.c:105`)      | `ESC [ ? 1 l`                         | no                   | mode assertion: `expected_active_mode = "Normal Cursor"`, `expected_mode_reversed = false` (`cases/mode/cases.zig:14-15`)               |
| `mode_decckm_app` (`harness.c:106`)        | `ESC [ ? 1 h`                         | no                   | mode assertion: `"Application Cursor"`, `true` (`cases/mode/cases.zig:20-21`)                                                           |
| `mode_deccnm_origin` (`harness.c:107`)     | `ESC [ ? 6 l`                         | no                   | mode assertion: `"Normal Mode"`, `false` (`cases/mode/cases.zig:26-27`)                                                                 |
| `mode_deccnm_app` (`harness.c:108`)        | `ESC [ ? 6 h`                         | no                   | mode assertion: `"Origin Mode"`, `true` (`cases/mode/cases.zig:32-33`)                                                                  |
| `mode_decscnm_reverse` (`harness.c:109`)   | `ESC [ ? 5 h`                         | no                   | mode assertion: `"Reverse Video"`, `true` (`cases/mode/cases.zig:38-39`)                                                                |
| `mode_decscnm_normal` (`harness.c:110`)    | `ESC [ ? 5 l`                         | no                   | mode assertion: `"Normal Video"`, `false` (`cases/mode/cases.zig:44-45`)                                                                |
| `mode_decawm_autowrap` (`harness.c:111`)   | `ESC ? 7 h` — **malformed, see §6.1** | no                   | mode assertion: `"Auto Wrap"`, `true` (`cases/mode/cases.zig:50-51`); the assertion should be paired with an input fix to `ESC [ ? 7 h` |
| `mode_decawm_noautowrap` (`harness.c:112`) | `ESC ? 7 l` — **malformed, see §6.1** | no                   | mode assertion: `"No Auto Wrap"`, `false` (`cases/mode/cases.zig:56-57`); input fix to `ESC [ ? 7 l`                                    |
| `mode_decipam_visible` (`harness.c:113`)   | `ESC [ ? 25 h` (DECTCEM show)         | no                   | mode assertion: `"Cursor Visible"`, `false` (`cases/mode/cases.zig:62-63`)                                                              |
| `mode_decipam_hidden` (`harness.c:114`)    | `ESC [ ? 25 l` (DECTCEM hide)         | no                   | mode assertion: `"Cursor Hidden"`, `false` (`cases/mode/cases.zig:86-87`) — see §6.3 on the `expected_mode_reversed` value              |
| `mode_decarm_8bit` (`harness.c:115`)       | `ESC [ ? 3 h`                         | no                   | mode assertion: `"8-Bit Mode"`, `true` (`cases/mode/cases.zig:68-69`)                                                                   |
| `mode_decarm_7bit` (`harness.c:116`)       | `ESC [ 3 l`                           | no                   | mode assertion: `"7-Bit Mode"`, `false` (`cases/mode/cases.zig:74-75`)                                                                  |

Reachability: mode state lives in `src/terminal/modes.zig` (located, not read). Whether a mode
readback is exposed on the `libghostty-vt` C surface used by `conformance/harness.c` is **UNKNOWN**.

---

## 5. KITTY-GFX — 5 cases (`conformance/harness.c:132-138`)

These are APC sequences (`ESC _ ... ESC \`), i.e. image-protocol control data. Nothing is printed:
correct plaintext `""` for all five. Kitty handling lives in `src/terminal/apc.zig` (located, not read).

| case name                              | input bytes                                             | plaintext assertable | proposed C string literal or alternative assertion                                                                                   |
| -------------------------------------- | ------------------------------------------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `kitty_init` (`harness.c:133-134`)     | `ESC _ G i=32;a=s;c=32;k=16;s=100;t=100;f=24;v=1 ESC \` | no                   | graphics-action assertion: `expected_action = "Init"` (`cases/kitty-gfx/cases.zig:16`); `expected_uri/width/height` are `null` there |
| `kitty_progress` (`harness.c:135`)     | `ESC _ G p=1;f=100 ESC \`                               | no                   | graphics-action assertion: `expected_action = "Progress"` (`cases/kitty-gfx/cases.zig:24`)                                           |
| `kitty_end` (`harness.c:136`)          | `ESC _ G m=1 ESC \`                                     | no                   | graphics-action assertion: `expected_action = "End"` (`cases/kitty-gfx/cases.zig:32`)                                                |
| `kitty_reset` (`harness.c:137`)        | `ESC _ G m=2 ESC \`                                     | no                   | graphics-action assertion: `expected_action = "Reset"` (`cases/kitty-gfx/cases.zig:40`)                                              |
| `kitty_transparency` (`harness.c:138`) | `ESC _ G d=100 ESC \`                                   | no                   | graphics-action assertion: `expected_action = "Transparency"` (`cases/kitty-gfx/cases.zig:48`)                                       |

Whether the terminal-level C API surfaces a kitty graphics action for readback is **UNKNOWN**
(no such API call exists in `conformance/harness.c`; the file only uses terminal + formatter calls,
`conformance/harness.c:190-232`).

---

## 6. Drift and defects found while reading (adjacent to the 34, worth fixing in the same pass)

**6.1 Two MODE cases do not parse as DECAWM at all.**
`conformance/harness.c:111-112` use `ESC "?7h"` / `ESC "?7l"` — the CSI introducer `[` is missing, so
these bytes are `ESC` + `?` + `7` + `h`, not `CSI ? 7 h`. Contrast `ESC "[?3h"` at
`conformance/harness.c:115`. The identical mistake is in the Zig source of truth
(`cases/mode/cases.zig:50`, `:56`), so both copies are wrong together and the mirror check cannot
catch it. Correct form: `ESC "[?7h"` / `ESC "[?7l"`.

**6.2 The Zig mode file mislabels a case.**
`cases/mode/cases.zig:60` names `ESC [ ? 25 h` `"mode_decom_origin"`, but `CSI ? 25 h` is DECTCEM
(show cursor); DECOM is `CSI ? 6 h` (`cases/mode/cases.zig:32`). The C array names it correctly
(`"mode_decipam_visible"`, `conformance/harness.c:113`), so the two "byte-identical" copies disagree
on the case _name_ as well as the fields.

**6.3 `expected_mode_reversed` semantics are unclear for DECTCEM.**
`cases/mode/cases.zig:86-87` records `"Cursor Hidden"` with `expected_mode_reversed = false`, while
the default state of DECTCEM is _visible_ — under the reading "reversed == non-default", this should
be `true`. **UNKNOWN** whether the field means "non-default" or "inverted"; needs a definition before
it can be asserted mechanically.

**6.4 The Zig source of truth has drifted ahead of the C mirror.**

- OSC: Zig has 10 entries (extra `osc_9_set_pwd`, `cases/osc/cases.zig:62-68`); C has 9
  (`conformance/harness.c:81-90`); `conformance/README.md:22` still says "9 OSC cases".
- MODE: Zig has 15 entries (`cases/mode/cases.zig:10-101`); C has 12 (`conformance/harness.c:105-116`).
  Missing from C: `mode_decim` (`cases/mode/cases.zig:78-82`), `mode_decilm` (`:90-94`),
  `mode_riscap` (`:96-100`).
- `conformance/README.md:145-146` ("Keep them byte-identical") is therefore already false.

**6.5 The struct cannot express "expect empty".** See §1. This is the root cause of the 34.

---

## 7. Counts

- **Assertable as plaintext today (non-empty literal): 0 of 34.**
- **Assertable as plaintext today (including an explicit empty assertion): 0 of 34** — the empty
  string is the "no assertion" sentinel (`conformance/harness.c:27`, `:201`). After the sentinel
  fix in §1, all 34 become assertable as "expect empty", which is a strictly better crash/no-crash
  check but still weak.
- **Need a different assertion type: 34 of 34.** Breakdown: OSC 9 (title 2, colour 3, pwd 1,
  hyperlink 2, clipboard 1), charset 8 (charset state), mode 12 (mode state), kitty-gfx 5 (graphics
  action). Every one of these typed expectations already exists in
  `conformance/cases/{osc,charset,mode,kitty-gfx}/cases.zig`; three OSC colour cases have no Zig
  expectation yet and need new typed fields.

---

## 8. Top 3 highest-value additions

**1. OSC 8 hyperlink state (2 cases: `harness.c:87-89`) — cell-level artifact, cheap readback.**
Hyperlink state is the only one of the 34 whose observable lives _in the grid_, not in a side
channel: `GHOSTTY_CELL_DATA_HAS_HYPERLINK` (`include/ghostty/vt/screen.h:192`), row-level flag
(`include/ghostty/vt/screen.h:291`), and a URI getter
`ghostty_grid_ref_hyperlink_uri` (`wasm/include/ghostty-vt.h:398`; `docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md:55`
lists `grid_ref.h` among the C headers). Asserting the URI on the first cell turns two no-op cases
into two real parser assertions. **UNKNOWN:** whether the same symbol is exported from the
`include/ghostty/vt/` headers the C harness links against — the `wasm/` copy was confirmed, the
`include/` copy was not checked.

**2. MODE state (12 cases: `harness.c:105-116`) — largest block of dead assertions.**
Twelve of the 34 (35 %) assert nothing. A single mode readback (`src/terminal/modes.zig`) plus the
already-written `expected_active_mode` / `expected_mode_reversed` fields
(`cases/mode/cases.zig:14-15` etc.) converts all twelve into real assertions, and it is the block
most likely to catch genuine regressions (cursor key mode, origin mode, autowrap, reverse video).
Fix `harness.c:111-112` in the same change (§6.1) or the two autowrap cases stay vacuous.

**3. CHARSET via a probe byte (8 cases: `harness.c:94-101`) — the only route to a genuine plaintext assertion.**
Every other category needs a new readback API; charset can instead be asserted _as plaintext_ by
appending one printable byte to each input and comparing the transliterated glyph (the screen then
contains exactly one character, e.g. `ESC ) 0` + `a`). This keeps the harness's single
plaintext-comparison machinery (`conformance/harness.c:225-226`) and reuses it unchanged. Requires
the translation table in `src/terminal/charsets.zig` (**UNKNOWN**, not read) to derive the expected
glyph, and requires the empty-string sentinel fix (§1) only if a case must still expect empty.

Runner-up (4th): **OSC 0/2 title (2 cases)** — the classic end-to-end assertion, but title is
dispatched at the termio layer (`src/termio/stream_handler.zig:349` is `report_pwd`; title is a
sibling handler that was not located), so reachability from the terminal-only C API is **UNKNOWN**
and may require a different harness entry point.

---

## 9. Explicit UNKNOWNs (not guessed)

1. Whether the repo's OSC 8 parser yields URI `"https://example.com"` (as `cases/osc/cases.zig:75`
   states) or `"Click Here"` (standard `OSC 8 ; params ; URI` split). The payload-split code was not
   read. Does not affect the plaintext conclusion.
2. Whether `libghostty-vt` exposes readback for: terminal title, clipboard contents, pwd report,
   mode state, charset state, kitty graphics action. Only the terminal + formatter API is used
   today (`conformance/harness.c:190-232`).
3. The exact charset transliteration table (`src/terminal/charsets.zig`) needed for the probe-byte
   plaintext assertions.
4. The intended semantics of `expected_mode_reversed` (§6.3).
5. Whether `ghostty_grid_ref_hyperlink_uri` is exported from `include/ghostty/vt/` (only the `wasm/`
   copy was confirmed).
