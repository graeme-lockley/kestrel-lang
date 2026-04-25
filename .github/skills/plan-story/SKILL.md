---
name: plan-story
description: >-
  Plans a Kestrel kanban story: takes a feature story from unplanned/, explores
  the codebase and specs, adds a complete implementation plan (impact analysis,
  tasks, tests to add, docs to update), and moves the story to planned/. Use
  when a story needs to move from unplanned to planned with a substantive,
  build-ready implementation plan.
---

# Kestrel kanban — plan a story

Canonical rules: **[docs/kanban/README.md](docs/kanban/README.md)**. This skill produces the `planned/` content for a story in `unplanned/`.

## §A. Gate criteria — `unplanned/ → planned/`

A story may move from `unplanned/` to `planned/` only when:

- File lives in `docs/kanban/unplanned/` with the correct `S##-##-slug.md` name.
- All required unplanned sections exist: `## Sequence`, `## Tier`, `## Epic`, `## Summary`, `## Current State`, `## Goals`, `## Acceptance Criteria`, `## Spec References`, `## Risks / Notes`.
- The owning `## Epic` link resolves.
- This skill has added `## Impact analysis`, `## Tasks`, `## Tests to add`, and `## Documentation and specs to update` (steps 4–7 below).

## 1. Read the story

Open `docs/kanban/unplanned/S##-##-slug.md`. Read every section: **Summary**, **Current State**, **Goals**, **Acceptance Criteria**, **Spec References**, **Risks / Notes**, and the **Epic** link. If a required unplanned section is thin or missing, fill it before proceeding — a weak story produces a weak plan.

## 2. Explore the codebase

Search the source for every area the story touches. Use the table below as a starting guide:

| Area | Key paths |
|------|-----------|
| Parser | `compiler/src/parser/` |
| Typecheck | `compiler/src/typecheck/check.ts` |
| Codegen (bytecode) | `compiler/src/codegen/codegen.ts` |
| Codegen (JVM) | `compiler/src/jvm-codegen/codegen.ts` |
| AST nodes | `compiler/src/ast/` |
| Stdlib | `stdlib/kestrel/` |
| JVM runtime | `runtime/jvm/src/` |
| CLI / scripts | `scripts/` |

For each area: identify the files and functions that implement the current behaviour, note any intrinsics or opcodes involved, and note what existing tests already cover.

## 3. Read relevant specs

Open every file listed in **Spec References** and read the affected sections. Understand the current documented behaviour before authoring tasks that change it.

## 4. Write the impact analysis

Add this section to the story using the shape in [`_templates/story-planned-additions.md`](../_templates/story-planned-additions.md) § 1.

- Cover: compiler, JVM codegen, JVM runtime, stdlib, tests, scripts.
- State the nature of the change (new function, modified type, new test file, spec update).
- Note compatibility and rollback risk where relevant.
- Reference or incorporate bullet risks from **Risks / Notes** — do not silently drop them.

## 5. Write the tasks

Add this section using the shape in [`_templates/story-planned-additions.md`](../_templates/story-planned-additions.md) § 2. Tasks must be concrete enough to execute without further research.

Rules:
- One `- [ ]` per discrete file-level or function-level change.
- Preserve pipeline order: parser → typecheck → codegen → JVM codegen → JVM runtime → stdlib → CLI.
- Add the verification commands as their own tasks per the trigger matrix in [`_shared/verify.md`](../_shared/verify.md).

## 6. Write the tests to add

Add this section using the shape in [`_templates/story-planned-additions.md`](../_templates/story-planned-additions.md) § 3. Include only relevant layers. For each entry state *what* the test asserts:
- Happy-path acceptance criteria.
- Boundary and edge conditions (empty, zero, max, recursive, cross-module).
- Regression guards for each behaviour the feature introduces.

## 7. Write documentation and specs to update

Add this section using the shape in [`_templates/story-planned-additions.md`](../_templates/story-planned-additions.md) § 4. Every file listed in **Spec References** needs an entry. Add other docs (AGENTS.md, guide.md) only if they already document the affected feature.

## 8. Move the story to planned/

Move `docs/kanban/unplanned/S##-##-slug.md` → `docs/kanban/planned/S##-##-slug.md` (same filename, different folder). Do not change any other content.

The story is now ready for **build-story** to implement.

## Related

- Create an epic: skill **epic-create**
- Create a story: skill **story-create**
- Implement: skill **build-story**
- Kanban rules: `docs/kanban/README.md`
