# Khostty fork-delta decision ledger — corrected in pass 5

Observed 2026-09-29. Frozen product `a29aa9c6553d9f42aa68e2919116c0f6d53f329d`; earlier comparison target `f9e82709360d97b2246718f774c544de0f16787b`; merge base `d4c88d8069912b653d707191388ca98e24751f12`. The earlier 207-ahead/145-behind result remains a dated topology observation, NOT a count of product requirements or unique contributions. This pass did not rerun the whole compare.

## Correction: the ABI manifest is inherited

The previous ledger called `ghostty_type_json` a potentially genuine fork contribution. Exact Git blob comparisons falsify that attribution. Both `include/ghostty/vt/types.h` (`059bc5c8fd5cf971eb02611ab1033f906963b42f`) and the implementation `src/terminal/c/types.zig` (`4184de8227ec74cbe1d5e4aad5978d206138de2b`) are identical in frozen Khostty and its upstream merge base. The implementation was also read through `ghostty-org/ghostty` at that base, not merely assumed to be upstream from its filename.

Wrappers using the manifest may be useful fork work. That does not make the underlying manifest generator a fork invention. No build-versus-buy decision may rely on the earlier attribution. See `pass5/EXPERIMENT-RECEIPT.json`.

| Subject | Evidence classification | Current bootstrap disposition |
|---|---|---|
| Terminal/ABI manifest primitives above | Proven inherited at the compared revisions | USE upstream; do not award fork differentiation |
| Polyglot wrappers | Distinct wrapper code exists; complete ABI/ownership/runtime qualification remains open | Evaluate real consumer outcomes against upstream APIs/generated bindings |
| Conformance harness | Fork-owned verification surface per earlier diff; historical receipts not rerun | Preserve and test mutation sensitivity; usefulness does not require owning the whole terminal |
| Windows host | Selectable runtime, but byte-verified App init/register/run return Unimplemented | Genuine implementation gap, not merely absent GUI screenshot; native spike remains necessary |
| Agent IPC | Protocol modules versus actual native mounting remain distinct; exported `apprt.ipc` is legacy mod | Compare thin integration and existing control surfaces; do not infer full app mounting from module tests |
| Benchmarks, packaging, CI | Verification/support work, not automatic differentiation | Keep only where justified by accepted configurations and independently bound evidence |

## Comparator pinned, not adopted

Ghoztty source `fd3838acfa834c29e99616cdc8500c0208a13a09` has a README describing `+new-window`, `+split`, `+close`, named targets, working directory/command arguments and idempotent behavior. Root LICENSE is MIT. Those are source-document facts; no runtime test, complete source-delta assessment or dependency license audit was performed. Importantly, silent success closing a nonexistent target may be valid idempotency, not a false green. Test unwanted effects and instance/name reuse rather than forcing identical return codes across competitors.

For an embedding outcome, compare upstream libghostty plus a thin host/binding. For an agent-control outcome, compare the strongest applicable existing terminal/control composition. Do not force desktop automation and library embedding into one averaged winner. Windows platform obligations remain separate from Unix/macOS control claims.

## Decision witnesses

A retained custom subsystem must identify accepted need, strongest realistic alternative, exact unmet behavior, current source delta, native/consumer experiment, security/lifetime constraints and ongoing merge cost. The terminal-child nonce journey must distinguish parser output injection from child input. The embedding journey must exercise allocation/thread/callback lifetimes, not just compile headers.

Full tree enumeration, useful history, capability reachability, native comparisons, project health and mature-scope authority remain OPEN. Neither delete-the-fork nor keep-everything has passed. Read `DEVELOPER-HANDOFF.md` for the bounded experiments ready now.

## Pass 6 Windows bootstrap correction

External Windows implementation changes the default decision:

- upstream Ghostty still has no Windows app runtime at `f9e82709360d97b2246718f774c544de0f16787b`;
- `shiweis/ghostty-windows@119b9270c8585fa3ae6969c353767fab5a32e438` has a substantial native Win32 runtime, direct parent `ghostty-org/ghostty`, MIT root license, real Windows CI and a successful pinned-head build/test run;
- its current-upstream comparison is 241 commits ahead / 345 behind. This is not a low-cost drop-in dependency; it is prior implementation that must be adapted/evaluated, with explicit merge-debt ownership;
- upstream PR #12167 was closed around reviewability/toolkit/maintenance concerns, especially long-term maintainer ownership, rather than a demonstrated impossibility of a Win32 host.

**Bootstrap order for Windows is now: ADAPT/PORT EXISTING WIN32 DELTA → thin libghostty host if sufficient → BUILD CUSTOM only for demonstrated missing accepted obligations.**

The K-E02 comparison must include the external Win32 fork as the primary native implementation reference. Do not spend effort recreating tabs/splits/input/IME/ConPTY/windowing simply because Khostty already has scaffold files.


## Pass 10 same-family source comparison — Ghoztty already demonstrates the app-thread bridge pattern

Pinned Ghoztty source fd3838acfa834c29e99616cdc8500c0208a13a09 was inspected beyond its README. Its macOS IPCServer.swift receives framed JSON socket requests, but operations that touch terminal/window state dispatch onto DispatchQueue.main (and in some cases MainActor) and synchronize the response. handleSendKeys resolves a stable target, switches to the main queue, and writes PTY input through the surface model; handleRead likewise reads terminal text on the main queue. Layout mutation uses the same pattern.

Ghoztty also bakes both its owning IPC socket path and pane identity into child environments (GHOZTTY_IPC_SOCKET, GHOZTTY_PANE_ID). CLI commands carry caller-pane identity as a default anchor so a later focus change cannot silently redirect an agent command. Explicit target/pane/from-focused flags override that default. Named creation is idempotent and stale registry entries are pruned.

This is direct architectural prior art for K-E02a:
- do not let connection threads directly touch app/terminal state;
- cross into the runtime-owned thread and correlate completion;
- preserve caller/instance/pane identity independently of current focus;
- distinguish PTY child input from parser/display feed.

It does not establish Ghoztty as the product choice: the inspected implementation is macOS/Swift-specific, has a different protocol and feature scope, and has not been runtime-qualified here. But it materially raises the custom-build burden: Khostty cannot claim the app-thread bridge or stable caller-pane targeting concept as novel, and should adapt/learn from this pattern rather than invent an unsafe direct mount.

## Pass 10 Windows comparator expansion — do not collapse onto one fork

Fresh source inspection on 2026-09-30 materially expands the Windows bootstrap set.

### shiweis/ghostty-windows

Current README claims a native Win32 runtime with WGL/OpenGL, ConPTY, DirectWrite discovery, IME, tabs/splits, PowerShell integration and 66/66 apprt action coverage. Its documented build target is Zig 0.16 with `-Dapp-runtime=win32 -Dtarget=x86_64-windows-gnu`; it also documents 25+ Windows/WSL-driven tests. Packaging is explicitly still incomplete. Treat feature claims as source assertions until Khostty's held-out build/runtime harness reproduces them.

### cullendotdev/winghostty

The current status/capability documents describe another substantial Win32 host: Windows 10/11 x64+ARM64, native windows/tabs/splits, IME, session-state restore, shell profiles including PowerShell, WGL terminal rendering plus separate D3D11/DirectComposition chrome, partial UI Automation, local automation through JSON/list + allowlisted perform-action IPC, and packaged WinGet/Scoop distribution. Its own docs call accessibility partial and Win32 extraction incomplete. This is a distinct architecture and therefore a useful contradiction to any assumption that one Win32 host shape is uniquely correct.

### upstream ecosystem signal

The upstream Windows discussion in 2026 contains multiple active approaches, including a WinUI 3 + DirectX/libghostty prototype and a separate Rust-shell Windows port. Upstream discussion also continues to treat frontend/framework choice as unsettled. Therefore Khostty must not equate "Windows support" with blindly transplanting one existing fork.

### Revised experimental comparison

Before custom Windows host implementation, compare at least these viable families on the same Khostty obligations:

1. adapt the substantial Zig/Win32 apprt delta;
2. adapt the winghostty Win32 host and its automation/session-state ideas;
3. thin libghostty host using a native Windows UI stack where that lowers merge debt;
4. custom Khostty host only for obligations still unserved after the above.

The comparison must exercise native build, ConPTY child nonce input/output, exact pane identity, tabs/splits, PowerShell cwd/title/prompt integration, IME, restart/session semantics, automation/control-plane mounting, packaging, accessibility, and measured upstream-sync conflict burden. README capability counts are not acceptance evidence.
