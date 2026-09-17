# Windows AppRT scaffold validation

Observed 2026-09-17, 04:42 Pacific. Owner: Jcode Windows scaffold worker.

Use `zig build -Dtarget=x86_64-windows-gnu -Dapp-runtime=windows`.
Windows remains opt-in. macOS retains `none`, Linux retains `gtk`.
The scaffold does not provide a working Windows terminal or native event loop.

| Check | Observation |
|---|---|
| Window unit test | 1/1 passed |
| Surface association test plus Window | 2/2 passed, Surface owned by separate worker |
| Runtime enum/defaults tests | 2/2 passed |
| Surface cross-compilation | x86_64-windows-gnu, `zig test ... -fno-emit-bin` passed |
| App and interface syntax | `zig ast-check` passed |
| Interface standalone semantic test | Blocked by imports outside standalone module root |
| Changed-file formatting | `zig fmt --check` passed |
| Windows target build graph / --help | Passed, lists windows enum option |
| Non-Windows target with windows option | Correctly rejects with InvalidAppRuntimeTarget |
| Full Windows executable (ghostty-vt.dll + ghostty-vt.pdb) | Compiled and linked; exe link failed on concurrent src/cli/new_window.zig:249 error.IPCFailed not in destination error set |
| Hosted and native GUI acceptance | NOT RUN |

Full build first found the missing windows SharedDeps switch, now fixed.
Old cache then reported missing uucode. A fresh cache under Jcode scratch
advanced past dependency resolution. An unrelated IPC directory-move bug was
reported to the coordinator; IPC owner fixed it as `cd1ed5c60`. After that
fix, all C/C++/Zig dependencies for the Windows target compiled. The link
step that builds `ghostty-vt.dll` succeeded. The final `ghostty` exe fails
with `src/cli/new_window.zig:249: error: expected type 'error{Unimplemented}',
found 'error{IPCFailed}'`. That error is in CLI code outside this worker's
scope. The scaffold itself compiled for x86_64-windows-gnu.

App init/run and native operations fail with error.Unimplemented. Void App
hooks are no-ops. Resource discovery returns empty ResourcesDir. The core
Surface bridge hooks remain explicitly documented as pending in interface.zig.
All exhaustive runtime switches include windows, including lazy GObject branches.

## Ownership and contamination history

Commit b2c388c9b unintentionally included other workers' staged conformance
changes and win32api.zig. This worker did not author those changes. The
git-commit wrapper metadata was logged as tx-agent human tx-validated manual
because env detection occurred outside the wrapper scope. History was not
rewritten.

The interface contract was committed in `11f952990 feat(windows): define
standalone App runtime contract` with explicit tx-agent jcode tx-validated
manual tx-task G3.2 metadata.

The build wiring (build.zig, src/apprt.zig, src/apprt/runtime.zig,
src/build/Config.zig, src/build/SharedDeps.zig, the lazy GObject switches,
the InvalidAppRuntimeTarget guard, and this testing doc) was staged by this
worker, but the concurrent IPC owner committed it as part of
`3cccd3e31 feat(ipc): G4.11 app_host.zig` under tx-task G4.11. This worker
did not amend or rewrite that commit. The substantive Windows wiring is
present on `main` even though ledger attribution lands under G4.11.

Surface is lowercase surface.zig. mod.zig uses exact case for case-sensitive
hosts. The Surface owner restored and committed their implementation in
933bf771a; that work is preserved.
