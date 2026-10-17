# phenoreg-linker — REPORT

**Session:** 20261017-phenoreg-linker
**Date:** 2026-10-17T07:14 PDT
**Operator:** local-board
**Scope:** Link KooshaPari/Khostty PRs (khostty audit arc) to the 3 phenoreg
(Paperclip @ localhost:3180) phase issues for the Khostty project.

## API discovered

Paperclip exposes a Linear-style REST surface (idempotent; no auth required for
local-board writes):

| Action | Endpoint |
|---|---|
| List issues | `GET /api/companies/{companyId}/issues` |
| Read issue  | `GET /api/issues/{issueUuid}` (full UUID only) |
| List comments | `GET /api/issues/{issueUuid}/comments` |
| Add comment  | `POST /api/issues/{issueUuid}/comments` with `{"body":"…"}` |
| Delete comment | `DELETE /api/issues/{issueUuid}/comments/{commentId}` (soft-delete) |

No `/links` endpoint exists. Comments are the linking mechanism. Issue IDs in
this report use the full UUID (the short 8-char hex prefix resolves only
through `/api/issues/{id}` and is rejected on comment endpoints).

API latency is high: POST/DELETE on `/comments` takes 25–85s end-to-end. The
180s `--max-time` budget is too tight; 600s is the working budget.

## Issue → PR mapping (final)

| Phenoreg issue (full UUID) | Title (PHE-N) | PR | Linked comment UUID |
|---|---|---|---|
| `b1230628-c138-4435-a0d6-c2cb32a1915a` | Phase A — Post-SUNSET polish batch (PHE-17) | #35 `khostty-registry-checklist-20261017` | `0f39d41c-9137-41b0-a501-ad346aa7c6c4` |
| `14040d6d-40f4-41c8-bbba-7287ad32b482` | Phase B — Wire IPC server into GTK runtime (G4 finish) (PHE-18) | #36 `khostty-phase-b-gtk-spec-20261017` | `179d5ef2-3ef5-4ac2-a20d-82060b5e3024` |
| `372bb3d6-2c07-4fe8-8936-42b8ef4e6f01` | Phase C — Phase 1 mux shell design (2d) (PHE-19) | #37 `khostty-q1-decision-matrix-20261017` | `3642e7f4-1d7c-4bba-a2fd-d7cc81981140` |
| `372bb3d6-2c07-4fe8-8936-42b8ef4e6f01` | Phase C — Phase 1 mux shell design (2d) (PHE-19) | #38 `khostty-phase1-risk-doc-20261017` | `9eaab5c6-53c1-49bf-8a36-66db795b64b7` |

PRs #34 (`docs/intent-evaluation-20261016`) and #30 (`lanes/d-ci-installer-20261016`)
were in the open-PR list but do not map cleanly to any of the 3 phase issues;
left unlinked (per "link to closest phase issue" rule, neither is closest).

## Comment text used

All comments share the prefix `[phenoreg-linker-2026-10-17]` for grep-ability.

**PR #35 → Phase A:** `[phenoreg-linker-2026-10-17] Linked
KooshaPari/Khostty#35 (`khostty-registry-checklist-20261017`): 4-section
operator registry checklist (O1-O4) covering operator-fit inputs that close
out tasks A1-A7 in this phase. URL: https://github.com/KooshaPari/Khostty/pull/35`

**PR #36 → Phase B:** `[phenoreg-linker-2026-10-17] Linked
KooshaPari/Khostty#36 (`khostty-phase-b-gtk-spec-20261017`): GTK-runtime
IPC wire-up specification; it is the design input that tasks B1 (Server.bind
from GTK), B2 (pane.write mailbox hop), B4 (cross-thread surface API), and
B5 (acceptance test) are implementation against. URL:
https://github.com/KooshaPari/Khostty/pull/36`

**PR #37 → Phase C:** `[phenoreg-linker-2026-10-17] Linked
KooshaPari/Khostty#37 (`khostty-q1-decision-matrix-20261017`): Q1 decision
matrix for the Phase 1 windowed runtime; it gates the Q1(a) operator
decision and the Q1(b) embedded-on-macOS choice that drives the C1-C5 design
tasks in this phase. URL: https://github.com/KooshaPari/Khostty/pull/37`

**PR #38 → Phase C:** `[phenoreg-linker-2026-10-17] Linked
KooshaPari/Khostty#38 (`khostty-phase1-risk-doc-20261017`): Phase 1
mux-shell risk analysis that complements C4 (mux architecture doc) and
tightens the Lock-Ordering decision called out by the mux audit §5 as the
single highest-risk design point. URL: https://github.com/KooshaPari/Khostty/pull/38`

## Cleanup notes

First-round POSTs with `--max-time 180` "failed" (exit 28) but the server
actually accepted them — the requests were already past the API handler.
Re-POSTs succeeded with the same body, leaving 4 duplicate comments. The
older duplicates (`abe2bdbb…` Phase A, `22049e33…` Phase B, `5b909a20…` PR37,
`cef9701e…` PR38) were soft-deleted via `DELETE /api/issues/{uuid}/comments/{id}`
(HTTP 200 each). Final state: 4 link comments, 1 per (issue, PR) pair. The
self-test probe comment (`2f325cc3-…`) was also soft-deleted before the real
posts were created.

## Stop condition met

All 3 issues carry at least one linked PR (Phase C carries two). Reporting up
with full PR URLs + comment text:

- `b1230628` ↔ https://github.com/KooshaPari/Khostty/pull/35
- `14040d6d` ↔ https://github.com/KooshaPari/Khostty/pull/36
- `372bb3d6` ↔ https://github.com/KooshaPari/Khostty/pull/37, https://github.com/KooshaPari/Khostty/pull/38
