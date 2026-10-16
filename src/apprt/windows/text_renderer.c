// Software Direct2D target with DirectWrite system font fallback.
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <initguid.h>
#include <d2d1.h>
#include <dwrite.h>

typedef struct {
    HWND hwnd;
    ID2D1Factory *factory;
    IDWriteFactory *write;
    IDWriteTextFormat *format;
    ID2D1HwndRenderTarget *target;
    ID2D1SolidColorBrush *brush;
} KhosttyText;

static void drop_target(KhosttyText *self) {
    if (self->brush) ID2D1SolidColorBrush_Release(self->brush);
    if (self->target) ID2D1HwndRenderTarget_Release(self->target);
    self->brush = NULL;
    self->target = NULL;
}

void khostty_text_free(KhosttyText *self) {
    if (!self) return;
    drop_target(self);
    if (self->format) IDWriteTextFormat_Release(self->format);
    if (self->write) IDWriteFactory_Release(self->write);
    if (self->factory) ID2D1Factory_Release(self->factory);
    HeapFree(GetProcessHeap(), 0, self);
}

static HRESULT create_target(KhosttyText *self) {
    RECT rect;
    if (!GetClientRect(self->hwnd, &rect)) return HRESULT_FROM_WIN32(GetLastError());
    UINT dpi = GetDpiForWindow(self->hwnd);
    if (!dpi) return E_FAIL;
    D2D1_RENDER_TARGET_PROPERTIES props = {0};
    // Explicit software backend avoids the unimplemented OpenGL path and
    // does not depend on GPU/driver availability on the Windows desk.
    props.type = D2D1_RENDER_TARGET_TYPE_SOFTWARE;
    props.pixelFormat.format = DXGI_FORMAT_UNKNOWN;
    props.pixelFormat.alphaMode = D2D1_ALPHA_MODE_IGNORE;
    props.dpiX = props.dpiY = (FLOAT)dpi;
    D2D1_HWND_RENDER_TARGET_PROPERTIES window = {0};
    window.hwnd = self->hwnd;
    window.pixelSize.width = rect.right > 0 ? (UINT32)rect.right : 1;
    window.pixelSize.height = rect.bottom > 0 ? (UINT32)rect.bottom : 1;
    HRESULT hr = ID2D1Factory_CreateHwndRenderTarget(self->factory, &props, &window, &self->target);
    if (FAILED(hr)) return hr;
    D2D1_COLOR_F color = {0.9f, 0.9f, 0.9f, 1.0f};
    hr = ID2D1HwndRenderTarget_CreateSolidColorBrush(self->target, &color, NULL, &self->brush);
    if (FAILED(hr)) drop_target(self);
    return hr;
}

HRESULT khostty_text_new(HWND hwnd, KhosttyText **out) {
    if (!out || !IsWindow(hwnd)) return E_INVALIDARG;
    *out = NULL;
    KhosttyText *self = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(*self));
    if (!self) return E_OUTOFMEMORY;
    self->hwnd = hwnd;
    HRESULT hr = D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, &IID_ID2D1Factory, NULL, (void **)&self->factory);
    if (SUCCEEDED(hr)) hr = DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, &IID_IDWriteFactory, (IUnknown **)&self->write);
    if (SUCCEEDED(hr)) hr = IDWriteFactory_CreateTextFormat(self->write, L"Consolas", NULL,
        DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
        16.0f, L"en-us", &self->format);
    if (SUCCEEDED(hr)) hr = IDWriteTextFormat_SetWordWrapping(self->format, DWRITE_WORD_WRAPPING_NO_WRAP);
    if (SUCCEEDED(hr)) hr = create_target(self);
    if (FAILED(hr)) { khostty_text_free(self); return hr; }
    *out = self;
    return S_OK;
}

HRESULT khostty_text_resize(KhosttyText *self, UINT32 width, UINT32 height) {
    if (!self || !IsWindow(self->hwnd)) return E_INVALIDARG;
    if (!width || !height) return S_OK;
    if (!self->target) return create_target(self);
    UINT dpi = GetDpiForWindow(self->hwnd);
    if (!dpi) return E_FAIL;
    ID2D1HwndRenderTarget_SetDpi(self->target, (FLOAT)dpi, (FLOAT)dpi);
    D2D1_SIZE_U size = {width, height};
    HRESULT hr = ID2D1HwndRenderTarget_Resize(self->target, &size);
    if (hr == D2DERR_RECREATE_TARGET) drop_target(self);
    return hr;
}

HRESULT khostty_text_draw(KhosttyText *self, const WCHAR *text, UINT32 len) {
    if (!self || !text) return E_INVALIDARG;
    HRESULT hr = S_OK;
    if (!self->target) hr = create_target(self);
    if (FAILED(hr)) return hr;
    RECT rect;
    if (!GetClientRect(self->hwnd, &rect)) return HRESULT_FROM_WIN32(GetLastError());
    if (rect.right <= 0 || rect.bottom <= 0) return S_OK;
    UINT dpi = GetDpiForWindow(self->hwnd);
    if (!dpi) return E_FAIL;
    IDWriteTextLayout *layout = NULL;
    ID2D1HwndRenderTarget_SetDpi(self->target, (FLOAT)dpi, (FLOAT)dpi);
    hr = IDWriteFactory_CreateTextLayout(self->write, text, len, self->format,
        (FLOAT)rect.right * 96.0f / dpi, (FLOAT)rect.bottom * 96.0f / dpi, &layout);
    if (FAILED(hr)) return hr;
    D2D1_COLOR_F background = {0.06f, 0.06f, 0.06f, 1.0f};
    D2D1_POINT_2F origin = {0, 0};
    ID2D1HwndRenderTarget_BeginDraw(self->target);
    ID2D1HwndRenderTarget_Clear(self->target, &background);
    ID2D1HwndRenderTarget_DrawTextLayout(self->target, origin, layout,
        (ID2D1Brush *)self->brush, D2D1_DRAW_TEXT_OPTIONS_NONE);
    hr = ID2D1HwndRenderTarget_EndDraw(self->target, NULL, NULL);
    IDWriteTextLayout_Release(layout);
    if (hr == D2DERR_RECREATE_TARGET) drop_target(self);
    return hr;
}


// Inspect shaped glyph IDs through DirectWrite's own fallback pipeline. This
// reports missing glyphs without capturing any screen or pixel content.
typedef struct {
    IDWriteTextRenderer iface;
    ULONG refs;
    UINT32 missing;
    UINT32 runs;
} GlyphProbe;
static HRESULT STDMETHODCALLTYPE probe_query(IDWriteTextRenderer *p, REFIID iid, void **out) {
    if (!out) return E_POINTER;
    *out = NULL;
    if (!IsEqualIID(iid, &IID_IUnknown) && !IsEqualIID(iid, &IID_IDWritePixelSnapping) &&
        !IsEqualIID(iid, &IID_IDWriteTextRenderer)) return E_NOINTERFACE;
    *out = p; ((GlyphProbe *)p)->refs++; return S_OK;
}
static ULONG STDMETHODCALLTYPE probe_add(IDWriteTextRenderer *p) { return ++((GlyphProbe *)p)->refs; }
static ULONG STDMETHODCALLTYPE probe_release(IDWriteTextRenderer *p) { return --((GlyphProbe *)p)->refs; }
static HRESULT STDMETHODCALLTYPE probe_snap(IDWriteTextRenderer *p, void *ctx, BOOL *out) {
    (void)p; (void)ctx; *out = TRUE; return S_OK;
}
static HRESULT STDMETHODCALLTYPE probe_transform(IDWriteTextRenderer *p, void *ctx, DWRITE_MATRIX *out) {
    (void)p; (void)ctx; DWRITE_MATRIX identity = {1, 0, 0, 1, 0, 0}; *out = identity; return S_OK;
}
static HRESULT STDMETHODCALLTYPE probe_dpi(IDWriteTextRenderer *p, void *ctx, FLOAT *out) {
    (void)p; (void)ctx; *out = 1; return S_OK;
}
static HRESULT STDMETHODCALLTYPE probe_run(IDWriteTextRenderer *p, void *ctx, FLOAT x, FLOAT y,
    DWRITE_MEASURING_MODE mode, const DWRITE_GLYPH_RUN *run,
    const DWRITE_GLYPH_RUN_DESCRIPTION *description, IUnknown *effect) {
    (void)ctx; (void)x; (void)y; (void)mode; (void)description; (void)effect;
    GlyphProbe *probe = (GlyphProbe *)p; probe->runs++;
    for (UINT32 i = 0; i < run->glyphCount; i++) if (!run->glyphIndices[i]) probe->missing++;
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE probe_underline(IDWriteTextRenderer *p, void *ctx, FLOAT x, FLOAT y,
    const DWRITE_UNDERLINE *line, IUnknown *effect) {
    (void)p; (void)ctx; (void)x; (void)y; (void)line; (void)effect; return S_OK;
}
static HRESULT STDMETHODCALLTYPE probe_strike(IDWriteTextRenderer *p, void *ctx, FLOAT x, FLOAT y,
    const DWRITE_STRIKETHROUGH *line, IUnknown *effect) {
    (void)p; (void)ctx; (void)x; (void)y; (void)line; (void)effect; return S_OK;
}
static HRESULT STDMETHODCALLTYPE probe_inline(IDWriteTextRenderer *p, void *ctx, FLOAT x, FLOAT y,
    IDWriteInlineObject *object, BOOL sideways, BOOL rtl, IUnknown *effect) {
    (void)p; (void)ctx; (void)x; (void)y; (void)object; (void)sideways; (void)rtl; (void)effect;
    return E_NOTIMPL;
}
static IDWriteTextRendererVtbl probe_vtable = {
    probe_query, probe_add, probe_release, probe_snap, probe_transform, probe_dpi,
    probe_run, probe_underline, probe_strike, probe_inline
};
HRESULT khostty_text_glyph_probe(KhosttyText *self, const WCHAR *text, UINT32 len,
    UINT32 *missing, UINT32 *runs) {
    if (!self || !text || !missing || !runs) return E_INVALIDARG;
    IDWriteTextLayout *layout = NULL;
    HRESULT hr = IDWriteFactory_CreateTextLayout(self->write, text, len, self->format, 4096, 256, &layout);
    if (FAILED(hr)) return hr;
    GlyphProbe probe = {{&probe_vtable}, 1, 0, 0};
    hr = IDWriteTextLayout_Draw(layout, NULL, &probe.iface, 0, 0);
    IDWriteTextLayout_Release(layout);
    *missing = probe.missing; *runs = probe.runs;
    return hr;
}
