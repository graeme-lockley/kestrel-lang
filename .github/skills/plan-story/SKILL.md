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

Canonical rules: **[docs/kanban/README.md](docs/kanban/README.md)**. This skill produces the `planned/` content for a story in `unplanned/`. See **kanban-story-migrate §A** for the formal gate.

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

Add this section to the story. One row per component that changes:

```markdown
## Impact analysis

| Area | Change |
|------|--------|
| ... | ... |
```

- Cover: compiler, JVM codegen, JVM runtime, stdlib, tests, scripts.
- State the nature of the change (new function, modified type, new test file, spec update).
- Note compatibility and rollback risk where relevant.
- Reference or incorporate bullet risks from **Risks / Notes** — do not silently drop them.

## 5. Write the tasks

Tasks must be concrete enough to execute without further research.

```markdown
## Tasks

- [ ] <implementation change — file and function level>
- [ ] ...
- [ ] Run `cd compiler && npm run build && npm test`
- [ ] Run `./scripts/kestrel test`
```

Rules:
- One `- [ ]` per discrete file-level or function-level change.
- Preserve pipeline order: parser → typecheck → codegen → JVM codegen → JVM runtime → stdlib → CLI.
- Add `cd runtime/jvm && bash build.sh` and `./scripts/run-e2e.sh` when the story modifies JVM runtime code or user-visible behaviour.

## 6. Write the tests to add

```markdown
## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest unit | `compiler/test/unit/…` | … |
| Vitest integration | `compiler/test/integration/…` | … |
| Kestrel harness | `tests/unit/<feature>.test.ks` | … |
| Conformance typecheck | `tests/conformance/typecheck/…` | … |
| Conformance runtime | `tests/conformance/runtime/…` | … |
| E2E positive | `tests/e2e/scenarios/positive/…` | … |
| E2E negative | `tests/e2e/scenarios/negative/…` | … |
```

Include only relevant layers. For each entry state *what* the test asserts:
- Happy-path acceptance criteria.
- Boundary and edge conditions (empty, zero, max, recursive, cross-module).
- Regression guards for each behaviour the feature introduces.

## 7. Write documentation and specs to update

```markdown
## Documentation and specs to update

- [ ] `docs/specs/<file>.md` — <what section and what to change>
- [ ] ...
```

Every file listed in **Spec References** needs an entry. Add other docs (AGENTS.md, guide.md) only if they already document the affected feature.

## 8. Move the story to planned/

Move `docs/kanban/unplanned/S##-##-slug.md` → `docs/kanban/planned/S##-##-slug.md` (same filename, different folder). Do not change any other content.

The story is now ready for **build-story** to implement.

## Related

- Create an epic: skill **epic-create**
- Create a story: skill **story-create**
- Phase gates: skill **kanban-story-migrate** (§A for the unplanned → planned gate)
- Implement: skill **build-story**
