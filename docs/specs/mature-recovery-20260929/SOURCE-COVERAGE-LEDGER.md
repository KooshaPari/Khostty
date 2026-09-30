# Source coverage ledger — Khostty

Baseline: Khostty `a29aa9c6553d9f42aa68e2919116c0f6d53f329d`; registry `85d7cd00cf59c379c05b740e8130a85b0d5bd31b`. Date: 2026-09-29.

**SEMANTIC DENOMINATOR OPEN; TRACKED-TREE ENUMERATION CLOSED.** Pass 6 enumerated every top-level Git tree at the frozen source with untruncated responses. `inventory/TRACKED-TREE-{A,B}.json` preserve 2,117 raw A+B rows with 62 exact-path overlaps, yielding 2,055 unique non-fuzz paths and zero object-ID conflicts; the unchanged test tree separately contains 4,014 fuzz-family blobs (4,002 corpus seeds) plus Windows/root test files. This closes structural tracked-file coverage only. Meaningful semantic-source total/resolved/fraction remain unknown; inherited corpus/file counts cannot become requirement counts.

Resolution requires all six: meaning understood; contradictions disposed; obligations extracted or explicitly non-normative; actual relevant surfaces identified; stage/journey consequences considered; verification consequences designed. A family also needs a justified finite member inventory. Split sources where authority differs; do not count mirrored documents twice. Retain negative searches as search receipts, not absence proofs.

| ID / family | Inspected extent and classification | Meaning / candidate obligation / consequence | Remaining resolution work |
|---|---|---|---|
| K-S01 Product intent and conversations | Current mission normative for process; targeted historical Khostty/phenotype-khostty/Ghostty/agent IPC/native Windows/FFI searches yielded no product-specific user-authored decision | Owned fork, embedded runtime, and desktop product are competing interpretations; do not import Pine or general ecosystem aspirations | Recover primary decision, date, actor and supersession; independent alias searches and deleted predecessor leads |
| K-S02 Identity and lineage | GitHub repository metadata; README inspected, long tail not certified complete; CURRENT IMPLEMENTATION metadata plus author assertions | Actual GitHub parent/source is ghostty-org/ghostty; README clone reference 1jehuang/khostty is not proof of ancestry | Git merge-base, rename/fork chronology, upstream delta inventory; resolve clone-reference status |
| K-S03 README / fork WBS / design sessions | README plus deep WBS read; `docs/FORK.md`, `ARCHITECTURE.md`, `PLATFORMS.md`, `API.md` sampled at frozen source; historical/supporting assertions | Fork itself decomposes conformance, Windows, IPC, wrappers; later docs contradict earlier scaffold status. DONE labels do not establish journeys | Reconcile dated docs against exact commits/current code; read remaining handoffs/security/testing/release evidence and authority |
| K-S04 Protocol | `src/apprt/ipc/protocol.md` lines 1–290; claims normative v1; supporting design, authority unverified | v1 pane.write injects display VT, explicitly not child input; AppHost outside build graph; documented focus/cwd behavior needs reconciliation | Remaining section 7; wire schema/code mismatch review; actor/outcome and versioning decisions |
| K-S05 IPC modules | Full high-priority ownership/reachability pass: 10 new agent-stack files + inherited `ipc/mod.zig`; protocol/app_host/server/pane sampled deeply | Public `apprt.ipc` is inherited three-action module relocated; new server/AppHost not in normal app startup graph; focus/search/mailbox still gaps | Finish semantic review of all 10 files, lifetime/security controls, then bounded native wiring/control experiment |
| K-S06 Upstream terminal semantics | Complete tracked-tree ownership boundary now shows large identical upstream trees; selected `src/terminal/c/` 36/36 byte-identical at merge base | Terminal core/API is inherited product substrate, not fork differentiation; parser/display state still distinct from child effects | Resolve semantic upstream compatibility obligations by family rather than file count; execute conformance/mutation evidence |
| K-S07 Native UI / runtime / PTY | Full tree ownership shows macOS tree identical to merge base; Windows 11-file runtime is fork-added; App lifecycle exact source says init/register/run Unimplemented | Native platform obligations must be configuration-specific; Windows fork delta is real but GUI lifecycle absent | Inspect remaining Windows modules/build hooks and execute native host experiment; inherited macOS/GTK qualify separately |
| K-S08 Embedding / ABI / wrappers | Exact ownership pass: public `include/` and selected terminal C API/ABI manifest identical to merge base; Rust/Go/Python wrapper trees are fork-added | Underlying C/ABI primitive is inherited; wrapper packaging/safety may still be fork value | Run one real wrapper consumer vs direct upstream integration; inspect ownership/thread/callback/package semantics |
| K-S09 Tests and independent evidence | Protocol test-count claims and fake_host role read; no suite executed | Fake-host/protocol tests cannot certify native mounting, input execution or GUI behavior | Inventory tests/fixtures/skips/expected failures, provenance and candidate identity; separate unit/contract/native acceptance |
| K-S10 CI / build / supply chain | Source commit records repair of ecosystem detection silently skipping nested Rust/Go/TS jobs | Historical false-green mechanism was repaired; current job coverage remains unverified | Inspect full workflows, expected-job matrix, skipped/empty policy, pinned tools and actual candidate run artifacts |
| K-S11 Release / install / lifecycle | README distribution and platform claims only | Artifact publication is not clean installation or restart qualification | Resolve releases/tags/artifact digests, supported configurations, signing, update/rollback/uninstall and reproducibility |
| K-S12 Security / operations / persistence | Partial server/auth protocol comments only | Token validation, socket ownership, resource bounds, stale handles and state recovery need scoped witnesses | Read auth and native transports; threat model, limits, failures, logs, persistence and telemetry; no security pass |
| K-S13 Registry | `docs/governance/atlas/products/Khostty/STATE.md` full; other atlas/mirrored files discovered | September 16 snapshot explicitly bounded; not a current assessment and not product authority | Read remaining relevant records, deduplicate mirrors, reconcile source/repo truth without overwriting history |
| K-S14 History / issues / PRs / predecessors | Merge-base top-level object comparison now 43 identical / 13 added / 6 modified / 0 removed; high-priority src ownership resolved; earlier current-upstream 207/145 topology retained | Large inherited trees proven identical; fork review narrowed; useful commit/PR intent and predecessor authority still open | Classify modified build/CI/dist and added wrappers/wasm/conformance history; recover primary product intent |
| K-S15 External standards / SOTA | Official WezTerm/Ghostty docs; Ghoztty same-family fork; Ghostling/libghostty embedding prior art; earlier kitty/cmux pass | Generic pane automation and Ghostty+agent-IPC are commodity/contested; upstream libghostty supports thin-host architecture | Pin Ghoztty source/license/health; execute identical-journey bake-off; standards/security/accessibility and ownership cost remain |
| K-S16 Other interfaces / auxiliary files | MCP/API/services not exhaustively inventoried; no absence claim | Do not infer an interface from filenames or dependency declarations | Enumerate every meaningful source family from full tree; classify auxiliary/irrelevant sources explicitly |

## Known sources, immutable paths

Product source prefix: `https://github.com/KooshaPari/Khostty/blob/a29aa9c6553d9f42aa68e2919116c0f6d53f329d/`.
Registry prefix: `https://github.com/KooshaPari/PhenoRegistry/blob/85d7cd00cf59c379c05b740e8130a85b0d5bd31b/`.
Source file blobs and findings are recorded in FINDINGS.md. Future refinements must preserve IDs or explicit supersession edges. Research freshness must be recorded separately from repository revision freshness.


## Pass 6 tracked-tree and ownership receipt

Every top-level tree is structurally covered. Exact A+B blob-family counts: runtime-core 639; upstream-core 365; upstream-macOS 270; build-support 233; upstream examples 133; polyglot wrappers 117; distribution 61; root contract/build 38; public API 37; localization 37; verification 36; assets 34; WASM 33; CI 30; documentation 18; historical 16; agent IPC 11; Windows runtime 11; vendored dependency 9; packaging 8; agent instructions 2. These categories are navigation, not weights.

Ownership comparison corrects several earlier assumptions: macOS/test/include/examples and other large trees are wholly identical to merge base; `src/terminal/c` ABI surface inspected is inherited; `src/apprt/ipc/mod.zig` is normalized-identical to baseline `src/apprt/ipc.zig`; Windows and ten adjacent agent-server files are real fork additions. See `inventory/FORK-OWNERSHIP.md`.


## Pass 6 tracked-tree and ownership receipt

Every top-level tree in the frozen Khostty source was enumerated with `truncated=false`. Exact non-fuzz row projection: runtime core 639; upstream core 365; upstream macOS runtime 270; build support 233; upstream examples 133; polyglot wrappers 117; distribution 61; root contract/build 38; public API 37; localization 37; verification 36; assets 34; WASM 33; CI 30; documentation 18; historical 16; agent IPC 11; Windows runtime 11; vendored dependency 9; packaging 8; agent instructions 2. Counts guide review only.

The test corpus is separately grouped: `fuzz-libghostty` has 4,014 blobs including 4,002 corpus seeds. It is a verification family, not 4,002 obligations.

Top-level merge-base comparison: 43 identical, 13 added, 6 modified, no removed entries. Entire large trees such as `macos/`, `test/`, `include/`, `example/`, `pkg/` and `vendor/` are byte/tree-identical at that baseline.


## Pass 6 ownership/mount reconciliation

Top-level comparison against merge base: 43 identical, 13 added, 6 modified, 0 removed. Critical ownership: 11 Windows runtime blobs added; 10 new agent-server/host files added; relocated `src/apprt/ipc/mod.zig` is semantically identical to baseline `src/apprt/ipc.zig` after import-path normalization; 36 inspected `src/terminal/c` blobs are identical. Fork-aware searches found no app lifecycle callers for AppHost/Server.bind/event hooks outside the subsystem/docs. This, plus protocol §7, establishes the agent JSON server as unmounted at frozen source.
