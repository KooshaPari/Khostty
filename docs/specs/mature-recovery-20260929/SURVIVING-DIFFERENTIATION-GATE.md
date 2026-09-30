# Khostty surviving-differentiation gate — pass 6

Frozen product: `a29aa9c6553d9f42aa68e2919116c0f6d53f329d`.
Upstream merge base: `d4c88d8069912b653d707191388ca98e24751f12`.
Status: **candidate build/bootstrap gate, not an architecture freeze**.

The fork is not evaluated as one indivisible proposition. Large terminal/macOS/API/test trees are proven inherited, while the meaningful owned candidates are much narrower.

## Candidate deltas still permitted to survive

| Delta | Current evidence | Strongest falsifier / alternative | Survival witness |
|---|---|---|---|
| Windows native host | Khostty has an 11-file added runtime, but App init/register/run are Unimplemented | Mature external Ghostty Windows fork; thin libghostty host | Native create/input/render/clipboard/IME/resize/shutdown journey plus maintenance/delta comparison |
| Agent control | 10 new JSON server/host files exist but are unmounted; v1 display feed != child input | Ghoztty same-family IPC, WezTerm/kitty/cmux | Demonstrated unmet semantics: causal completion, exact identity/event/state/auth/platform behavior that justify extra surface |
| Rust/Go/Python wrappers | Added fork packages; Rust native tests can compile away without library | direct upstream libghostty C use, generated bindings | Real native consumer with artifact-bound tests, ownership/thread/error ergonomics and maintenance comparison |
| WASM distribution | fork-added package/build surface | upstream WASM/libghostty facilities + thin package | Browser/runtime consumer evidence and a concrete packaging/API gap |
| Conformance harness | fork-added verification surface | upstream tests/conformance | Mutation sensitivity against fork-relevant regressions; reusable without needing a broad fork |
| Benchmark harness | fork-added verification surface; historical measurements non-qualifying | existing upstream benchmarks | Controlled revision-pinned quiet-host measurements only if an accepted performance question exists |
| Fork-specific CI/distribution | modified/added support surface | upstream workflows + thin fork config | Required configurations actually run; no skipped/advisory false greens; support cost justified |

## Explicitly not differentiation

At the compared baseline:
- terminal C API and ABI type-manifest implementation;
- public headers inspected;
- macOS runtime tree;
- inherited test/fuzz corpus;
- examples and major support/vendor trees.

They remain product dependencies/compatibility obligations, but cannot justify the fork.

## K-E02 control experiment contract

The primary same-family comparator is pinned Ghoztty plus another mature programmable terminal where the accepted outcome is not Ghostty-specific.

For one real terminal process/session:

1. Create a target with known identity and working directory.
2. Start a verifier-owned child that can emit an external nonce receipt.
3. Send input to the child, not merely parser/display state.
4. Independently observe the child receipt.
5. Read terminal output/state from the exact target.
6. Create/focus/close another target without mutating the first.
7. Replace only the controller; reconnect.
8. Close/recreate and reject stale identity/evidence.
9. Exercise wrong-instance targeting with two instances where supported.
10. Exercise event loss/causal completion only for systems claiming those semantics.

Record PASS / FAIL / UNSUPPORTED / BLOCKED per capability. Unsupported alternatives do not become zeros in an aggregate score; the purpose is to isolate unmet accepted needs.

### Causal-completion hypothesis

Ghoztty source already demonstrates child input, read, target naming, per-instance socket identity and substantial lifecycle behavior. Its create/split implementation may return after request acceptance while UI mutation is still dispatched asynchronously. Khostty may retain a more expensive protocol only if **causally confirmed creation/identity** is an accepted need and can be implemented reliably.

If that gap is not valuable in real agent workflows, it is not differentiation.

## K-E03 embedding experiment contract

Use the exact native library artifact and prove the integration suite actually exists/runs.

For each wrapper under evaluation:
- construct a terminal;
- feed VT state;
- query geometry/text/state as applicable;
- resize;
- exercise at least one callback/effect;
- dispose safely;
- include repeated/concurrent lifecycle where supported;
- record native artifact digest and wrapper candidate;
- compare the same consumer outcome with direct upstream C API or a generated binding.

The wrapper survives only where it materially improves safe ownership, error handling, packaging, ABI drift detection or language ergonomics relative to a thin alternative.

The ABI manifest itself is inherited and earns no differentiation credit.

## Windows decision rule

Feature existence is already contested by a substantive external Windows Ghostty fork. Therefore the choices are not “build Khostty Windows or have no Windows Ghostty.”

Compare:
- Khostty's current intended runtime;
- adapting/rebasing the mature Win32 fork or extracting its runtime delta;
- a smaller libghostty Windows host.

Judge native behavior and ownership burden:
- window lifecycle;
- ConPTY/child process;
- keyboard including AltGr/IME;
- mouse;
- renderer/glyph fallback;
- clipboard/bracketed paste;
- tabs/splits if mature scope requires them;
- DPI/resizing;
- shutdown/restart;
- accessibility;
- packaging/update;
- upstream merge surface.

Novelty is irrelevant.

## Fork retention rule

For each surviving custom subsystem require:

```
accepted journey/obligation
+ strongest alternative
+ precise unmet gap
+ candidate-bound experiment
+ security/lifetime constraints
+ ongoing merge/maintenance cost
+ reversibility plan
```

If any element remains absent, status is UNVERIFIED, not “keep.”

A subsystem can be extracted into a thin companion/package even if the current monorepo implementation works. Sunk implementation volume is never a retention criterion.

## Possible outcomes

The gate deliberately permits all of these:
- retain Khostty as a scoped fork because Windows/native integration truly requires it;
- retain the fork but delete/replace the custom agent server;
- move wrappers/conformance into thin upstream-adjacent packages;
- use an existing terminal for agent control while retaining libghostty embedding work;
- collapse most owned work onto upstream and keep only verification/distribution;
- retain the current architecture if experiments actually beat the thinner alternatives.

No overall verdict is issued before K-E02/K-E03 evidence.
