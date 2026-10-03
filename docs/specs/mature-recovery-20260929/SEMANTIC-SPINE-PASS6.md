# Khostty semantic spine resolution — pass 6

Frozen source: `a29aa9c6553d9f42aa68e2919116c0f6d53f329d`. This resolves the IPC/Windows spine first; it does not claim the 2,055-file product-relevant inventory is semantically closed.

## Inventory denominator

After deduplicating overlapping inventory parts by path/object identity, **2,055 unique product-relevant tracked blobs** are inventoried. The inherited bulk test corpus is deliberately not used to inflate this denominator. Enumeration remains distinct from semantic resolution.

## IPC / Windows spine

| Subject | Meaning / source fact | Consequence | Resolution |
|---|---|---|---|
| windows/App.zig | init/registerWindowClass/run return `Unimplemented`; performIpc also unimplemented | Windows executable selection/CLI evidence is not a native terminal-app journey | RESOLVED current state; implementation choice open |
| windows/renderer.zig | every renderer operation returns `Unimplemented` | no native Windows rendering path exists at snapshot | RESOLVED current state |
| windows/surface.zig | association/message bookkeeping exists; init unimplemented; paint/erase/requestRender return false | scaffold can be unit-tested without producing a window/frame | RESOLVED current state |
| windows/ipc.zig | pipe namespace, owner-only ACL intent and non-inheritance are specified/tested; Server/Client ops all Unimplemented | security decisions exist but are not applied to a real transport | PARTIAL; native transport experiment required |
| apprt.zig | `.windows => windows` selects the scaffold; `apprt.ipc` exports legacy mod | compile selection is not runtime capability | RESOLVED role |
| ipc/protocol.zig | v1 JSON agent protocol; pane IDs are raw core surface IDs; command table and parser are real | handle epoch/stale-instance semantics are absent from ID itself | PARTIAL; lifecycle identity decision required |
| ipc/protocol.md | explicitly says app-thread hop/server startup absent and real focus/search unsupported | G4 DONE cannot qualify mounted journey | RESOLVED contradiction, blocking implementation |
| ipc/app_host.zig | GTK-only real host; parser/display feed, not child input; direct access needs mailbox hop | child-input and native mounting are separate obligations | PARTIAL/blocking |
| ipc/server.zig | actual threaded server implementation exists, but application caller/startup not established | module tests do not imply reachable product surface | PARTIAL |
| ipc/auth.zig | fail-closed token design, generated/file/env token machinery | useful security primitive if mounted; platform/transport policy still separate | PARTIAL |
| ipc/events.zig | bounded subscriber/event machinery with sequence/drop semantics | supporting live state; does not solve product/process epoch identity | PARTIAL |
| ipc/fake_host.zig | test host | test fixture only | RESOLVED role |
| ipc/handler.zig / pane.zig / state.zig | command dispatch/registry/state machinery | requires real Host and lifecycle identity | PARTIAL |

### Architecture facts now stable enough for experimental work

1. The current Windows path is a scaffold, not a nearly-finished GUI hidden behind packaging.
2. New agent IPC and legacy Ghostty IPC are separate surfaces; exporting/importing one does not mount the other.
3. v1 `pane.write` display-feed semantics must not silently become child input.
4. Raw surface ID alone is insufficient for stale-handle safety across instance/restart unless an enclosing instance/epoch is proven.
5. Named-pipe security constants are design evidence only until applied to actual handles.
6. An alternative comparison must compare effects/workflows, not require identical protocol shapes or return codes.

## Experimental handoff consequence

K-E01's inventory portion is substantially advanced by the complete API tree enumeration and this spine resolution. It is **not closed** because useful history, full caller/build reachability, wrapper ownership and complete source-family semantic review remain open. K-E02/K-E03 may be prepared, but broad code modification should wait for a real checkout receipt and accepted experiment configuration.
