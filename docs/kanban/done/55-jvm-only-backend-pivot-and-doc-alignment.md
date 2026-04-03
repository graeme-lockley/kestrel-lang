# JVM-Only Backend Pivot: Roadmap and Documentation Alignment

## Sequence: 55
## Tier: 8
## Former ID: (none)

## Summary

Update all kanban roadmap stories and project-level documentation to reflect JVM-only backend direction. This story covers the planning/documentation layer only — script/tooling changes (56), Zig VM code removal (57), and spec rewrites (58) are handled by dedicated follow-up stories.

## Current State

- Unplanned stories (59–71) contain Zig VM scope, dual-backend acceptance language, and VM-specific references.
- Project docs (`README.md`, `AGENTS.md`, `docs/guide.md`, `docs/IMPLEMENTATION_PLAN.md`, `docs/Kestrel_v1_Language_Specification.md`) reference both Zig VM and JVM backends.

## Relationship to other stories

- **56** (Scripts & tooling JVM-only update) depends on this story landing first so doc expectations are aligned.
- **57** (Zig VM code removal) should follow 56.
- **58** (Specs alignment) can run in parallel with or after 57.
- Directly re-scopes all current unplanned stories (59–71).

## Goals

- Every unplanned story reflects JVM-only scope, acceptance criteria, tests, and doc/spec references.
- VM-specific stories (65–67: float, fixtures, spread) are re-scoped or marked for JVM-only verification/closure.
- Project-level documentation describes JVM-only backend support.
- No code or script changes in this story — those belong to 56–58.

## Acceptance Criteria

- [x] Each file in `docs/kanban/unplanned/` (59–71) reviewed and updated to remove Zig VM implementation scope.
- [x] VM-specific stories (65, 66, 67) re-scoped to JVM-only verification or marked for closure with rationale.
- [x] `README.md` updated to JVM-only backend language.
- [x] `AGENTS.md` updated to remove Zig VM build/test commands and references (noting that script/code changes follow in 56–57).
- [x] `docs/guide.md` updated to JVM-only language.
- [x] `docs/IMPLEMENTATION_PLAN.md` updated to JVM-only language.
- [x] `docs/Kestrel_v1_Language_Specification.md` updated to JVM-only language where backend is mentioned.
- [x] No documentation text includes historical rationale for the pivot; it reflects the new state directly.

## Spec References

- Specs are **out of scope** for this story — handled by **58**.

## Risks / Notes

- Story updates should preserve sequence numbering and link integrity while re-scoping content.
- VM-related technical content that remains because it is JVM-relevant should be rewritten to JVM terminology.
- Stories 65 (VM float), 66 (VM test fixtures), and 67 (VM spread) may become obsolete under JVM-only; re-scope or note closure intent rather than deleting the files.

## Impact analysis

| Area | Files / subsystems | Change | Risk |
|------|-------------------|--------|------|
| **Unplanned stories** | `docs/kanban/unplanned/59–71` (13 files) | Remove Zig VM scope; rewrite dual-backend acceptance to JVM-only | Low |
| **README** | `README.md` | Remove Zig/VM backend description | Low |
| **AGENTS.md** | `AGENTS.md` | Remove `cd vm && zig build test` and Zig references from commands/guidelines | Low |
| **Guide** | `docs/guide.md` | JVM-only backend language | Low |
| **Implementation plan** | `docs/IMPLEMENTATION_PLAN.md` | JVM-only backend language | Low |
| **Language spec** | `docs/Kestrel_v1_Language_Specification.md` | JVM-only where backend mentioned | Low |

## Tasks

- [x] Audit all files in `docs/kanban/unplanned/` and list required JVM-only scope edits per story.
- [x] Update each unplanned story (59–71) to remove Zig VM implementation scope and align acceptance/tests/spec references to JVM-only delivery.
- [x] Re-scope or annotate VM-specific stories (65, 66, 67) for JVM-only verification or closure.
- [x] Update `README.md` to JVM-only backend language.
- [x] Update `AGENTS.md` to remove Zig VM build/test commands and references.
- [x] Update `docs/guide.md` to JVM-only language.
- [x] Update `docs/IMPLEMENTATION_PLAN.md` to JVM-only language.
- [x] Update `docs/Kestrel_v1_Language_Specification.md` to JVM-only language.

## Tests to add

- None — this story is documentation-only.

## Documentation and specs to update

- `README.md`
- `AGENTS.md`
- `docs/guide.md`
- `docs/IMPLEMENTATION_PLAN.md`
- `docs/Kestrel_v1_Language_Specification.md`
- `docs/kanban/unplanned/59–71` (all 13 files)

## Notes

- Specs (`docs/specs/`) are deliberately excluded — story **58** handles those as a focused pass.
- Script and tooling changes are excluded — story **56** handles those.
- Code removal is excluded — story **57** handles that.

## Build notes

- 2026-04-03: All 13 unplanned stories (59–71) updated. Stories 65, 66, 67 re-scoped from Zig VM to JVM-only verification. Stories 59, 60, 68, 69 had significant Zig VM implementation scope removed. Stories 61, 64, 70, 71 required minor wording fixes. Stories 62 and 63 had no VM references and required no changes. `docs/IMPLEMENTATION_PLAN.md` already retired; no additional changes needed beyond confirming no Zig references.
