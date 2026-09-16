# Khostty First Handoff

**Date:** 2026-09-16
**Repo:** KooshaPari/Khostty (fork of ghostty-org/ghostty)
**Branch:** main
**Divergence:** 14 ahead of upstream (11 CI/docs + 3 CI fixes + 1 docs)

---

## 1. Current Revision and Artifact Profile

| Item | Value |
|------|-------|
| Zig version | 0.16.0 (required by build.zig.zon) |
| Upstream commit | ghostty-org/ghostty main |
| Fork commits | 14 ahead, 0 behind |
| Build target | aarch64-macos.13.0 (native) |
| Full app build | BLOCKED: Xcode 26 beta missing MetalToolchain component |
| libghostty-vt build | PASS: static + dynamic + xcframework |
| WASM build | IN PROGRESS: `zig build -Demit-lib-vt -Dtarget=wasm32-freestanding` |
| zig fmt | PASS |

### Build Commands

```bash
# Full app (needs working Metal toolchain)
zig build -Doptimize=ReleaseSafe

# VT parser library only (no Metal needed)
zig build -Demit-lib-vt -Doptimize=ReleaseSafe

# WASM target
zig build -Demit-lib-vt -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall

# Tests
zig build test -Dtest-filter=<filter>

# Format check
zig fmt --check src/ build.zig
```

## 2. Indexed Paths and Unknowns

### Owned Paths (fork delta)
| Path | Category | Status |
|------|----------|--------|
| `.github/workflows/ci.yml` | CI | Zig-aware, macOS runner |
| `.github/workflows/trunk-check.yml` | CI | DELETED (generic template) |
| `.github/workflows/infisical.yml` | CI | DELETED (generic template) |
| `.github/workflows/scorecard.yml` | CI | DELETED (generic template) |
| `.circleci/config.yml` | CI | DELETED (generic template) |
| `.mergify.yml` | CI | DELETED (generic template) |
| `renovate.json` | CI | DELETED (generic template) |
| `trunk.yaml` | CI | DELETED (generic template) |
| `README.md` | Docs | Khostty branding |
| `docs/sessions/` | Docs | Session docs |

### Upstream Paths (read-only, tracked via rebase)
| Path | Role |
|------|------|
| `src/` | Shared Zig core (terminal, renderer, VT parser) |
| `src/renderer/` | GPU rendering (Metal, OpenGL) |
| `src/apprt/gtk/` | GTK app (Linux/FreeBSD) |
| `macos/` | macOS native app (Swift) |
| `build.zig` | Build system entry |
| `build.zig.zon` | Package dependencies |

### Unknowns
- WASM build outcome (in progress)
- VT conformance test results (not yet run)
- Metal Toolchain availability timeline (Xcode beta issue)
- Whether upstream CI uses custom runners that we can't replicate

## 3. Accepted Obligations

| Obligation | Status |
|------------|--------|
| Keep fork rebased on upstream | DONE (0 behind) |
| Maintain CI that actually builds/tests | DONE (Zig-aware) |
| Prove embedding improvement with no correctness regression | NOT STARTED |
| Run conformance corpus | NOT STARTED |
| Comparative benchmarks | NOT STARTED |

## 4. Two Strongest Dissatisfaction Records

1. **Metal Toolchain blocked on Xcode 26 beta** — Full Ghostty app cannot build locally. The `xcodebuild -downloadComponent MetalToolchain` fails. This blocks the full app build path. Mitigated by `libghostty-vt` which builds without Metal.

2. **Zero functional code changes** — All 14 fork commits are CI/docs. The fork has no owned functionality yet. This is the primary gap: the dossier requires "a specific embedding/workflow improvement."

## 5. Candidate Simpler Implementation

**libghostty-vt as standalone VT parser library.** Already builds on macOS. Next step: WASM cross-compile + thin wrapper. This avoids touching the renderer, GPU, or app bundle entirely.

## 6. Comparative Plan

| Subject | Correctness | Latency | Memory | Effort |
|---------|-------------|---------|--------|--------|
| Khostty (libghostty-vt) | TBD | TBD | TBD | TBD |
| Upstream Ghostty | Reference | Reference | Reference | N/A |
| WezTerm | TBD | TBD | TBD | TBD |
| Kitty | TBD | TBD | TBD | TBD |
| Native terminal | TBD | TBD | TBD | TBD |

Metrics to measure: VT conformance failures, render frame pacing, memory after long sessions, integration effort.

## 7. Next Bounded Task

**Build libghostty-vt as WASM module.** Validates the cross-platform embedding path. If this succeeds, the fork has its first real functional delta.

## 8. Required Permission

Proceed with WASM build and Rust FFI wrapper implementation (or defer to sponsor for direction on which delta to prioritize).

## 9. Expected Proof

1. `zig build -Demit-lib-vt -Dtarget=wasm32-freestanding` produces a valid `.wasm` file
2. The WASM module can be loaded and parse VT sequences
3. At least one VT100 conformance test passes via the embedded parser
