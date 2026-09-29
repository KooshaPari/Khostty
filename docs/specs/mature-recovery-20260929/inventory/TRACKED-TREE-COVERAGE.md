# Tracked-tree coverage — Khostty

Frozen product source: `a29aa9c6553d9f42aa68e2919116c0f6d53f329d`.

## Enumeration result

Every top-level Git tree at the frozen revision was enumerated with untruncated Git-tree responses.

- `TRACKED-TREE-A.json`: 1,283 exact blob rows across runtime/docs/wrappers/conformance/WASM/packaging/CI/bench.
- `TRACKED-TREE-B.json`: 855 exact blob rows across macOS/public API/examples/distribution/localization/vendor/support plus root files.
- **Explicit non-fuzz blob rows: 2,138.**
- Test tree separately resolved structurally: `fuzz-libghostty` = 4,014 blobs, including **4,002 corpus blobs**; Windows test subtree = 3 blobs; test root also contains 3 files.
- No top-level tree remains structurally uncovered.

The 4,002 corpus seeds are one inherited/verification source family unless a specific seed is shown to carry a distinct product obligation. They must not manufacture 4,002 requirements or completion points.

This closes tracked-tree enumeration at source-family resolution. It does not close semantic source coverage, useful Git history, predecessor/alias archaeology, user authority, external alternatives or runtime qualification.

## Initial semantic-family projection for exact A+B rows

| Family | Blob rows | Interpretation |
|---|---:|---|
| Runtime core | 639 | Mostly inherited/common runtime; ownership must be compared to merge base |
| Upstream core | 365 | INHERITED candidate; verify any modified exceptions |
| Upstream macOS runtime | 270 | INHERITED candidate; relevant to native journey but not fork differentiation |
| Build support | 233 | SUPPORT/OPERATIONS; large count is not product scope |
| Upstream examples | 133 | SUPPORTING/EXTERNAL-INTERNAL PRIOR ART |
| Polyglot wrappers | 117 | FORK CANDIDATE; high-priority ownership/consumer qualification |
| Distribution | 61 | OPERATIONS / support horizon |
| Root contract/build | 38 | Mixed normative/supporting; classify individually |
| Public API | 37 | Mostly inherited C surface; exact fork deltas required |
| Localization | 37 | Quality/support |
| Verification | 36 | Fork/inherited split; evidence quality must be assessed |
| Assets | 34 | Auxiliary unless journey-relevant |
| WASM | 33 | Candidate distribution/wrapper delta |
| CI | 30 | Evidence machinery |
| Documentation | 18 | Authority review |
| Historical | 16 | Historical by default |
| Agent IPC | 11 | Fork candidate, but native mounting incomplete |
| Windows runtime | 11 | Fork candidate; App lifecycle currently unimplemented |
| Vendored dependency | 9 | Auxiliary/supply-chain |
| Packaging | 8 | Operations |
| Agent instructions | 2 | Development machinery, not product behavior |

## Resolution order

1. Exact merge-base ownership map for `src/apprt/windows`, `src/apprt/ipc`, wrappers, conformance and WASM.
2. Actual runtime/startup/caller graph: compile reachability ≠ runtime mounting.
3. One real control journey and one embedding consumer against strongest alternatives.
4. Verification/CI evidence identity and upstream drift.
5. Distribution/support configurations.
6. Inherited runtime/core/macOS/test corpus grouped by semantic obligations rather than one-row-per-file.

Counts are navigation and falsification aids only.
