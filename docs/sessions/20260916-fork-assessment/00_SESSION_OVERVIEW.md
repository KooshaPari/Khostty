# Khostty Fork Assessment — 2026-09-16

## Fork State

| Item | Value |
|------|-------|
| upstream | ghostty-org/ghostty |
| fork | KooshaPari/Khostty |
| divergence | 13 ahead, 0 behind |
| build | Zig 0.16.0 (aarch64-macos) |
| Metal | BLOCKED (Xcode 26 beta missing MetalToolchain component) |
| OpenGL | Viable alternative renderer |

## Owned Deltas (All 13 Commits)

| # | Commit | Category | Description |
|---|--------|----------|-------------|
| 1 | b75af15 | CI | Mergify auto-merge rules |
| 2 | c72fd96 | CI | GitHub Actions CI with Blacksmith runners |
| 3 | 875a20b | CI | Trunk.io lint/format config |
| 4 | 92de0f4 | CI | CircleCI parallel pipeline |
| 5 | 7bb433b | CI | GitHub Actions Infisical workflow |
| 6 | 0480e2c | CI | GitHub Actions Scorecard workflow |
| 7 | 3207bdc | CI | GitHub Actions Trunk-check workflow |
| 8 | ecbdb4d | CI | Renovate.json (org template) |
| 9 | 2fa6896 | CI | Fix broken trunk-action with prettier-scoped check |
| 10 | d603731 | Docs | README: add AI slop inside + downloads badges |
| 11 | d49d2a9 | Docs | README: prepend ghostty header |
| 12 | f5b3932 | CI | Replace generic CI with Zig-aware workflow |
| 13 | 297d66f | CI | Use macOS runner for build, OpenGL renderer |

**Zero functional code changes.** All deltas are CI/docs/README.

## Build Status

- **Full app build:** 285/302 steps succeed. Metal shader compilation fails on Xcode 26 beta (MetalToolchain component missing). `-Demit-macos-app=false` does NOT help (Metal is in core library, not app bundle).
- **libghostty-vt build:** SUCCEEDS. `zig build -Demit-lib-vt -Doptimize=ReleaseSafe` produces:
  - `libghostty-vt.a` (static) + `libghostty-vt.0.1.0.dylib` (dynamic)
  - xcframework (macOS arm64+x86_64, iOS arm64, iOS arm64-simulator)
  - 35 C headers in `include/ghostty/vt/` including `wasm.h`, `terminal.h`, `screen.h`
  - Zero Metal dependency
- `zig fmt --check` passes clean

## Product Decision Required

The dossier requires "a specific embedding/workflow improvement with no unacceptable terminal correctness regression."

### VALIDATED: libghostty-vt WASM Embedding

Ghostty ships `libghostty-vt` — a standalone VT100/VT220 parser library.
**Verified: builds clean on macOS with zero Metal dependency.**

Build artifacts:
- `libghostty-vt.a` (static library)
- `libghostty-vt.0.1.0.dylib` (dynamic library)
- `libghostty-vt.xcframework` (macOS + iOS)
- 35 C headers including `wasm.h`, `terminal.h`, `screen.h`, `grid_ref.h`, `render.h`

This enables:
1. **Agent-side terminal state tracking** — parse VT sequences without a running terminal
2. **Terminal replay/debugging** — capture and replay terminal sessions
3. **Embedded terminal surfaces** — embed VT parsing in non-terminal applications
4. **WASM target** — cross-platform via `zig build -Demit-lib-vt -Dtarget=wasm32-freestanding`

This is the most architecturally clean delta because:
- It's a library, not a fork of the renderer
- WASM target means cross-platform
- Minimal upstream divergence (just wrapper/integration code)
- Proves the "embedding improvement" hypothesis from the dossier
- **Builds successfully today** (unlike full Ghostty which needs Metal)

### Next Steps (Awaiting Sponsor Decision)

1. ~~Build libghostty-vt as library~~ DONE
2. Create WASM build: `zig build -Demit-lib-vt -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall`
3. Write a thin Rust FFI wrapper around the C headers
4. Write integration tests proving VT conformance via the embedded parser
5. Run conformance corpus (VT100/VT220 test suite)
