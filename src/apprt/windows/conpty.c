// ConPTY ownership, async output drain and private job lifetime.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string.h>

typedef struct Chunk { struct Chunk *next; DWORD len, offset; char data[4096]; } Chunk;
typedef struct {
    HPCON console;
    HANDLE input, output, process, job, reader, writer, input_event;
    CRITICAL_SECTION lock;
    Chunk *head, *tail;
    SIZE_T queued;
    DWORD fault;
    Chunk *in_head, *in_tail;
    SIZE_T in_queued;
    BOOL stopping;
} KhosttyPty;
static HRESULT failure(void) { DWORD code = GetLastError(); return code ? HRESULT_FROM_WIN32(code) : E_FAIL; }
static void close_handle(HANDLE *handle) { if (*handle) { CloseHandle(*handle); *handle = NULL; } }
static DWORD WINAPI drain_output(void *context) {
    KhosttyPty *self = context;
    char buffer[4096]; DWORD len;
    while (ReadFile(self->output, buffer, sizeof(buffer), &len, NULL) && len) {
        Chunk *chunk = HeapAlloc(GetProcessHeap(), 0, sizeof(*chunk));
        if (chunk) { chunk->next = NULL; chunk->len = len; chunk->offset = 0; memcpy(chunk->data, buffer, len); }
        EnterCriticalSection(&self->lock);
        if (!chunk || self->queued + len > 16 * 1024 * 1024) {
            // Keep draining to avoid ConPTY shutdown deadlocks, but surface a
            // fatal error rather than pretending discarded output was delivered.
            self->fault = chunk ? ERROR_BUFFER_OVERFLOW : ERROR_NOT_ENOUGH_MEMORY;
            if (chunk) HeapFree(GetProcessHeap(), 0, chunk);
        } else {
            if (self->tail) self->tail->next = chunk; else self->head = chunk;
            self->tail = chunk; self->queued += len;
        }
        LeaveCriticalSection(&self->lock);
    }
    return 0;
}

static DWORD WINAPI send_input(void *context) {
    KhosttyPty *self = context;
    for (;;) {
        if (WaitForSingleObject(self->input_event, INFINITE) != WAIT_OBJECT_0) return 1;
        for (;;) {
            EnterCriticalSection(&self->lock);
            BOOL stop = self->stopping;
            Chunk *chunk = stop ? NULL : self->in_head;
            if (chunk) {
                self->in_head = chunk->next; if (!self->in_head) self->in_tail = NULL;
                self->in_queued -= chunk->len;
            }
            LeaveCriticalSection(&self->lock);
            if (stop) return 0;
            if (!chunk) break;
            DWORD offset = 0;
            while (offset < chunk->len) {
                DWORD written = 0;
                if (!WriteFile(self->input, chunk->data + offset, chunk->len - offset, &written, NULL) || !written) {
                    DWORD error = GetLastError();
                    EnterCriticalSection(&self->lock);
                    if (!self->stopping) self->fault = error ? error : ERROR_WRITE_FAULT;
                    LeaveCriticalSection(&self->lock);
                    break;
                }
                offset += written;
            }
            HeapFree(GetProcessHeap(), 0, chunk);
        }
    }
}

HRESULT khostty_pty_close(KhosttyPty *self) {
    if (!self) return S_OK;
    // The reader stays alive while ClosePseudoConsole flushes final output.
    EnterCriticalSection(&self->lock); self->stopping = TRUE; LeaveCriticalSection(&self->lock);
    if (self->input_event) SetEvent(self->input_event);
    close_handle(&self->job); // KILL_ON_JOB_CLOSE, confined to this shell tree.
    if (self->writer) {
        CancelSynchronousIo(self->writer);
        if (WaitForSingleObject(self->writer, 5000) != WAIT_OBJECT_0) return HRESULT_FROM_WIN32(ERROR_TIMEOUT);
    }
    close_handle(&self->writer); close_handle(&self->input_event); close_handle(&self->input);
    if (!self->reader) close_handle(&self->output);
    if (self->console) { ClosePseudoConsole(self->console); self->console = NULL; }
    if (self->reader) {
        CancelSynchronousIo(self->reader);
        if (WaitForSingleObject(self->reader, 5000) != WAIT_OBJECT_0)
            return HRESULT_FROM_WIN32(ERROR_TIMEOUT); // retain state; never free beneath the reader.
    }
    close_handle(&self->reader); close_handle(&self->output);
    if (self->process && WaitForSingleObject(self->process, 5000) != WAIT_OBJECT_0)
        return HRESULT_FROM_WIN32(ERROR_TIMEOUT);
    close_handle(&self->process);
    while (self->head) { Chunk *next = self->head->next; HeapFree(GetProcessHeap(), 0, self->head); self->head = next; }
    while (self->in_head) { Chunk *next = self->in_head->next; HeapFree(GetProcessHeap(), 0, self->in_head); self->in_head = next; }
    DeleteCriticalSection(&self->lock);
    HeapFree(GetProcessHeap(), 0, self);
    return S_OK;
}

HRESULT khostty_pty_new(UINT16 cols, UINT16 rows, const WCHAR *command, KhosttyPty **out) {
    if (!out || !cols || !rows || cols > 32767 || rows > 32767) return E_INVALIDARG;
    *out = NULL;
    KhosttyPty *self = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(*self));
    if (!self) return E_OUTOFMEMORY;
    InitializeCriticalSection(&self->lock);
    HANDLE input_read = NULL, output_write = NULL, thread = NULL;
    PPROC_THREAD_ATTRIBUTE_LIST attributes = NULL;
    BOOL attributes_initialized = FALSE;
    HRESULT hr = E_FAIL;
    if (!CreatePipe(&input_read, &self->input, NULL, 0) ||
        !CreatePipe(&self->output, &output_write, NULL, 0)) { hr = failure(); goto done; }
    COORD size = {(SHORT)cols, (SHORT)rows};
    hr = CreatePseudoConsole(size, input_read, output_write, 0, &self->console);
    if (FAILED(hr)) goto done;
    self->reader = CreateThread(NULL, 0, drain_output, self, 0, NULL);
    if (!self->reader) { hr = failure(); goto done; }
    SIZE_T bytes = 0;
    InitializeProcThreadAttributeList(NULL, 1, 0, &bytes);
    if (!bytes) { hr = failure(); goto done; }
    attributes = HeapAlloc(GetProcessHeap(), 0, bytes);
    if (!attributes) { hr = E_OUTOFMEMORY; goto done; }
    if (!InitializeProcThreadAttributeList(attributes, 1, 0, &bytes)) { hr = failure(); goto done; }
    attributes_initialized = TRUE;
    if (!UpdateProcThreadAttribute(attributes, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
        self->console, sizeof(self->console), NULL, NULL)) { hr = failure(); goto done; }
    self->job = CreateJobObjectW(NULL, NULL);
    if (!self->job) { hr = failure(); goto done; }
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {0};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(self->job, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) { hr = failure(); goto done; }
    WCHAR *line = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, 32768 * sizeof(WCHAR));
    if (!line) { hr = E_OUTOFMEMORY; goto done; }
    if (command) {
        if (lstrlenW(command) >= 32768) { hr = E_INVALIDARG; HeapFree(GetProcessHeap(), 0, line); goto done; }
        lstrcpyW(line, command);
    } else {
        const WCHAR *choices[] = {L"pwsh.exe", L"powershell.exe", L"cmd.exe", L"wsl.exe"};
        WCHAR path[32768]; BOOL found = FALSE;
        for (UINT i = 0; i < 4; i++) {
            DWORD length = SearchPathW(NULL, choices[i], NULL, 32768, path, NULL);
            if (length && length < 32700) {
                lstrcpyW(line, L"\""); lstrcatW(line, path); lstrcatW(line, L"\"");
                if (i < 2) lstrcatW(line, L" -NoLogo -NoProfile");
                found = TRUE; break;
            }
        }
        if (!found) { hr = HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND); HeapFree(GetProcessHeap(), 0, line); goto done; }
    }
    STARTUPINFOEXW startup = {0}; startup.StartupInfo.cb = sizeof(startup); startup.lpAttributeList = attributes;
    // Match Microsoft Terminal: explicitly request fresh console standard
    // handles instead of inheriting an IDE/agent's redirected pipe handles.
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    PROCESS_INFORMATION process = {0};
    if (!CreateProcessW(NULL, line, NULL, NULL, FALSE, EXTENDED_STARTUPINFO_PRESENT | CREATE_SUSPENDED,
        NULL, NULL, &startup.StartupInfo, &process)) { hr = failure(); HeapFree(GetProcessHeap(), 0, line); goto done; }
    HeapFree(GetProcessHeap(), 0, line);
    self->process = process.hProcess; thread = process.hThread;
    if (!AssignProcessToJobObject(self->job, self->process)) { hr = failure(); TerminateProcess(self->process, 1); goto done; }
    self->input_event = CreateEventW(NULL, FALSE, FALSE, NULL);
    if (!self->input_event) { hr = failure(); goto done; }
    self->writer = CreateThread(NULL, 0, send_input, self, 0, NULL);
    if (!self->writer) { hr = failure(); goto done; }
    if (ResumeThread(thread) == (DWORD)-1) { hr = failure(); goto done; }
    hr = S_OK;
done:
    close_handle(&thread); close_handle(&input_read); close_handle(&output_write);
    if (attributes_initialized) DeleteProcThreadAttributeList(attributes);
    if (attributes) HeapFree(GetProcessHeap(), 0, attributes);
    if (FAILED(hr)) { khostty_pty_close(self); return hr; }
    *out = self; return S_OK;
}

HRESULT khostty_pty_write(KhosttyPty *self, const char *bytes, UINT32 len) {
    if (!self || (!bytes && len)) return E_INVALIDARG;
    Chunk *head = NULL, *tail = NULL; UINT32 remaining = len;
    if (len > 16 * 1024 * 1024) return HRESULT_FROM_WIN32(ERROR_BUFFER_OVERFLOW);
    while (remaining) {
        Chunk *chunk = HeapAlloc(GetProcessHeap(), 0, sizeof(*chunk));
        if (!chunk) {
            while (head) { Chunk *next = head->next; HeapFree(GetProcessHeap(), 0, head); head = next; }
            return E_OUTOFMEMORY;
        }
        chunk->next = NULL; chunk->offset = 0; chunk->len = remaining > 4096 ? 4096 : remaining;
        memcpy(chunk->data, bytes, chunk->len); bytes += chunk->len; remaining -= chunk->len;
        if (tail) tail->next = chunk; else head = chunk; tail = chunk;
    }
    EnterCriticalSection(&self->lock);
    if (self->stopping || self->in_queued + len > 16 * 1024 * 1024) {
        LeaveCriticalSection(&self->lock);
        while (head) { Chunk *next = head->next; HeapFree(GetProcessHeap(), 0, head); head = next; }
        return HRESULT_FROM_WIN32(ERROR_BUFFER_OVERFLOW);
    }
    if (head) {
        if (self->in_tail) self->in_tail->next = head; else self->in_head = head;
        self->in_tail = tail; self->in_queued += len;
    }
    LeaveCriticalSection(&self->lock);
    if (len && !SetEvent(self->input_event)) return failure();
    return S_OK;
}
HRESULT khostty_pty_read(KhosttyPty *self, char *bytes, UINT32 capacity, UINT32 *len) {
    if (!self || !bytes || !len) return E_INVALIDARG;
    *len = 0;
    EnterCriticalSection(&self->lock);
    DWORD fault = self->fault;
    while (self->head && *len < capacity) {
        Chunk *chunk = self->head;
        DWORD count = chunk->len - chunk->offset;
        if (count > capacity - *len) count = capacity - *len;
        memcpy(bytes + *len, chunk->data + chunk->offset, count);
        chunk->offset += count; self->queued -= count; *len += count;
        if (chunk->offset == chunk->len) {
            self->head = chunk->next; if (!self->head) self->tail = NULL;
            HeapFree(GetProcessHeap(), 0, chunk);
        }
    }
    LeaveCriticalSection(&self->lock);
    return fault ? HRESULT_FROM_WIN32(fault) : S_OK;
}
HRESULT khostty_pty_resize(KhosttyPty *self, UINT16 cols, UINT16 rows) {
    if (!self || !cols || !rows || cols > 32767 || rows > 32767) return E_INVALIDARG;
    COORD size = {(SHORT)cols, (SHORT)rows}; return ResizePseudoConsole(self->console, size);
}
BOOL khostty_pty_alive(KhosttyPty *self) { return self && WaitForSingleObject(self->process, 0) == WAIT_TIMEOUT; }
DWORD khostty_pty_pid(KhosttyPty *self) { return self ? GetProcessId(self->process) : 0; }
HRESULT khostty_pty_active(KhosttyPty *self, UINT32 *count) {
    if (!self || !count) return E_INVALIDARG;
    JOBOBJECT_BASIC_ACCOUNTING_INFORMATION info;
    if (!QueryInformationJobObject(self->job, JobObjectBasicAccountingInformation, &info, sizeof(info), NULL)) return failure();
    *count = info.ActiveProcesses; return S_OK;
}
