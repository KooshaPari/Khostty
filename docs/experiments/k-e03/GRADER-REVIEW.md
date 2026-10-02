# Experimental grader review — pass 9 source re-grade

Candidate branch: `experiment/mature-recovery-k-e03`. Baseline: `a29aa9c6553d9f42aa68e2919116c0f6d53f329d`.

Status: **BLOCKED ON NATIVE EXECUTION / TWO-ARTIFACT COMPARISON. NO FORK ACCEPTANCE.**

This supersedes the earlier source-level FAIL/REVISE review for the final branch tree.

## Source contract now addressed

- evidence mode can require a real native library and fail instead of silently cargo-checking unlinked;
- explicit library/include paths support out-of-tree consumer setup;
- Rust consumer executes create/write/resize/render/search/snapshot-restore;
- direct C comparator now exercises the same behavior class rather than only create/write/free;
- missing-library control is fail-closed;
- Rust lifetime misuse is a compile-fail control;
- existing `abi_layout` + `ffi_coverage` tests are invoked against the supplied configuration;
- receipt records native artifact digest, claimed source/origin, commands/stdout/stderr, wrapper/direct LOC and explicit install steps.

## Still required before experimental PASS

1. Execute the harness against an exact Khostty-built native library and preserve its build receipt.
2. Execute it separately against an independently built upstream/merge-base or current-upstream library compatible with the comparison contract.
3. Authenticate library-source provenance; the CLI source-SHA/origin fields remain caller claims.
4. Record exact compiler/Rust/Zig/target/config and native artifact hashes.
5. Confirm the ABI/FFI verification actually passes on both intended subjects or document incompatibility as a result.
6. Compare package/install dependency footprint and failure modes from clean out-of-tree directories.
7. Independent reviewer evaluates whether wrapper safety/ergonomics justify maintenance; no weighted winner is preselected.

Do not intentionally dereference freed native state merely to manufacture a crash. Compile-time lifetime rejection plus safe invalid-handle/API controls are preferable.

## Disposition

Keep experimental. A successful wrapper experiment can justify preserving/extracting the wrapper without justifying the Khostty terminal fork, Windows runtime, or agent IPC.


## Independent audit delta — 2026-09-30

The first native K-E03 run built `libghostty-vt.a` successfully and recorded SHA-256 `6b477a3844fc8767713a2ea43e6aa10bab5956d468bac683eb91da6860036f0d`, but the harness itself then failed with a Python syntax error caused by literal `\\n` text. This is a harness failure, not wrapper evidence, and no experimental credit is awarded from that run.

The syntax defect is fixed. The harness now derives `GHOSTTY_VT_LINK_KIND=static` when the supplied artifact is `.a`; otherwise Rust could search for a dylib while the workflow had built a static archive. The receipt records link kind.

The experiment workflow now:
- validates harness syntax before the expensive native build;
- builds and hashes the exact Khostty candidate static library;
- executes wrapper + direct-C comparison against it;
- separately checks out Ghostty at merge base `d4c88d8069912b653d707191388ca98e24751f12`, builds that native library, and runs the **same current wrapper/direct-C harness** against upstream headers/library;
- pins checkout/toolchain/artifact actions and records tool versions.

Use the exact **push** workflow run as candidate evidence. PR-event runs can incorporate the moving PR base and are not equivalent to branch-head execution because Khostty main has advanced beyond the frozen recovery source.
