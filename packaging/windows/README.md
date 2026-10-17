# Windows desk build gate

Install the `minimum_zig_version` from `build.zig.zon` (currently 0.16.0)
from ziglang.org, verify its published SHA-256, and add its directory to the
current session's PATH. Git Bash and Inno Setup 6.3+ are also required.

From the repository root in PowerShell 7:

```powershell
./packaging/windows/build.ps1 -Jobs 2
```

This rebuilds the x86_64 Windows GNU DLL and executable, runs
`test-windows-apprt` with a native 60-second per-test timeout, compiles the
existing Inno installer definition, and
checks the executable's `+version` exit status. Two parallel Zig jobs bound
memory pressure on the 16 GB desk. Logs are under `dist-release/logs/` and
the installer is under `dist-release/stage/windows/Khostty-*-win64/output/`.
Set `KHOSTTY_ISCC` if Inno Setup is installed outside its default location.
Errors stop the gate; a compiled installer does not prove installation,
GUI rendering, input, or shell operation.

The complete test-build process tree also has a 15-minute wall-clock limit.
This independently fails with `error.TestsTimedOut` if the native per-test
timeout protocol stops responding. It never converts a timeout into a pass.

The workflow is `.github/workflows/windows-desk.yml`. It only requests
`[self-hosted, Windows, X64]`, has no hosted fallback, rejects external
fork PRs before allocating a runner, and fails if the assigned host is not
`KOOSHAPARI-DESK`. On 2026-10-16 the Khostty runner API
returned zero registered runners. No desk-specific label was available to
verify. Register the desk for this fork before expecting CI execution;
local desk receipts remain distinct from Actions job results.

GUI acceptance must separately launch the freshly built executable and
record its actual result. The lifecycle and renderer scaffolds can return
`error.Unimplemented`; that is a failed GUI gate, even if `+version` passes.
Installer install/uninstall verification is also a separate acceptance gate.
