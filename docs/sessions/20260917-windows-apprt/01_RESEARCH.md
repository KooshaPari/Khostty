# Windows AppRT scaffold

Observed 2026-09-17. Explicit user scope supersedes WBS 3.2/3.3 Win32 calls:
only scaffold, interface and build selection are authorized here.

GTK's facade exports App, Surface and resourcesDir. App.init takes *CoreApp and
empty options, followed by run and terminate. The shared runtime is selected in
src/apprt.zig, with its enum in src/apprt/runtime.zig and build option in
src/build/Config.zig. SharedDeps has an exhaustive runtime dependency switch.
PascalCase App.zig/Surface.zig match GTK and the user's explicit file paths.

No Win32 declarations or API calls are introduced. init/run return
error.Unimplemented. Null HWND means absent, not a usable window.
The configured Zig on PATH reports 0.16.0; build.zig.zon requires 0.15.2.
No product dossier was present at the configured docs-5 products path.
Recursive worker delegation was rejected because this session is itself a worker.
