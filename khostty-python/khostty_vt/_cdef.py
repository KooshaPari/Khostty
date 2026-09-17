"""Hand-written cffi declarations mirroring ``include/ghostty/vt/*.h``.

Nothing here is compiled: these declarations describe an already-built shared
library that is opened with ``dlopen``. That makes this module the single place
where the C shapes live, and it makes :data:`STRUCT_SIZES` the contract that
:func:`khostty_vt._ffi.validate_struct_sizes` checks against the library's own
type manifest.

C enums are declared as ``int``. The library specifies that its enums are
backed by C ``int`` (``GHOSTTY_ENUM_TYPED`` expands to ``: int``), so the
declarations remain ABI-correct while keeping the Python side free of enum
plumbing.

``size_t`` and the ``uintN_t`` family are used directly: cffi provides them as
primitives of the correct platform width. Declaring ``typedef ... size_t;``
instead would make it an opaque type, which cannot appear as a struct field.
"""

from __future__ import annotations

__all__ = ["CDEF", "STRUCT_SIZES"]

#: Struct sizes this module's declarations were written against, in bytes.
#:
#: Reproducing a C layout by hand is the one thing ABI-mode cffi cannot check
#: for you, so these are asserted against the library's own type manifest by
#: the test suite and by :func:`validate_struct_sizes`.
STRUCT_SIZES = {
    "GhosttyString": 16,
    "GhosttyBuffer": 24,
    "GhosttyWriter": 16,
    "GhosttyReader": 16,
    "GhosttyColorRgb": 3,
    "GhosttyGridRef": 24,
    "GhosttyTerminalScrollbar": 24,
    "GhosttyMousePosition": 8,
    "GhosttyMouseEncoderSize": 40,
    "GhosttySelection": 64,
    "GhosttySelectionBuffer": 24,
    "GhosttyStyleColor": 16,
    "GhosttyStyle": 72,
    "GhosttyFormatterScreenExtra": 16,
    "GhosttyFormatterTerminalExtra": 32,
    "GhosttyFormatterTerminalOptions": 56,
}


# The declarations mirror include/ghostty/vt/*.h. C enums are declared as int
# parameters and ordinary int constants, because the library's enums are
# specified to be backed by C `int` (GHOSTTY_ENUM_TYPED expands to `: int`).
CDEF = r"""
/* size_t, uint8_t, and friends are cffi primitives of the correct platform
   width, so they are used directly rather than re-typedef'd. Declaring
   `typedef ... size_t;` would make it an opaque type, which cannot be a
   struct field. */

typedef struct GhosttyTerminalImpl *GhosttyTerminal;
typedef struct GhosttySnapshotDecoderImpl *GhosttySnapshotDecoder;
typedef struct GhosttySearchImpl *GhosttySearch;
typedef struct GhosttyFormatterImpl *GhosttyFormatter;
typedef struct GhosttyKeyEventImpl *GhosttyKeyEvent;
typedef struct GhosttyKeyEncoderImpl *GhosttyKeyEncoder;
typedef struct GhosttyMouseEventImpl *GhosttyMouseEvent;
typedef struct GhosttyMouseEncoderImpl *GhosttyMouseEncoder;

typedef struct {
    const uint8_t *ptr;
    size_t len;
} GhosttyString;

typedef struct {
    uint8_t *ptr;
    size_t cap;
    size_t len;
} GhosttyBuffer;

typedef _Bool (*GhosttyWriterFn)(void *userdata, const uint8_t *data, size_t len);
typedef struct {
    GhosttyWriterFn write;
    void *userdata;
} GhosttyWriter;

typedef _Bool (*GhosttyReaderFn)(void *userdata, uint8_t *buffer, size_t capacity, size_t *out_read);
typedef struct {
    GhosttyReaderFn read;
    void *userdata;
} GhosttyReader;

typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
} GhosttyColorRgb;

typedef struct {
    size_t size;
    void *node;
    uint16_t x;
    uint16_t y;
} GhosttyGridRef;

typedef struct {
    size_t total;
    size_t offset;
    size_t len;
} GhosttyTerminalScrollbar;

typedef struct {
    size_t size;
    GhosttyGridRef start;
    GhosttyGridRef end;
    _Bool rectangle;
} GhosttySelection;

typedef struct {
    GhosttySelection *ptr;
    size_t cap;
    size_t len;
} GhosttySelectionBuffer;

typedef union {
    uint8_t palette;
    GhosttyColorRgb rgb;
    uint64_t padding;
} GhosttyStyleColorValue;

typedef struct {
    int tag;
    GhosttyStyleColorValue value;
} GhosttyStyleColor;

typedef struct {
    size_t size;
    GhosttyStyleColor fg_color;
    GhosttyStyleColor bg_color;
    GhosttyStyleColor underline_color;
    _Bool bold;
    _Bool italic;
    _Bool faint;
    _Bool blink;
    _Bool inverse;
    _Bool invisible;
    _Bool strikethrough;
    _Bool overline;
    int underline;
} GhosttyStyle;

typedef struct {
    size_t size;
    _Bool cursor;
    _Bool style;
    _Bool hyperlink;
    _Bool protection;
    _Bool kitty_keyboard;
    _Bool charsets;
} GhosttyFormatterScreenExtra;

typedef struct {
    size_t size;
    _Bool palette;
    _Bool modes;
    _Bool scrolling_region;
    _Bool tabstops;
    _Bool pwd;
    _Bool keyboard;
    GhosttyFormatterScreenExtra screen;
} GhosttyFormatterTerminalExtra;

typedef struct {
    size_t size;
    int emit;
    _Bool unwrap;
    _Bool trim;
    GhosttyFormatterTerminalExtra extra;
    const GhosttySelection *selection;
} GhosttyFormatterTerminalOptions;

int ghostty_terminal_new(const void *allocator, GhosttyTerminal *terminal, uint16_t cols, uint16_t rows);
void ghostty_terminal_free(GhosttyTerminal terminal);
void ghostty_terminal_reset(GhosttyTerminal terminal);
int ghostty_terminal_resize(GhosttyTerminal terminal, uint16_t cols, uint16_t rows, uint32_t cell_width_px, uint32_t cell_height_px);
int ghostty_terminal_set(GhosttyTerminal terminal, int option, const void *value);
void ghostty_terminal_vt_write(GhosttyTerminal terminal, const uint8_t *data, size_t len);
int ghostty_terminal_vt_write_until_ground(GhosttyTerminal terminal, const uint8_t *data, size_t len, size_t *out_consumed);
int ghostty_terminal_get(GhosttyTerminal terminal, int data, void *out);

int ghostty_snapshot_encode_alloc(GhosttyTerminal terminal, const void *allocator, uint8_t **out_ptr, size_t *out_len);
int ghostty_snapshot_encode_buf(GhosttyTerminal terminal, uint8_t *buf, size_t buf_len, size_t *out_written);
int ghostty_snapshot_decoder_new_buf(const void *allocator, GhosttySnapshotDecoder *decoder, const uint8_t *ptr, size_t len);
void ghostty_snapshot_decoder_free(GhosttySnapshotDecoder decoder);
int ghostty_snapshot_decoder_decode(GhosttySnapshotDecoder decoder, GhosttyTerminal *terminal);

int ghostty_formatter_terminal_new(const void *allocator, GhosttyFormatter *formatter, GhosttyTerminal terminal, GhosttyFormatterTerminalOptions options);
int ghostty_formatter_format_alloc(GhosttyFormatter formatter, const void *allocator, uint8_t **out_ptr, size_t *out_len);
void ghostty_formatter_free(GhosttyFormatter formatter);

int ghostty_search_new(const void *allocator, GhosttySearch *out_search, GhosttyTerminal terminal);
void ghostty_search_free(GhosttySearch search);
int ghostty_search_set(GhosttySearch search, int option, const void *value);
int ghostty_search_get(GhosttySearch search, int data, void *value);
int ghostty_search_run(GhosttySearch search);
int ghostty_search_feed(GhosttySearch search);
int ghostty_search_tick(GhosttySearch search, int *out_status);

typedef struct {
    float x;
    float y;
} GhosttyMousePosition;

typedef struct {
    size_t size;
    uint32_t screen_width;
    uint32_t screen_height;
    uint32_t cell_width;
    uint32_t cell_height;
    uint32_t padding_top;
    uint32_t padding_bottom;
    uint32_t padding_right;
    uint32_t padding_left;
} GhosttyMouseEncoderSize;

int ghostty_key_event_new(const void *allocator, GhosttyKeyEvent *event);
void ghostty_key_event_free(GhosttyKeyEvent event);
void ghostty_key_event_set_action(GhosttyKeyEvent event, int action);
int ghostty_key_event_get_action(GhosttyKeyEvent event);
void ghostty_key_event_set_key(GhosttyKeyEvent event, int key);
int ghostty_key_event_get_key(GhosttyKeyEvent event);
void ghostty_key_event_set_mods(GhosttyKeyEvent event, uint16_t mods);
uint16_t ghostty_key_event_get_mods(GhosttyKeyEvent event);
void ghostty_key_event_set_consumed_mods(GhosttyKeyEvent event, uint16_t mods);
uint16_t ghostty_key_event_get_consumed_mods(GhosttyKeyEvent event);
void ghostty_key_event_set_composing(GhosttyKeyEvent event, _Bool composing);
_Bool ghostty_key_event_get_composing(GhosttyKeyEvent event);
void ghostty_key_event_set_utf8(GhosttyKeyEvent event, const char *utf8, size_t len);
const char *ghostty_key_event_get_utf8(GhosttyKeyEvent event, size_t *len);
void ghostty_key_event_set_unshifted_codepoint(GhosttyKeyEvent event, uint32_t codepoint);
uint32_t ghostty_key_event_get_unshifted_codepoint(GhosttyKeyEvent event);

int ghostty_key_encoder_new(const void *allocator, GhosttyKeyEncoder *encoder);
void ghostty_key_encoder_free(GhosttyKeyEncoder encoder);
void ghostty_key_encoder_setopt(GhosttyKeyEncoder encoder, int option, const void *value);
void ghostty_key_encoder_setopt_from_terminal(GhosttyKeyEncoder encoder, GhosttyTerminal terminal);
int ghostty_key_encoder_encode(GhosttyKeyEncoder encoder, GhosttyKeyEvent event, char *out_buf, size_t out_buf_size, size_t *out_len);

int ghostty_mouse_event_new(const void *allocator, GhosttyMouseEvent *event);
void ghostty_mouse_event_free(GhosttyMouseEvent event);
void ghostty_mouse_event_set_action(GhosttyMouseEvent event, int action);
int ghostty_mouse_event_get_action(GhosttyMouseEvent event);
void ghostty_mouse_event_set_button(GhosttyMouseEvent event, int button);
void ghostty_mouse_event_clear_button(GhosttyMouseEvent event);
_Bool ghostty_mouse_event_get_button(GhosttyMouseEvent event, int *out);
void ghostty_mouse_event_set_mods(GhosttyMouseEvent event, uint16_t mods);
uint16_t ghostty_mouse_event_get_mods(GhosttyMouseEvent event);
void ghostty_mouse_event_set_position(GhosttyMouseEvent event, GhosttyMousePosition position);
GhosttyMousePosition ghostty_mouse_event_get_position(GhosttyMouseEvent event);

int ghostty_mouse_encoder_new(const void *allocator, GhosttyMouseEncoder *encoder);
void ghostty_mouse_encoder_free(GhosttyMouseEncoder encoder);
void ghostty_mouse_encoder_setopt(GhosttyMouseEncoder encoder, int option, const void *value);
void ghostty_mouse_encoder_setopt_from_terminal(GhosttyMouseEncoder encoder, GhosttyTerminal terminal);
void ghostty_mouse_encoder_reset(GhosttyMouseEncoder encoder);
int ghostty_mouse_encoder_encode(GhosttyMouseEncoder encoder, GhosttyMouseEvent event, char *out_buf, size_t out_buf_size, size_t *out_len);

void ghostty_style_default(GhosttyStyle *style);
_Bool ghostty_style_is_default(const GhosttyStyle *style);
void ghostty_free(const void *allocator, uint8_t *ptr, size_t len);
const char *ghostty_type_json(void);
"""
