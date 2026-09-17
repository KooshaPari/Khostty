/*
 * VT/ANSI Conformance Test Suite for Khostty
 *
 * Validates that Khostty's libghostty-vt preserves Ghostty's terminal
 * emulation behavior across a comprehensive corpus of VT/ANSI sequences.
 *
 * Usage:
 *   ./conformance_test
 *
 * Build:
 *   cc -Iinclude conformance/harness.c zig-out/lib/libghostty-vt.a -o conformance_test
 */

#include <ghostty/vt.h>
#include <ghostty/vt/formatter.h>
#include <ghostty/vt/build_info.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---------- Test case model ---------- */

typedef struct {
    const char *name;
    const char *input;
    const char *expected_plain; /* empty means no plaintext assertion */
} TestCase;

static size_t g_passed = 0;
static size_t g_failed = 0;
static size_t g_total = 0;

#define CAT_COUNT 8
static size_t g_cat_pass[CAT_COUNT] = {0};
static size_t g_cat_fail[CAT_COUNT] = {0};
static const char *g_cat_names[CAT_COUNT] = {
    "sgr", "cursor", "osc", "charset",
    "mode", "scroll", "kitty-gfx", "edge",
};

/* ESC as octal to avoid hex-ambiguity with following hex digits. */
#define ESC "\033"

/* ---------- Cases (mirror conformance/cases/<category>/cases.zig) ---------- */

static const TestCase SGR_CASES[] = {
    {"sgr_reset_all", ESC "[0m", ""},
    {"sgr_bold", ESC "[1mText", "Text"},
    {"sgr_dim", ESC "[2mText", "Text"},
    {"sgr_italic", ESC "[3mText", "Text"},
    {"sgr_underline", ESC "[4mText", "Text"},
    {"sgr_blink", ESC "[5mText", "Text"},
    {"sgr_reverse", ESC "[7mText", "Text"},
    {"sgr_conceal", ESC "[8mText", "Text"},
    {"sgr_strikethrough", ESC "[9mText", "Text"},
    {"sgr_rgb_fg_red", ESC "[38;2;255;0;0mX", "X"},
    {"sgr_rgb_bg_green", ESC "[48;2;0;255;0mX", "X"},
    {"sgr_256_fg", ESC "[38;5;196mX", "X"},
    {"sgr_combined_bold_underline", ESC "[1;4mText", "Text"},
    {"sgr_reset_bold", ESC "[22mText", "Text"},
    {"sgr_reset_default_fg", ESC "[39mText", "Text"},
    {"sgr_reset_default_bg", ESC "[49mText", "Text"},
    {"sgr_resets_all", ESC "[1;3;4mHello" ESC "[0m World", "Hello World"},
};

static const TestCase CURSOR_CASES[] = {
    {"cursor_up", ESC "[5A", ""},
    {"cursor_down", ESC "[3B", ""},
    {"cursor_right", ESC "[5C", ""},
    {"cursor_left", "Hello" ESC "[3D", "Hello"},
    {"cursor_position_5_10", ESC "[5;10H", ""},
    {"cursor_home", "Hello" ESC "[H", "Hello"},
    {"cursor_save_restore", "Hello" ESC "7World" ESC "8", "HelloWorld"},
    {"cursor_default_up", ESC "[A", ""},
    {"cursor_default_down", ESC "[B", ""},
    {"cursor_default_right", ESC "[C", ""},
};

static const TestCase OSC_CASES[] = {
    {"osc_0_set_title", ESC "]0;Test Window Title", "\x07"},
    {"osc_2_set_title", ESC "]2;Another Title", "\x07"},
    {"osc_10_set_fg", ESC "]10;#ff0000", "\x07"},
    {"osc_11_set_bg", ESC "]11;#00ff00", "\x07"},
    {"osc_12_set_cursor", ESC "]12;#0000ff", "\x07"},
    {"osc_7_set_pwd", ESC "]7;file:///home/user/documents", "\x07"},
    {"osc_8_hyperlink_open",
     ESC "]8;url=https://example.com;Click Here" ESC "\\", ""},
    {"osc_8_hyperlink_close", ESC "]8;;" ESC "\\", ""},
    {"osc_52_clipboard_copy", ESC "]52;c;SGVsbG8gV29ybGQ=", "\x07"},
};

static const TestCase CHARSET_CASES[] = {
    {"charset_g0_uk", ESC "(A", ""},
    {"charset_g0_us", ESC "(B", ""},
    {"charset_g1_line_drawing", ESC ")0", ""},
    {"charset_g1_british", ESC ")1", ""},
    {"charset_ss2", "\x0e", ""},
    {"charset_ss3", "\x0f", ""},
    {"charset_lock_g1", ESC "~", ""},
    {"charset_lock_g0", ESC "n", ""},
};

static const TestCase MODE_CASES[] = {
    {"mode_decckm_horiz", ESC "[?1l", ""},
    {"mode_decckm_app", ESC "[?1h", ""},
    {"mode_deccnm_origin", ESC "[?6l", ""},
    {"mode_deccnm_app", ESC "[?6h", ""},
    {"mode_decscnm_reverse", ESC "[?5h", ""},
    {"mode_decscnm_normal", ESC "[?5l", ""},
    {"mode_decawm_autowrap", ESC "?7h", ""},
    {"mode_decawm_noautowrap", ESC "?7l", ""},
    {"mode_decipam_visible", ESC "[?25h", ""},
    {"mode_decipam_hidden", ESC "[?25l", ""},
    {"mode_decarm_8bit", ESC "[?3h", ""},
    {"mode_decarm_7bit", ESC "[3l", ""},
};

static const TestCase SCROLL_CASES[] = {
    {"scroll_set_region", ESC "[5;20r", ""},
    {"scroll_set_full", ESC "[1;24r", ""},
    {"scroll_up", "Line 1\nLine 2\nLine 3\n" ESC "M", "Line 1\nLine 2\nLine 3\n"},
    {"scroll_down", "Line 1\nLine 2\nLine 3\n" ESC "D", "Line 1\nLine 2\nLine 3\n"},
    {"scroll_ind", "Line 1\n" ESC "D", "Line 1\n"},
    {"scroll_ri", ESC "MLine 1\n", "Line 1\n"},
    {"scroll_su", "Line 1\nLine 2\nLine 3\n" ESC "[2S", "Line 1\nLine 2\nLine 3\n"},
};

static const TestCase KITTY_CASES[] = {
    {"kitty_init",
     ESC "_Gi=32;a=s;c=32;k=16;s=100;t=100;f=24;v=1" ESC "\\", ""},
    {"kitty_progress", ESC "_Gp=1;f=100" ESC "\\", ""},
    {"kitty_end", ESC "_Gm=1" ESC "\\", ""},
    {"kitty_reset", ESC "_Gm=2" ESC "\\", ""},
    {"kitty_transparency", ESC "_Gd=100" ESC "\\", ""},
};

static const TestCase EDGE_CASES[] = {
    {"incomplete_esc_bracket", ESC "[", ""},
    {"incomplete_csi_param", ESC "[1;", ""},
    {"unrecognized_escape", ESC "Z", ""},
    {"empty_string", "", ""},
    {"null_like", "\x00\x00\x00", ""},
    {"very_long_osc", ESC "]0;AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\x07", ""},
    {"mixed_sequences",
     ESC "[1;31mHello" ESC "[0m World" ESC "[44mTest" ESC "[0m",
     "Hello World Test"},
    {"unicode_char", "\xc3\xa9\xc3\xa8\xc3\xaa",
     "\xc3\xa9\xc3\xa8\xc3\xaa"},
    {"wide_char_test", "\xe4\xb8\xad\xe6\x96\x87",
     "\xe4\xb8\xad\xe6\x96\x87"},
    {"tab_expansion", "\t\t\t", ""},
    {"cr_lf", "\r\n\r\n", ""},
    {"bell", "\x07", ""},
    {"backspace", "\x08", ""},
    {"del_char", "\x7f", ""},
    {"invalid_sgr_param", ESC "[999m", ""},
    {"negative_param", ESC "[-5m", ""},
};

/* ---------- Runner ---------- */

typedef struct {
    uint8_t *data;
    size_t len;
    size_t cap;
} BufferWriter;

static bool buf_writer_write(void *ctx, const uint8_t *data, size_t len) {
    BufferWriter *bw = (BufferWriter *)ctx;
    if (bw->len + len > bw->cap) {
        size_t newcap = bw->cap ? bw->cap * 2 : 256;
        while (newcap < bw->len + len) newcap *= 2;
        uint8_t *n = (uint8_t *)realloc(bw->data, newcap);
        if (!n) return false;
        bw->data = n;
        bw->cap = newcap;
    }
    memcpy(bw->data + bw->len, data, len);
    bw->len += len;
    return true;
}

static void run_category(const char *category, const TestCase *cases, size_t n,
                         int cat_index, GhosttyTerminal terminal) {
    printf("\n--- %s Tests (%zu) ---\n", category, n);
    for (size_t i = 0; i < n; i++) {
        const TestCase *tc = &cases[i];
        ghostty_terminal_reset(terminal);
        ghostty_terminal_resize(terminal, 80, 24, 0, 0);

        ghostty_terminal_vt_write(
            terminal, (const uint8_t *)tc->input, strlen(tc->input));

        g_total++;
        bool ok = true;

        if (strlen(tc->expected_plain) > 0) {
            GhosttyFormatterTerminalOptions opts;
            memset(&opts, 0, sizeof(opts));
            opts.size = sizeof(opts);
            opts.emit = GHOSTTY_FORMATTER_FORMAT_PLAIN;
            opts.unwrap = false;
            opts.trim = false;
            opts.extra.size = sizeof(opts.extra);
            opts.selection = NULL;

            GhosttyFormatter fmt;
            GhosttyResult ar =
                ghostty_formatter_terminal_new(NULL, &fmt, terminal, opts);
            if (ar != GHOSTTY_SUCCESS) {
                printf("  [FAIL] %s: formatter alloc failed (%d)\n",
                       tc->name, (int)ar);
                ok = false;
            } else {
                BufferWriter bw = {0};
                GhosttyWriter writer = { .write = buf_writer_write,
                                         .userdata = &bw };
                GhosttyResult r = ghostty_formatter_format(fmt, writer);
                if (r != GHOSTTY_SUCCESS) {
                    printf("  [FAIL] %s: format returned %d\n",
                           tc->name, (int)r);
                    ok = false;
                } else if (bw.len != strlen(tc->expected_plain) ||
                           memcmp(bw.data, tc->expected_plain, bw.len) != 0) {
                    printf("  [FAIL] %s: expected '%s' got '%.*s'\n",
                           tc->name, tc->expected_plain,
                           (int)bw.len, (const char *)bw.data);
                    ok = false;
                }
                free(bw.data);
                ghostty_formatter_free(fmt);
            }
        }

        if (ok) {
            g_passed++;
            g_cat_pass[cat_index]++;
            printf("  [PASS] %s\n", tc->name);
        } else {
            g_failed++;
            g_cat_fail[cat_index]++;
        }
    }
}

int main(void) {
    printf("=== VT/ANSI Conformance Test Suite (Khostty) ===\n");

    GhosttyString version;
    if (ghostty_build_info(GHOSTTY_BUILD_INFO_VERSION_STRING, &version) ==
        GHOSTTY_SUCCESS) {
        printf("libghostty-vt version: %.*s\n", (int)version.len,
               (const char *)version.ptr);
        ghostty_free(NULL, (uint8_t *)version.ptr, version.len);
    }

    GhosttyTerminal terminal = NULL;
    GhosttyResult r = ghostty_terminal_new(NULL, &terminal, 80, 24);
    if (r != GHOSTTY_SUCCESS || terminal == NULL) {
        fprintf(stderr, "ghostty_terminal_new failed: %d\n", (int)r);
        return 1;
    }
    printf("Initializing terminal: OK (80x24)\n");
    printf("Running conformance tests...\n");

    run_category("sgr", SGR_CASES,
                 sizeof(SGR_CASES) / sizeof(SGR_CASES[0]), 0, terminal);
    run_category("cursor", CURSOR_CASES,
                 sizeof(CURSOR_CASES) / sizeof(CURSOR_CASES[0]), 1, terminal);
    run_category("osc", OSC_CASES,
                 sizeof(OSC_CASES) / sizeof(OSC_CASES[0]), 2, terminal);
    run_category("charset", CHARSET_CASES,
                 sizeof(CHARSET_CASES) / sizeof(CHARSET_CASES[0]), 3, terminal);
    run_category("mode", MODE_CASES,
                 sizeof(MODE_CASES) / sizeof(MODE_CASES[0]), 4, terminal);
    run_category("scroll", SCROLL_CASES,
                 sizeof(SCROLL_CASES) / sizeof(SCROLL_CASES[0]), 5, terminal);
    run_category("kitty-gfx", KITTY_CASES,
                 sizeof(KITTY_CASES) / sizeof(KITTY_CASES[0]), 6, terminal);
    run_category("edge", EDGE_CASES,
                 sizeof(EDGE_CASES) / sizeof(EDGE_CASES[0]), 7, terminal);

    ghostty_terminal_free(terminal);

    printf("\n=== VT/ANSI Conformance Test Results ===\n");
    printf("Passed: %zu\n", g_passed);
    printf("Failed: %zu\n", g_failed);
    printf("Total:  %zu\n", g_total);
    if (g_total > 0) {
        printf("Success Rate: %zu%%\n", (g_passed * 100) / g_total);
    }
    printf("\n--- Per Category ---\n");
    for (size_t i = 0; i < CAT_COUNT; i++) {
        size_t p = g_cat_pass[i], f = g_cat_fail[i];
        size_t t = p + f;
        if (t == 0) continue;
        printf("  %-10s %zu/%zu (%zu%%)\n",
               g_cat_names[i], p, t, (p * 100) / t);
    }
    printf("\nConformance test run complete.\n");

    return (g_failed == 0) ? 0 : 1;
}