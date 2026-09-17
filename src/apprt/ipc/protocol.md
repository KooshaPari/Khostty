# Khostty Agent IPC Protocol (v1)

Status: **draft, implemented in this directory** (G4 of the Khostty Deep WBS v2).
Owner: `src/apprt/ipc/`.
Supersedes: nothing. Upstream `ghostty` IPC (`ipc/mod.zig`) is unchanged and still
used for `new_window` / `new_tab` / `toggle_quick_terminal`; this protocol is an
additive, agent-facing surface.

---

## 1. Goals

The upstream IPC surface is command-line shaped: an external process asks a running
instance to open a window, open a tab, or toggle the quick terminal. It cannot:

- create or address an individual pane (split),
- inject input or VT sequences into a pane,
- read machine-readable terminal state (cursor, title, size, mode flags),
- search scrollback,
- observe asynchronous events (title change, child exit, resize, bell).

The agent IPC surface adds exactly that, over a line-delimited JSON protocol on a
local socket, with token authentication.

Non-goals (v1):

- No remote/TCP transport. Local socket (Unix domain socket; Windows named pipe is
  a follow-up, see `src/apprt/windows/ipc.zig`).
- No pty input injection (`pane.write` writes *VT bytes into the terminal parser*,
  it does not type into the child process). Typing into the child is a v2 item.
- No protocol negotiation beyond an integer version check.

## 2. Transport and framing

| Item | Value |
| --- | --- |
| Transport | Unix domain socket (macOS/Linux). Windows: named pipe, same framing. |
| Default path | macOS: `~/Library/Caches/khostty/ipc.sock` |
| | Linux/BSD: `$XDG_RUNTIME_DIR/khostty/ipc.sock` (fallback `/tmp/khostty-$UID/ipc.sock`) |
| Path override | `KHOSTTY_IPC_SOCKET` |
| Framing | One JSON value per line, UTF-8, `\n` terminated |
| Max frame | 1 MiB (`max_frame_bytes`); over-long frames get `bad_request` and the connection is closed |
| Direction | Full duplex. Responses are correlated with requests; events are unsolicited |
| Concurrency | One connection may pipeline requests; responses arrive in request order |
| Encoding | JSON. Binary payloads are base64 **not** used in v1: `pane.write.data` is a UTF-8 string and `\u0000`-style escapes carry control bytes |

`pane.write` carries terminal input as a JSON string, so an agent writes
`"data": "\u001b[31mred\u001b[0m"` or `"data": "ls -la\n"`. Escapes are decoded by
the JSON parser before the bytes reach the terminal parser.

## 3. Message shapes

### 3.1 Request (agent -> khostty)

```json
{"v":1,"id":7,"auth":"<token>","cmd":"pane.create","opts":{"split":"vertical"}}
```

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `v` | integer | no | Protocol version. Absent means 1. Mismatch -> `version_unsupported`. |
| `id` | integer | no | Correlation id, echoed verbatim in the response. Absent means uncorrelated. |
| `auth` | string | yes | Auth token. Alternatively sent once as `auth.token`; per-request is authoritative. |
| `cmd` | string | yes | Command name (section 4). |
| `pane_id` | string \| integer | command-dependent | Pane handle: `"p-3"`, `"3"`, or `3`. |
| `data` | string | command-dependent | VT bytes to inject (`pane.write`). |
| `query` | string | command-dependent | Search needle (`pane.search`). |
| `opts` | object | command-dependent | Command options (section 4.1). |

Unknown top-level fields are ignored (`ignore_unknown_fields`) so clients can be
forward-compatible with newer servers. Unknown *values* inside `opts` are ignored
for the same reason; unknown option names are not errors.

### 3.2 Response (khostty -> agent)

```json
{"v":1,"id":7,"ok":true,"data":{"pane_id":"p-3","pid":12345,"title":"bash","cols":120,"rows":40}}
```

```json
{"v":1,"id":7,"ok":false,"error":{"code":"pane_not_found","message":"no pane with id p-9"}}
```

| Field | Type | Present | Meaning |
| --- | --- | --- | --- |
| `v` | integer | always | Protocol version the server speaks. |
| `id` | integer | iff the request carried an id | Correlation id. |
| `ok` | bool | always | Success flag. |
| `data` | object or array | iff `ok` | Command-specific payload. |
| `error` | object | iff `!ok` | `{code, message}`. |

Error codes (`protocol.ErrorCode`):

| Code | Meaning |
| --- | --- |
| `bad_request` | Malformed JSON, missing `cmd`, malformed `pane_id`, oversized frame. |
| `unknown_command` | `cmd` is not in the table in section 4. |
| `unauthorized` | Missing or wrong auth token. |
| `version_unsupported` | `v` is not supported by this server. |
| `pane_not_found` | `pane_id` does not address a live pane. |
| `pane_not_found_after_close` | Pane exited between lookup and operation. |
| `host_unsupported` | The app runtime cannot do this (e.g. daemonized build). |
| `too_many_panes` | `pane.create` exceeded the configured pane ceiling. |
| `not_subscribed` | `events.unsubscribe` for an unknown subscription. |
| `internal` | Unexpected host error. |

### 3.3 Event (khostty -> agent, unsolicited)

```json
{"v":1,"event":"title_change","pane_id":"p-3","seq":12,"data":{"title":"~/projects/khostty"}}
```

Events are delivered only to connections that issued `events.subscribe`. They may
appear between any request and its response; clients must dispatch on the presence
of `event` rather than assuming a response.

## 4. Commands

| `cmd` | Options | `data` payload |
| --- | --- | --- |
| `ping` | - | `{"server":"khostty","version":1,"pid":123}` |
| `pane.create` | `opts` | pane object (section 4.1) |
| `pane.close` | `pane_id` | `{"closed":true,"pane_id":"p-3"}` |
| `pane.focus` | `pane_id` | `{"focused":true,"pane_id":"p-3"}` |
| `pane.list` | - | array of pane objects |
| `pane.write` | `pane_id`, `data` | `{"written":9}` |
| `pane.state` | `pane_id` | snapshot object (section 4.2) |
| `pane.search` | `pane_id`, `query`, `opts.limit` | array of match objects |
| `pane.resize_split` | `pane_id`, `opts:{dir,amount}` | `{"resized":true}` |
| `pane.equalize` | - | `{"equalized":true}` |
| `pane.zoom` | `pane_id` | `{"zoomed":true}` |
| `events.subscribe` | `opts.events` | `{"subscribed":true,"events":["title_change",...]}` |
| `events.unsubscribe` | - | `{"unsubscribed":true}` |

### 4.1 `pane.create`

```json
{"cmd":"pane.create","opts":{"split":"vertical","cwd":"/tmp","title":"build","focus":true}}
```

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `split` | `"vertical"` \| `"horizontal"` | `"vertical"` | tmux-style: vertical = side-by-side (splits left/right, `right`), horizontal = stacked (`down`). |
| `dir` | `"right"` \| `"down"` \| `"left"` \| `"up"` | - | Explicit split direction; overrides `split`. |
| `pane_id` | pane handle | focused pane | Pane to split relative to. |
| `cwd` | string | focused pane cwd | Working directory for the new pane. |
| `title` | string | - | Requested title (may be overwritten by shell integration). |
| `focus` | bool | `true` | Focus the new pane. |
| `command` | string | - | Reserved for v2 (requires `new_split` to accept arguments upstream). |

`splits` map onto real upstream actions only:

| Request | Upstream action |
| --- | --- |
| `dir=right` | `apprt.Action.new_split = .right` |
| `dir=down` | `apprt.Action.new_split = .down` |
| `dir=left` | `apprt.Action.new_split = .left` |
| `dir=up` | `apprt.Action.new_split = .up` |
| `focus=false` + `dir=X` | `new_split = X` then focus returns to the origin pane |
| `pane.focus` | `apprt.Action.goto_split` (`.previous`/`.next`) or direct surface focus when the runtime exposes one |
| `pane.close` | `apprt.Action.close_tab = .this` when the pane is the tab root, else surface close |
| `pane.resize_split` | `apprt.Action.resize_split = .{amount, direction}` |
| `pane.equalize` | `apprt.Action.equalize_splits` |
| `pane.zoom` | `apprt.Action.toggle_split_zoom` |

Pane object (returned by `pane.create`, and each entry of `pane.list`):

```json
{"pane_id":"p-3","title":"bash","pid":12345,"cwd":"/tmp","cols":120,"rows":40,"focused":true,"exited":false}
```

> Deviation from the WBS draft: the draft used `"id"` in `pane.list` entries but
> `"pane_id"` everywhere else. This implementation standardizes on `pane_id` in
> requests, events, and every pane payload. Fields the host does not know are
> `null`.

`new_split` is fire-and-forget in upstream: it carries no return value. The host
adapter therefore resolves the new pane by diffing the runtime's surface registry
before and after the action (see `Host.create` in `pane.zig`, implemented by
`app_host.zig`). If the runtime cannot report a new surface within the adapter's
bounded wait, `pane.create` fails with `internal` rather than inventing an id.

### 4.2 `pane.state` snapshot

```json
{"ok":true,"data":{
  "pane_id":"p-3",
  "title":"bash",
  "pid":12345,
  "cwd":"/Users/me/project",
  "size":{"cols":120,"rows":40,"pixel_width":1440,"pixel_height":960},
  "cursor":{"row":12,"col":45,"visible":true,"style":"block","blinking":false},
  "alt_screen":false,
  "focused":true,
  "mouse_tracking":true,
  "bell_count":0,
  "scrollback_rows":1024,
  "viewport_rows":40,
  "exited":false,
  "exit_code":null
}}
```

Every field is optional in the sense that the host may not know it: unknown values
are emitted as `null` rather than guessed (see `state.zig`). `UNKNOWN` is never
rendered as `0` or `false`.

### 4.3 `pane.search`

```json
{"cmd":"pane.search","pane_id":"p-3","query":"error","opts":{"limit":5}}
```

```json
{"ok":true,"data":{"matches":[{"row":-3,"col":8,"len":5,"text":"error"}],"total":1,"truncated":false}}
```

`row` is relative to the viewport top; negative rows are scrollback. `total` is the
number of matches found up to `limit`; `truncated` is true when the scan stopped
because `limit` was reached.

### 4.4 `events.subscribe`

```json
{"cmd":"events.subscribe","opts":{"events":["title_change","child_exit","resize","bell"]}}
```

Event kinds:

| `event` | `data` |
| --- | --- |
| `title_change` | `{"title":"..."}` |
| `child_exit` | `{"exit_code":0,"signal":null}` |
| `resize` | `{"cols":120,"rows":40}` |
| `bell` | `{"count":1}` |
| `focus_change` | `{"focused":true}` |
| `pane_created` | `{"title":"bash"}` |
| `pane_closed` | `{"reason":"exit"}` |

Omitting `opts.events` (or an empty array) subscribes to all kinds. Each subscriber
has a bounded queue (`events.queue_capacity`, default 256). On overflow the oldest
event is dropped and the subscriber receives a synthetic
`{"event":"events_dropped","data":{"dropped":N}}`, so an agent can detect loss
instead of silently missing state changes.

## 5. Authentication

- The server requires a token for **every** command except `ping` (which is
  unauthenticated on purpose, so an agent can probe liveness and version).
- Token sources, in order: `KHOSTTY_IPC_TOKEN`, then the token file
  (`KHOSTTY_IPC_TOKEN_FILE`, else the platform default under the same directory as
  the socket: `ipc.token`).
- If no token is configured the server **fails closed**: every authenticated
  command is rejected with `unauthorized`. It never runs unauthenticated.
- Comparison is constant-time (`std.crypto.utils.timingSafeEql`) and length is
  checked first in a way that does not leak length via early exit differences in
  the compare itself.
- Tokens are generated with `std.crypto.random` as 32 bytes hex-encoded (64 chars).
  The token file is expected to be `0600`; the server warns (log) but does not
  refuse if permissions are loose.

## 6. Versioning

- `version = 1`.
- Additive changes (new `cmd`, new response field, new event kind) do **not** bump
  the version; clients must ignore unknown fields.
- Removing or re-typing a field bumps `version` and older servers keep answering
  with their own version, so a client can detect the mismatch from the response
  rather than a handshake.
- `protocol.md` in this directory is the normative schema. `protocol.zig` is the
  implementation; `protocol.zig` unit tests are the executable checks.

## 7. Threading model and known limits

- `server.zig` runs a dedicated accept thread and one thread per connection. All
  state shared with the terminal (`pane.zig`, `events.zig`) is guarded by
  `std.Io.Mutex`.
- The terminal itself is owned by the app's IO thread. `app_host.zig` therefore
  documents that host callbacks must be marshalled onto the app thread; the socket
  threads call through the `pane.Host` vtable, whose app implementation is
  responsible for that hop (v1 ships the vtable and a direct implementation; the
  mailbox hop is listed as a follow-up).

## 8. Worked examples

See section 9 (`Agent usage examples`) at the end of this file.

## 9. Agent usage examples

### 9.1 Shell: split a pane, run a command, read the title

```sh
sock="${KHOSTTY_IPC_SOCKET:-$HOME/Library/Caches/khostty/ipc.sock}"
tok="$(cat "$HOME/Library/Caches/khostty/ipc.token")"

# Create a pane split to the right and capture its handle.
printf '%s\n' "{\"id\":1,\"auth\":\"$tok\",\"cmd\":\"pane.create\",\"opts\":{\"split\":\"vertical\",\"cwd\":\"/tmp\"}}" \
  | nc -U "$sock"
# -> {"v":1,"id":1,"ok":true,"data":{"pane_id":"p-4","title":"zsh","pid":4711,...}}
```

### 9.2 Python: write VT and read state

```python
import json, socket, os

sock_path = os.environ.get("KHOSTTY_IPC_SOCKET", os.path.expanduser("~/Library/Caches/khostty/ipc.sock"))
token = open(os.path.join(os.path.dirname(sock_path), "ipc.token")).read().strip()

def call(s, msg):
    s.sendall(json.dumps(msg).encode() + b"\n")
    buf = b""
    while not buf.endswith(b"\n"):
        buf += s.recv(65536)
    return json.loads(buf)

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
    s.connect(sock_path)
    panes = call(s, {"id": 1, "auth": token, "cmd": "pane.list"})
    pid = panes["data"][0]["pane_id"]

    call(s, {"id": 2, "auth": token, "cmd": "pane.write",
             "pane_id": pid, "data": "\u001b[1;32mready\u001b[0m\r\n"})

    state = call(s, {"id": 3, "auth": token, "cmd": "pane.state", "pane_id": pid})
    print(state["data"]["cursor"], state["data"]["title"])
```

### 9.3 Zig: end-to-end against an in-process host (test shape)

```zig
var server: ipc.Server = try .init(alloc, io, .{ .socket_path = path, .auth = auth });
try server.start(io, .{ .manager = &manager });
const client = try ipc.server.Client.connect(io, path);
defer client.deinit(io);
try client.writeRequest(io, .{ .id = 1, .cmd = .pane_create, .opts = .{ .split = .vertical } });
const resp = try client.readMessage(io, alloc);
```

### 9.4 Event subscription

```json
{"cmd":"events.subscribe","opts":{"events":["title_change","child_exit"]}}
{"v":1,"ok":true,"id":4,"data":{"subscribed":true,"events":["title_change","child_exit"]}}
{"v":1,"event":"title_change","pane_id":"p-4","seq":1,"data":{"title":"vim README.md"}}
{"v":1,"event":"child_exit","pane_id":"p-4","seq":2,"data":{"exit_code":0,"signal":null}}
```
