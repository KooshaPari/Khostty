# K-E03 independent source review — candidate branch

Candidate: experiment/mature-recovery-k-e03, compared to frozen source a29aa9c6553d9f42aa68e2919116c0f6d53f329d. Review date 2026-09-30. Source review only; no native library/build execution here.

## Candidate scope

Branch is 4 commits ahead and modifies Rust build.rs plus adds tools/k_e03_compare.py. Treat as an untrusted experimental candidate.

## Contract grade

- Missing-library false green: PROVISIONAL PASS — KHOSTTY_VT_REQUIRE_LINK turns missing library into build failure.
- Exact native artifact digest: PROVISIONAL PASS — harness records SHA-256.
- Linked Rust consumer execution: PROVISIONAL — harness runs out-of-tree Cargo consumer; must be actually executed.
- Direct C comparator: PROVISIONAL — builds/runs direct C consumer against same supplied library.
- Out-of-tree consumption: PROVISIONAL PASS by design — temp consumer is outside repository.
- ABI/use-after-close controls: **NOT MET** — harness explicitly defers ABI drift, snapshot/search and use-after-close.
- Upstream-vs-Khostty native comparison: **NOT MET** — direct C and Rust wrapper use the same supplied library. This isolates wrapper value but not independent upstream versus Khostty artifacts.
- Artifact/source authentication: PARTIAL — revision/origin are caller claims; separate build receipt required.
- Packaging/install friction: PARTIAL — path dependency, not a published/exported package installation.

**Overall K-E03 candidate: useful phase-1 harness, NOT a completed bake-off.**

## Required phase-1 execution

Run twice with independently built/authenticated native artifacts: Khostty and selected upstream Ghostty/libghostty-vt if API-compatible. Preserve source commit, dirty state, Zig/compiler target/config, artifact SHA-256, exported-symbol/version evidence and exact harness command. Within each run use the same artifact for direct-C and wrapper consumers to isolate wrapper cost; compare the two runs separately for native-fork value.

## Required harness extension before acceptance

- snapshot/restore and search/read behavior;
- explicit close then safe invalid-operation control without invoking UB;
- ABI/type-manifest mismatch fixture that fails before unsafe use;
- cargo/rustc/cc/Zig versions and lock identity;
- distinguish handwritten wrapper LOC from generated FFI/tests;
- package/install experiment beyond a path dependency if standalone distribution is accepted scope.

No conclusion to keep/remove/upstream the wrapper is yet justified.
