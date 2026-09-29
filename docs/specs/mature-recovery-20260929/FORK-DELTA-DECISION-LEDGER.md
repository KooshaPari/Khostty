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
