# JVM-Only Backend Pivot And Documentation Alignment

## Sequence: 55
## Tier: 8
## Former ID: (none)

## Summary

Align the roadmap, codebase, tooling, and project documentation to a JVM-only backend direction by removing Zig VM implementation support and code, updating developer and CI tools, and reflecting JVM-only support across unplanned stories, README content, specs, and supporting documentation.

## Current State

- The repository currently includes both JVM and Zig VM backends in implementation and documentation.
- Current unplanned stories include VM-specific work items and acceptance language.
- Specs and docs reference bytecode VM behavior, VM build/test workflows, and dual-backend assumptions.
- Build, test, and helper tooling still includes Zig VM commands and assumptions.
- Repository structure includes VM-oriented directories and integration surfaces that may be simplified under JVM-only support.

## Relationship to other stories

- Directly updates and re-scopes all current unplanned stories in `docs/kanban/unplanned/` to remove Zig VM implementation scope and align with JVM-only delivery.
- May require follow-up sequencing adjustments for stories that become obsolete, merged, or JVM-reframed.

## Goals

- Update every unplanned story so scope, acceptance criteria, tests, and doc/spec references are JVM-only.
- Remove Zig VM implementation references from roadmap intent in unplanned stories.
- Remove Zig VM code and related runtime implementation artifacts from the repository.
- Update scripts, CLI flows, build/test automation, and other tools so JVM-only workflows are first-class and Zig VM workflows are removed.
- Reorganize repository structure where needed to reflect JVM-only architecture and reduce backend-split complexity.
- Update top-level and component README files to describe JVM-only backend support.
- Update specs and docs so backend/runtime descriptions, testing guidance, and tooling references are consistent with JVM-only support.
- Ensure all written changes are declarative and do not include rationale for the pivot.

## Acceptance Criteria

- Each file in `docs/kanban/unplanned/` is reviewed and updated to remove Zig VM implementation scope and references.
- Any unplanned story that is no longer relevant under JVM-only support is clearly re-scoped, merged, or replaced with explicit JVM-only intent.
- Zig VM implementation code is removed from active repository code paths.
- Tooling and automation (local scripts, project commands, and CI-oriented workflows) no longer require or invoke Zig VM build/test/runtime paths.
- If repository reorganization is required, the resulting structure is consistent with JVM-only delivery and all affected references/import paths/docs are updated.
- README files across the repository that mention backend support are updated to JVM-only language.
- Specs under `docs/specs/` are updated so backend/runtime/tooling descriptions are internally consistent and JVM-only.
- Other project documentation that references backend support is updated to JVM-only language.
- Documentation text does not include historical rationale or justification for the pivot; it reflects the new state directly.

## Spec References

- `docs/specs/01-language.md`
- `docs/specs/03-bytecode-format.md`
- `docs/specs/04-bytecode-isa.md`
- `docs/specs/05-runtime-model.md`
- `docs/specs/08-tests.md`
- `docs/specs/09-tools.md`
- `docs/specs/10-compile-diagnostics.md`

## Risks / Notes

- This story is intentionally broad and documentation-heavy; move to planned only after identifying exact file-level impact and concrete edit tasks.
- Story updates should preserve numbering and link integrity while re-scoping content.
- Any VM-related technical content that remains because it is JVM-relevant should be rewritten to JVM terminology and workflows.
- Code removal and potential repository reorganization should be sequenced to avoid broken scripts, stale references, and orphaned tests during transition.

## Impact analysis

- Compiler and runtime interfaces:
	- `compiler/` modules and tests that currently target or mention Zig VM bytecode execution paths must be audited and either removed or rewritten for JVM-only runtime assumptions.
	- `runtime/jvm/` becomes the only supported backend runtime path; references should be made explicit in compiler docs and tooling docs.
- VM implementation surface:
	- `vm/` source, tests, and build files are candidates for removal from active workflows.
	- Any build artifacts or checked-in generated VM assets referenced by scripts/docs must be either removed or replaced with JVM equivalents.
- Scripts and CLI:
	- `scripts/` commands (`test-all`, backend build helpers, smoke scripts) and root `kestrel` wrapper must stop invoking Zig build/test commands.
	- CI-oriented command documentation in markdown files must align with JVM-only commands.
- Story and planning docs:
	- All files in `docs/kanban/unplanned/` must be reviewed for VM-specific scope and acceptance language and rewritten to JVM-only intent.
	- Sequence numbers must remain unchanged while story text is re-scoped.
- Risk and rollout:
	- High cross-cutting risk due to broad doc/tooling/code touch points; execute in ordered passes (stories/docs -> scripts -> code removal -> verification).
	- Roll-forward strategy is preferred; avoid partial deletion before replacing references.

## Tasks

- [ ] Audit all files in `docs/kanban/unplanned/` and list required JVM-only scope edits per story.
- [ ] Update each unplanned story to remove Zig VM implementation scope and align acceptance/tests/spec references to JVM-only delivery.
- [ ] Identify and remove or neutralize Zig VM code paths from active repository workflows (`vm/`, script entry points, references).
- [ ] Update CLI and scripts to remove Zig VM build/test/run paths and preserve working JVM-only developer workflows.
- [ ] Update repository structure references (README, docs, script comments, helper docs) to match the post-pivot layout.
- [ ] Update specs listed in this story so runtime/backend/tooling language is internally consistent and JVM-only.
- [ ] Run required verification suites for compiler, Kestrel tests, and JVM runtime workflows; confirm no Zig VM dependency remains in required paths.
- [ ] Capture any deferred follow-up work as new unplanned stories with explicit sequencing.

## Tests to add

- `tests/unit/*.test.ks`: add/update tests where language/tooling behavior changes due to JVM-only execution assumptions.
- `compiler/test/` Vitest suites: add regression coverage for compiler/runtime integration paths that previously referenced Zig VM outputs.
- `tests/e2e/scenarios/`: add or adjust scenarios that asserted VM-specific behavior so they assert JVM-only behavior.
- `tests/conformance/runtime/`: update corpus expectations if backend-specific outputs or diagnostics changed.
- Script-level verification:
	- `./scripts/kestrel test`
	- `cd compiler && npm test`
	- `./scripts/test-all.sh`
	- Ensure no required verification step includes `cd vm && zig build test` after pivot completion.

## Documentation and specs to update

- `README.md`
- `AGENTS.md`
- `docs/guide.md`
- `docs/IMPLEMENTATION_PLAN.md`
- `docs/Kestrel_v1_Language_Specification.md`
- `docs/specs/01-language.md`
- `docs/specs/03-bytecode-format.md`
- `docs/specs/04-bytecode-isa.md`
- `docs/specs/05-runtime-model.md`
- `docs/specs/08-tests.md`
- `docs/specs/09-tools.md`
- `docs/specs/10-compile-diagnostics.md`

## Notes

- Execute this story in deliberate stages to avoid repository breakage: roadmap/doc re-scope first, workflow/tooling updates second, backend code-path removal third, verification last.
- If story re-scoping reveals obsolete or overlapping unplanned items, preserve the sequence IDs and rewrite scope in place; only merge/supersede with explicit cross-links.