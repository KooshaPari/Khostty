#include <stdio.h>
#include "../../src/apprt/windows/text_renderer.c"
int main(void) {
    HWND window = CreateWindowExW(0, L"STATIC", L"Khostty renderer probe", WS_OVERLAPPEDWINDOW,
        0, 0, 480, 300, NULL, NULL, GetModuleHandleW(NULL), NULL);
    if (!window) return 10;
    KhosttyText *renderer = NULL;
    HRESULT hr = khostty_text_new(window, &renderer);
    if (FAILED(hr)) { printf("init HRESULT=0x%08lx\n", (unsigned long)hr); DestroyWindow(window); return 11; }
    const WCHAR text[] = L"A\u754c\U0001f600";
    UINT32 missing = 0, runs = 0;
    hr = khostty_text_glyph_probe(renderer, text, 4, &missing, &runs);
    printf("positive HRESULT=0x%08lx missing=%u runs=%u\n", (unsigned long)hr, missing, runs);
    int code = FAILED(hr) || missing || !runs ? 12 : 0;
    const WCHAR absent[] = L"\U0010ffff";
    hr = khostty_text_glyph_probe(renderer, absent, 2, &missing, &runs);
    printf("negative HRESULT=0x%08lx missing=%u runs=%u\n", (unsigned long)hr, missing, runs);
    if (!code && (FAILED(hr) || !missing)) code = 13;
    hr = khostty_text_draw(renderer, text, 4);
    printf("draw HRESULT=0x%08lx\n", (unsigned long)hr);
    if (!code && FAILED(hr)) code = 14;
    khostty_text_free(renderer);
    if (!DestroyWindow(window) && !code) code = 15;
    return code;
}

