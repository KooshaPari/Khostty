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
