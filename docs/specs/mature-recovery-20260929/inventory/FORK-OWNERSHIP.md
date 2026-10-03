# Khostty fork ownership map — pass 6

Frozen product: `a29aa9c6553d9f42aa68e2919116c0f6d53f329d`. Upstream merge base: `d4c88d8069912b653d707191388ca98e24751f12`.

## Top-level Git-object comparison

Exact tree/blob identity gives a much cleaner ownership denominator than filenames or documentation claims:

- **43 top-level entries are byte/tree-identical to the merge base.**
- **13 top-level entries are added.**
- **6 top-level entries are modified.**
- **0 top-level entries were removed at this boundary.**

Large trees proven wholly identical at this merge base include `macos/`, `test/`, `include/`, `example/`, `flatpak/`, `images/`, `nix/`, `pkg/`, `po/`, `snap/`, and `vendor/`. These remain relevant inherited product/runtime/support evidence, but they are not fork differentiation.

Added top-level families include `bench/`, `conformance/`, `docs/`, `khostty-go/`, `khostty-python/`, `khostty-vt/`, `packaging/`, and `wasm/`, plus fork automation/config. Modified top-level families include `.github/`, `.gitignore`, `README.md`, `build.zig`, `dist/`, and `src/`.

## High-priority source ownership

A recursive comparison of current `src/` against the merge-base `src/` produces the following for the critical surfaces already under investigation:

| Surface | Exact result | Consequence |
|---|---|---|
| `src/apprt/windows/` | 11 current blobs; all **ADDED** | Genuine fork-owned implementation surface |
| `src/apprt/ipc/` | 11 current blobs; 10 new agent-protocol/server/host files plus `mod.zig` | Mixed: do not count the whole directory as new behavior |
| legacy IPC module | current `ipc/mod.zig` and baseline `ipc.zig` have 253 lines each and become **exactly identical after correcting only their relative import paths** | The public `apprt.ipc` module remains inherited three-action Ghostty IPC moved into a directory; the new agent server is adjacent, not the same mounted surface |
| `src/apprt.zig` | MODIFIED | It redirects inherited IPC import to `ipc/mod.zig` and adds/selects Windows runtime; it does not itself start the new agent server |
| `src/terminal/c/` selected public ABI implementation | 36 blobs inspected; **all byte-identical** | C terminal API and ABI manifest are inherited at this merge base |

This resolves an important semantic confusion: **the fork-owned JSON agent protocol is not the same thing as the inherited `apprt.ipc` exported by `src/apprt.zig`.** Native agent-server startup therefore cannot be inferred from the fact that `apprt.ipc` is imported.

## Exact fork candidates for architecture evaluation

1. Windows host/runtime implementation and its build/distribution integration.
2. Ten new agent IPC/server/host files and whatever native hooks are required to mount them.
3. Polyglot wrapper packages.
4. WASM package/distribution work.
5. Conformance and benchmark infrastructure.
6. Fork-specific build/CI/distribution changes.

Everything else must first prove it differs from upstream before being awarded differentiation.

## Next closure work

Trace callers/imports of `server.zig`, `AppHost`, and the native Windows/GTK/macOS lifecycle; compare wrapper behavior rather than inherited C APIs; classify modified `build.zig`, `.github` and `dist/`; then execute K-E02/K-E03 against alternatives. Git-object identity establishes ownership, not runtime correctness or user value.
