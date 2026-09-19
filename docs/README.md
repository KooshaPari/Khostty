# Khostty Documentation

Reference documentation for Khostty, the Phenotype fork of
[Ghostty](https://github.com/ghostty-org/ghostty).

This directory holds **canonical** documentation: stable, cross-linked, and
maintained as living documents. Dated evidence, assessments, and session work live
in [`docs/sessions/`](sessions/), not here.

For a project overview and quickstart, see the [root README](../README.md).

---

## Documents

| Document | Read it for |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Layer stack (AppRT, terminal core, C ABI, polyglot FFI, IPC, CLI), Windows scaffold, fork surface discipline |
| [API.md](API.md) | The C ABI, Rust crate, Go module, WASM/JS package, upstream IPC, and CLI reference |
| [AGENT.md](AGENT.md) | Driving Khostty from an agent: what works today, recipes, and the v1 IPC status |
| [PLATFORMS.md](PLATFORMS.md) | macOS / Linux / Windows / WASM support matrix with verified vs unverified separated |
| [BUILD.md](BUILD.md) | Building from source, per-platform notes, troubleshooting, and current build status |
| [INSTALL.md](INSTALL.md) | Installing each built artifact, per-platform verification steps, and a dated VERIFIED / NOT BUILT / BLOCKED status table |
| [TESTING.md](TESTING.md) | Conformance suite mechanics, every test suite, the WBS gate structure, dated results |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Fork vs upstream contribution paths, definition of done, style, ledger commits, real CI coverage |
| [FORK.md](FORK.md) | What this fork adds over upstream, and what the evidence does not yet support |
| [SECURITY.md](SECURITY.md) | Trust boundaries, IPC authorization, memory-safety approach, undefended surfaces |
| [GLOSSARY.md](GLOSSARY.md) | VT, AppRT, surface, pane, snapshot, gate, ledger |
| [RELEASE.md](RELEASE.md) | The version scheme, how the version is derived (build.zig `lib_version`), what `0.x` means, the cut-a-release commands, and the artifact checksum manifest |
| [HANDOFF.md](HANDOFF.md) | Picking up each artifact as a consumer: macOS zip, Linux `.deb`, WASM npm package, Rust/Go/Python FFI — with verified vs unverified per artifact |
| [changelog/0.1.0.md](changelog/0.1.0.md) | Release notes for 0.1.0: the four fork deltas, gate evidence, and the known issues |

Related reference material elsewhere in the repository:

| Location | Contents |
|---|---|
| [`src/apprt/ipc/protocol.md`](../src/apprt/ipc/protocol.md) | Normative v1 agent IPC protocol spec |
| [`wasm/README.md`](../wasm/README.md) | WASM package usage, build internals, correctness guarantees |
| [`conformance/README.md`](../conformance/README.md) | Conformance corpus, methodology, and coverage gaps |
| [`bench/README.md`](../bench/README.md) | Benchmark harness, measurement discipline, and load caveats |
| [`test/fuzz-libghostty/README.md`](../test/fuzz-libghostty/README.md) | AFL++ fuzz targets |
| [`example/README.md`](../example/README.md) | 35 upstream examples in C, Zig, C++, Swift, Python, and JS |
| `HACKING.md`, `PACKAGING.md` (root) | Upstream deep-dive and packaging guides |
| `AI_POLICY.md`, `AGENTS.md` (root) | Upstream AI usage and agent policy |

---

## Status at a glance

Observed **2026-09-17**. The tree is under active concurrent edit; see the dated
notes inside each document, and `git log` for live truth.

Status vocabulary: **DONE** (merged, built, observed passing) · **IN PROGRESS**
(code exists, acceptance criteria unmet) · **SCAFFOLD** (interfaces exist, every
operation returns `error.Unimplemented`) · **NOT STARTED** · **UNKNOWN**.

| Gate | Scope | Status |
|---|---|---|
| G0 | Fork hygiene | DONE |
| G1 | Native build validation | DONE |
| G2 | Conformance evidence | **DONE — 84/84, verified 2026-09-17** |
| G3 | Windows application runtime | DONE — cross-build + 25/25 host-side apprt tests; **never executed on Windows** |
| G4 | Agent/IPC surface | DONE — protocol complete and tested; **not wired into the running app** |
| G5 | Polyglot FFI — Rust | DONE — 199/199 tests |
| G6 | Polyglot FFI — Go + Python | DONE — 207 tests (Go not reproducible on this host: SDK/clang link failure) |
| G7 | WASM cross-compilation | DONE — 54/54 tests, artifact verified |
| G8 | Improvements + benchmarks | DONE — paired runs captured; no absolute performance claim |
| G9 | Documentation + packaging | DONE — 15/15, with the `.deb` and `.app` caveats in [changelog/0.1.0.md](changelog/0.1.0.md) |
| G10 | Release artifacts | IN PROGRESS — non-publishing items done; 10.5/10.6/10.8 blocked on authorization |

### Two things to know before you build on Khostty

1. **The source tree builds.** `zig build -Demit-lib-vt` exits 0, re-verified
   2026-09-19, so the relative-import failure in `src/apprt/ipc/mod.zig` recorded on
   2026-09-17 (commit `e1277bea2`) is no longer reproducible. Historical diagnosis:
   [BUILD.md](BUILD.md#unable-to-load-mainzig-filenotfound--unable-to-load-quirkszig).
2. **There is no usable *absolute* benchmark comparison yet.** A harness exists at
   `bench/` and produced paired Khostty/upstream passes on 2026-09-17, but every pass
   ran at load 548-674 on a dirty tree, which the harness's own methodology says makes
   the absolute numbers unreliable. No absolute performance claim is supported. See
   [FORK.md](FORK.md#4-what-the-evidence-does-not-support).

---

## Documentation conventions

- Every status claim carries an **observation date**. A historical pass is not a
  fresh pass.
- Status labels come from the vocabulary above; a percentage needs an observed
  denominator.
- **UNKNOWN** is a valid, preferred answer over an inferred one.
- Canonical docs are living documents. Do not create `SUMMARY.md`, `STATUS.md`,
  `FINAL.md`, or `_V2` files.
- Dated measurements, run output, and gate evidence belong in
  `docs/sessions/<YYYYMMDD-name>/`.
- Every document ends with a "See also" section.

Authoritative task decomposition: [`docs/sessions/20260916-fork-assessment/02_DEEP_WBS.md`](sessions/20260916-fork-assessment/02_DEEP_WBS.md).

---

## See also

- [root README](../README.md) — project overview, status table, quickstart
- [ARCHITECTURE.md](ARCHITECTURE.md) — start here for how the system fits together
- [CONTRIBUTING.md](CONTRIBUTING.md) — start here before changing anything
- [TESTING.md](TESTING.md) — start here before claiming anything works
