# Security Model

**Observed:** 2026-09-17 · Trust boundaries, the authorization requirement, memory
safety approach, and an explicit list of what is not yet defended.

Khostty embeds an upstream terminal library and adds an agent-facing control
surface. That second part is the security-relevant delta: an IPC channel that can
write VT bytes into a live shell is remote code execution by design unless it is
authenticated and scoped.

---

## 1. Trust boundaries

```
 UNTRUSTED ─────────────────────────────────────────────────────────────────
  │
  │  PTY bytes          Agent JSON over IPC socket     Kitty image payloads
  │  (program output,   (local clients)                (APC sequences)
  │   possibly hostile)
  │        │                       │                          │
  ▼        ▼                       ▼                          ▼
 ┌──────────────────┐   ┌──────────────────────┐   ┌─────────────────────┐
 │ VT parser        │   │ IPC auth + dispatch  │   │ Image decode        │
 │ (src/terminal/)  │   │ (src/apprt/ipc/)     │   │ (wuffs / kitty)     │
 │                  │   │                      │   │                     │
 │ never fails on   │   │ fail-closed token    │   │ media policy gated  │
 │ malformed input  │   │ (auth.zig)           │   │ by host options     │
 └────────┬─────────┘   └──────────┬───────────┘   └──────────┬──────────┘
          │                        │                          │
          │  terminal state (trusted once parsed)             │
          ▼                        ▼                          ▼
 ┌──────────────────────────────────────────────────────────────────────────┐
 │ HOST CAPABILITIES — capability-gated, never ambient                       │
 │ clipboard read/write · desktop notification · progress report ·           │
 │ open URL · kitty image file media · paste confirmation                    │
 └──────────────────────────────────────────────────────────────────────────┘
          │
          ▼
 TRUSTED ── host application, user's filesystem, user's session
```

The design principle: **the parser is defensive about bytes and permissive about
nothing else.** Anything that reaches outside the terminal (clipboard, files,
notifications) is routed through a host callback that the embedder must explicitly
install.

---

## 2. Untrusted input handling

### The parser does not fail on hostile bytes

`ghostty_terminal_vt_write` is documented to **never fail**:

> Any erroneous input or errors in processing the input are logged internally but do
> not cause this function to fail because this input is assumed to be untrusted and
> from an external source; so the primary goal is to keep the terminal state
> consistent and not allow malformed input to corrupt or crash.

That is the right contract: a terminal must survive `cat /dev/urandom` without
taking down the session, and a partial escape sequence must leave usable state
rather than an error the host has to interpret.

### Paste is a separate trust decision

Pasted text is not the same as program output: it arrives from the user's clipboard
and may contain control characters that a shell would interpret as commands.

`include/ghostty/vt/paste.h` provides:

| API | Purpose |
|---|---|
| `ghostty_paste_is_safe(data, len)` | Conservative check; true only when the data contains no unsafe control bytes |
| `ghostty_terminal_paste(...)` | Writes only the first text representation; rejects with `GHOSTTY_REJECTED` **and writes nothing** unless `allow_unsafe` is set |
| `ghostty_paste_encode(...)` | Encodes without a terminal: bracketed paste wrapping and unsafe-byte stripping (NUL, ESC, DEL, and similar) |

The rejection-then-confirm pattern is deliberate: the host gets a clean
"rejected, nothing written" signal, shows the user a confirmation, and only then
retries with `allow_unsafe`. Nothing is written speculatively.

### Fuzzing

Upstream ships AFL++ harnesses in `test/fuzz-libghostty/` with 4,002 seed files and
three targets (`osc`, `parser`, `stream`), plus `replay-crashes.nu`. The G2
acceptance criterion is "zero new crashes on the corpus".

**Not verified here.** No fuzz run was executed on 2026-09-17. Treat the corpus as
available tooling, not as a current assurance.

---

## 3. IPC authorization requirement

**Requirement:** an unauthenticated IPC channel that accepts `pane.write` is
arbitrary code execution in the user's shell. Authentication is therefore a
correctness requirement, not a hardening nicety.

The v1 protocol spec ([`src/apprt/ipc/protocol.md`](../src/apprt/ipc/protocol.md)
§5) and the implementation (`src/apprt/ipc/auth.zig`) specify:

| Control | Behaviour |
|---|---|
| Required for | **Every** command except `ping` |
| `ping` exemption | Deliberate: lets an agent probe liveness and version without a secret |
| Token sources, in order | `KHOSTTY_IPC_TOKEN`, then a token file (`KHOSTTY_IPC_TOKEN_FILE`, else `ipc.token` beside the socket) |
| Missing token | **Fail-closed.** Every authenticated command is rejected with `unauthorized`. The server never runs unauthenticated. |
| Comparison | Constant-time (`std.crypto.utils.timingSafeEql`), length checked first in a way that does not leak length through early-exit timing |
| Token generation | `std.crypto.random`, 32 bytes, hex-encoded (64 chars) |
| Token file permissions | Expected `0600`; loose permissions are **logged, not refused** |

Socket placement also matters, and the spec follows the platform convention:

| Platform | Path |
|---|---|
| macOS | `~/Library/Caches/khostty/ipc.sock` |
| Linux/BSD | `$XDG_RUNTIME_DIR/khostty/ipc.sock` (fallback `/tmp/khostty-$UID/ipc.sock`) |
| Override | `KHOSTTY_IPC_SOCKET` |

`$XDG_RUNTIME_DIR` is per-user and mode-restricted, which is the correct default.
The `/tmp` fallback is the weakest option and depends on the `-$UID` suffix and
directory permissions for isolation.

### What is not yet true about IPC

| Gap | Why it matters |
|---|---|
| **No `server.zig`** | Nothing listens. The auth code is not reachable end to end, so its behaviour is unverified in situ. |
| No `app_host.zig` | The real host adapter and its thread-marshalling are unimplemented |
| Not wired into any runtime | No running Khostty exposes the socket |
| Concurrency untested | The spec promises "concurrent pane operations do not deadlock"; no test exercises it |
| Scope of tokens | One token grants all commands. There is no per-command or per-pane capability granularity. |
| No rate limiting | No documented bound on commands per connection |
| Loose token-file permissions tolerated | Logged only; a world-readable token would still work |

The last three are design weaknesses to settle before the protocol ships, not
implementation bugs.

---

## 4. Windows transport weakness (scaffold)

`src/apprt/windows/ipc.zig` sketches a named pipe at
`\\.\pipe\khostty-{server_pid}`. Its security attributes are:

```zig
const PIPE_SECURITY_ATTRIBUTES = stdwin.SECURITY_ATTRIBUTES{
    .nLength = @sizeOf(stdwin.SECURITY_ATTRIBUTES),
    .lpSecurityDescriptor = null,   // default DACL
    .bInheritHandle = TRUE,         // handle is inheritable
};
```

Two problems if this is implemented as written:

1. **`lpSecurityDescriptor = null`** means the pipe gets the process's default DACL,
   which in a typical user session permits other processes in that session to
   connect. A named pipe with no ACL is the Windows equivalent of a world-writable
   socket.
2. **`bInheritHandle = TRUE`** lets the handle leak into child processes, widening
   who can use it.

Neither is exploitable today, because every operation returns
`error.Unimplemented`. But the Windows transport is not mentioned in the v1 auth
design, which is Unix-socket-shaped. **The Windows IPC transport needs its own
authorization design** before G3 and G4 converge. Recorded here so it is not
discovered later.

---

## 5. Memory safety

### Why the model is tractable

The engine is written in Zig, and the C ABI exposes **opaque handles** rather than
raw struct pointers for the important types:

```c
GhosttyTerminal term = NULL;
ghostty_terminal_new(NULL, &term, 80, 24);
/* term is opaque; you cannot dereference or forge it */
ghostty_terminal_free(term);
```

That is materially safer than a C library that hands out `struct` pointers.
Ownership rules are documented per API.

### Ownership rules that matter

| Rule | Consequence if violated |
|---|---|
| Library-owned buffers from `*_alloc` must be released with `ghostty_free` | Leak, or double-free if freed twice |
| Borrowed pointers (`GhosttyString`, row/cell handles, search match buffers) are valid only until the next mutating call on the object that produced them | Use-after-free that reads plausible data rather than crashing |
| A freed handle must not be used | Use-after-free |
| Callbacks must not unwind across the FFI boundary (Rust) | Undefined behaviour |
| Callbacks must not re-enter `vt_write` on the same terminal | Documented as no-reentrancy; violation is a logic error |

### How the wrappers defend against these

| Wrapper | Defence |
|---|---|
| Rust | RAII `Drop` on all wrapper types; `unsafe` confined to `src/ffi.rs` with documented invariants; borrowed values tied to Rust lifetimes so the borrow checker rejects outliving uses |
| Rust | `tests/abi_layout.rs` asserts layout against the library's own `ghostty_type_json()` manifest, so a struct change fails loudly instead of corrupting memory |
| Rust | `--features bindgen` regenerates bindings from the C headers and fails on drift |
| WASM | `js/memory.js` reacquires `ArrayBuffer`/typed-array views whenever the buffer identity or length changes, because an exported call can grow linear memory and leave host views detached. A stale view still reads and writes, producing plausible garbage rather than a fault. |
| WASM | Shared helper copies **before** freeing library-owned buffers, because the reverse order is a silent use-after-free |
| WASM | All struct layout read from the type manifest at runtime; no hardcoded offsets |

### AST-level static analysis

There is **no** Clippy-on-Zig equivalent wired up, and no sanitizer run is recorded.
`zig build test-valgrind` exists and `valgrind.supp` is maintained, but it was not
executed on 2026-09-17.

---

## 6. Host capabilities as attack surface

These are the sequences through which untrusted program output can reach outside
the terminal. Each is gated by an option the embedder controls, and each is
therefore a decision the embedder must make explicitly.

| Capability | Trigger | Gate |
|---|---|---|
| Clipboard **read** | OSC 52 `?`, OSC 5522 | `GHOSTTY_TERMINAL_OPT_CLIPBOARD_READ` |
| Clipboard **write** | OSC 52 | `GHOSTTY_TERMINAL_OPT_CLIPBOARD_WRITE` |
| Kitty image from **file** | APC image payload | `GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_MEDIUM_FILE` |
| Kitty image from **temp file**, restricted to a directory | APC image payload | `GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_MEDIUM_TEMP_FILE` (the allowed directory is supplied by the host) |
| Kitty image from **shared memory** | APC image payload | `GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_MEDIUM_SHARED_MEM` |
| Image storage bounds | APC image payload | `GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_STORAGE_LIMIT` |
| APC payload size bounds | APC sequences | `GHOSTTY_TERMINAL_OPT_APC_MAX_BYTES`, `…_APC_MAX_BYTES_KITTY` |
| Desktop notification | OSC 9, OSC 777 | `GHOSTTY_TERMINAL_OPT_DESKTOP_NOTIFICATION` |
| Progress report | OSC 9;4 | `GHOSTTY_TERMINAL_OPT_PROGRESS_REPORT` |
| Unknown sequence | any unrecognised escape | `GHOSTTY_TERMINAL_OPT_UNKNOWN_SEQUENCE`, `…_UNKNOWN_MAX_BYTES` |
| Remote inquiry responses | ENQ, XTVERSION, device attributes | `…_ENQUIRY`, `…_XTVERSION`, `…_DEVICE_ATTRIBUTES` |
| Title / working directory | OSC 0/2, OSC 7 | `…_TITLE`, `…_PWD`, `…_TITLE_CHANGED`, `…_PWD_CHANGED` |

The safe default stance for an embedder processing untrusted output: leave the
clipboard and file-backed image media **unset**, and bound APC and unknown-sequence
sizes.

The file-backed image media deserves emphasis. A terminal that will read an image
from a path supplied by the program it is displaying has handed that program an
arbitrary-file-read primitive against the user's account. `libghostty-vt` makes this
opt-in and directory-restricted for the temp-file medium; the embedder still has to
decide.

---

## 7. WASM specifics

The WASM build has a structurally **smaller** attack surface than the native build:

| Property | Consequence |
|---|---|
| `wasm32-freestanding` | No PTY, no filesystem, no clock, no timestamps |
| Kitty graphics disabled (16 functions excluded) | No file-backed or shared-memory image media at all; sequences are parsed and ignored |
| No ambient authority | A module cannot touch the host except through declared imports (currently none) |
| Linear memory, no raw pointers on the host side | No host address-space access |

Residual risks are memory-safety bugs inside the module and any imports the host
chooses to supply via `ImportOverrides`. The default is zero imports.

---

## 8. Build and supply chain

| Control | State |
|---|---|
| Dependency pinning | 15 dependencies in `build.zig.zon` each pin a URL **and** a content hash |
| Dependency source | `deps.files.ghostty.org` (upstream-controlled) |
| Vendored code | `vendor/glad`, `vendor/nerd-fonts` committed in-tree |
| C/C++ in the build | `wuffs` (image decoding), `simdutf`, `highway` — upstream-vendored |
| npm dependencies | **None.** `wasm/package.json` has zero dependencies; tests use `node:test`; `typescript` is fetched on demand |
| Rust dependencies | **None** at runtime; `bindgen` is an optional build dependency behind a non-default feature |
| Secrets in the tree | None found: no `.env`, no credential files tracked, no key-shaped literals in `src/`, `include/`, `khostty-vt/src`, `khostty-go`, or `wasm/js` |
| SAST / secret scanning | **None configured.** G0 stripped upstream's Scorecard workflow as boilerplate; no CodeQL or equivalent replaced it |
| Dependency update automation | `dependabot.yml` is present |

The absence of any automated security scanning is a real gap. The npm and Rust
dependency footprint is admirably small, which reduces risk, but nothing
continuously checks the C/Zig surface or the vendored code.

---

## 9. Threat model summary

| Threat | Control | Status |
|---|---|---|
| Malformed VT bytes corrupt or crash the terminal | `vt_write` never fails; input treated as untrusted | Designed and exercised by the conformance `edge` category (16 cases) |
| Hostile clipboard content executed as commands | `paste_is_safe`, reject-then-confirm, unsafe-byte stripping | Implemented upstream |
| Unauthorized local process drives the terminal | Token auth, fail-closed, constant-time compare | Designed; **not reachable** (no server) |
| Untrusted output reads user files via image media | Opt-in, directory-restricted image media | Implemented as host-gated options |
| Untrusted output exfiltrates clipboard | Clipboard read is a host-gated callback | Implemented upstream |
| Memory corruption at the FFI boundary | Opaque handles, RAII wrappers, ABI manifest assertions, copy-before-free | Implemented in Rust and WASM wrappers |
| ABI drift corrupts memory silently | `ghostty_type_json()` manifest + layout tests | Implemented |
| Other process in the session connects to the Windows pipe | Named pipe ACL | **Not defended** — default DACL, inheritable handle |
| Compromised build dependency | Content-hash pinning | Implemented |
| Known-vulnerable dependency introduced | Automated scanning | **Not implemented** |
| Privilege escalation from the terminal process | OS sandboxing | **Not attempted.** The terminal runs with the user's full privileges, as upstream does. |

---

## 10. Reporting a vulnerability

This is a fork. Two upstreams are in play:

1. **If the issue is in `libghostty-vt` or the terminal engine** — it affects
   upstream Ghostty. Report to upstream through their security process. Fixing it
   only in the fork would leave upstream users exposed and make future merges
   harder.
2. **If the issue is in a Khostty-only surface** (`khostty-vt/`, `khostty-go/`,
   `wasm/`, `src/apprt/windows/`, `src/apprt/ipc/`, `conformance/`) — report to the
   Khostty maintainers.

Do not open a public issue containing a working exploit. Contact the maintainers
privately, allow time to assess and fix, and coordinate disclosure.

Nothing in this repository currently constitutes a supported security-response
commitment; there is no published security contact and no release to patch. Treat
this section as the intent, not a guarantee.

---

## 11. What is not defended (explicit list)

Listing these prevents them from being mistaken for solved:

- No OS sandbox around the terminal process
- No automated vulnerability scanning, secret scanning, or SAST in CI
- No fuzzing run recorded, and no sanitizer or Valgrind run recorded
- No IPC server, so no end-to-end authorization verification
- No per-command or per-pane token scoping; no rate limiting
- Windows named pipe has default-DACL, inheritable-handle attributes
- No security review of the Rust, Go, or WASM wrappers by anyone other than their authors
- No independent threat-model review
- No release, therefore no security-fix channel

---

## See also

- [ARCHITECTURE.md](ARCHITECTURE.md) — where each trust boundary sits
- [AGENT.md](AGENT.md) — the IPC surface in practical detail
- [CONTRIBUTING.md](CONTRIBUTING.md) — the review checklist, including secrets
- [BUILD.md](BUILD.md) — dependency resolution and the current build blocker
- [`src/apprt/ipc/protocol.md`](../src/apprt/ipc/protocol.md) — the auth design in full
- `AI_POLICY.md` — upstream's AI usage policy (disclosure requirements)
