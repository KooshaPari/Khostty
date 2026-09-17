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
| Full Windows executable | UNVERIFIED, see blockers below |
| Hosted and native GUI acceptance | NOT RUN |

Full build first found the missing windows SharedDeps switch, now fixed.
Old cache then reported missing uucode. A fresh cache under Jcode scratch
advanced past dependency resolution and exposed unrelated IPC directory-move
errors: src/apprt/ipc/mod.zig imported ../quirks.zig and ../lib/main.zig, resolving
to missing src/apprt/quirks.zig and src/apprt/lib/main.zig. Reported to coordinator
for IPC owner. Broad build cancelled after capturing these errors.

App init/run and native operations fail with error.Unimplemented. Void App
hooks are no-ops. Resource discovery returns empty ResourcesDir. The core
Surface bridge hooks remain explicitly documented as pending in interface.zig.
All exhaustive runtime switches include windows, including lazy GObject branches.

Commit b2c388c9b unintentionally included other workers' staged conformance
changes and win32api.zig. This worker did not author those changes. Its wrapper
metadata incorrectly identified human/manual. History was not rewritten.
Subsequent commits use explicit pathspecs and ledger metadata. During concurrent
editing this worker incorrectly restored the original surface stub once. The
Surface owner subsequently restored and committed their implementation in
933bf771a. That implementation is preserved. Tracked file is lowercase
surface.zig, so mod.zig uses exact case for case-sensitive hosts.
