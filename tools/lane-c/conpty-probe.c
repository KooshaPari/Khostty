#include <stdio.h>
#include "../../src/apprt/windows/conpty.c"
int main(void) {
    KhosttyPty *pty = NULL;
    HRESULT hr = khostty_pty_new(80, 24, L"cmd.exe /d /q", &pty);
    printf("create HRESULT=0x%08lx\n", (unsigned long)hr);
    if (FAILED(hr)) return 10;
    HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, khostty_pty_pid(pty));
    hr = khostty_pty_resize(pty, 100, 30);
    printf("resize HRESULT=0x%08lx\n", (unsigned long)hr);
    const char *command = "echo KH_ConPTY_^roundtrip\r\n";
    hr = khostty_pty_write(pty, command, (UINT32)strlen(command));
    char combined[32768] = {0}; UINT32 used = 0; BOOL found = FALSE;
    for (UINT i = 0; i < 500; i++) {
        UINT32 len = 0;
        hr = khostty_pty_read(pty, combined + used, sizeof(combined) - used - 1, &len);
        if (FAILED(hr)) break;
        used += len; combined[used] = 0;
        if (strstr(combined, "KH_ConPTY_roundtrip")) { found = TRUE; break; }
        Sleep(10);
    }
    printf("roundtrip=%u bytes=%u HRESULT=0x%08lx\n", found, used, (unsigned long)hr);
    int code = found ? 0 : 11;
    command = "ping -n 30 127.0.0.1\r\n";
    khostty_pty_write(pty, command, (UINT32)strlen(command));
    BOOL started = FALSE, stopped = FALSE; UINT32 active = 0;
    for (UINT i = 0; i < 200; i++) { khostty_pty_active(pty, &active); if (active >= 2) { started = TRUE; break; } Sleep(10); }
    BOOL ready = FALSE; used = 0; combined[0] = 0;
    for (UINT i = 0; i < 300; i++) {
        UINT32 len = 0;
        khostty_pty_read(pty, combined + used, sizeof(combined) - used - 1, &len);
        used += len; combined[used] = 0;
        if (strstr(combined, "TTL=")) { ready = TRUE; break; }
        Sleep(10);
    }
    printf("ping-ready=%u\n", ready);
    if (!ready && !code) code = 16;
    khostty_pty_write(pty, "\x03", 1);
    for (UINT i = 0; i < 300; i++) { khostty_pty_active(pty, &active); if (active == 1) { stopped = TRUE; break; } Sleep(10); }
    printf("ctrl-c child-started=%u interrupted=%u shell-alive=%u\n", started, stopped, khostty_pty_alive(pty));
    if (!code && (!started || !stopped)) code = 12;
    hr = khostty_pty_close(pty);
    printf("close HRESULT=0x%08lx\n", (unsigned long)hr);
    if (!code && FAILED(hr)) code = 13;
    if (process) { DWORD wait = WaitForSingleObject(process, 5000); printf("child-wait=%lu\n", wait); if (!code && wait != WAIT_OBJECT_0) code = 14; CloseHandle(process); }
    else if (!code) code = 15;
    return code;
}


