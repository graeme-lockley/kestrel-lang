---
name: build-story
version: 1.0.0
description: >-
  Implements a Kestrel kanban story end-to-end: locates the story, runs
  plan-story first if it is still in unplanned/, then confirms the impact
  analysis, executes all tasks, records decisions as build notes, verifies
  tests pass, and moves the story to done/.
inputs:
  - story_id: "story identifier (S##-##)"
outputs:
  - "edits source, tests, and specs to satisfy the planned tasks"
  - "appends Build notes entries"
  - "moves the story to docs/kanban/done/"
  - "creates one or more conventional-commit commits"
allowed-tools: [read_file, list_dir, file_search, grep_search, semantic_search, create_file, replace_string_in_file, multi_replace_string_in_file, run_in_terminal, get_errors, manage_todo_list]
forbids: ["git push", "git push --force", "git reset --hard", "git commit --amend", "git rebase", "rm -rf"]
---

# Kestrel kanban — build a story

Canonical rules: **[docs/kanban/README.md](docs/kanban/README.md)**. This skill drives a story from any phase to **`done/`**.

Gate criteria for `planned/ → doing/ → done/` are defined inline in §B below. When anything goes wrong at any step, follow [`_shared/failure-protocol.md`](../_shared/failure-protocol.md). Cross-cutting conventions (date sourcing, no batching, push policy) are in [`_shared/conventions.md`](../_shared/conventions.md).

## Inputs

- **story_id** — the story identifier (e.g. `S03-04`).

## Outputs / Side effects

- Edits source, tests, and specs to satisfy the planned tasks.
- Appends entries to the story's `## Build notes` section.
- Moves the story file from `planned/` (via `doing/`) to `done/`.
- Creates one or more conventional-commit commits (see [`_templates/commit-messages.md`](../_templates/commit-messages.md)).
- **Does not push** to any remote.

## 0. Locate the story and determine phase

Find the story file in `docs/kanban/`:

| Story is in | Action |
|-------------|--------|
| `future/` | Not roadmap-ready — use **story-create** to promote to `unplanned/` first |
| `unplanned/` | Run **plan-story** first, then continue from step 1 |
| `planned/` | Continue from step 1 |
| `doing/` | Continue from step 2 (already in progress) |
| `done/` | Nothing to do |

Open the owning epic file (`docs/kanban/epics/unplanned/EXX-*.md`) and note any cross-story dependencies.

## 1. Confirm the story is ready

Read the story file in full. Verify:

- **Impact analysis** covers all relevant areas (compiler, JVM, stdlib, scripts, tests).
- **Tasks** are concrete and file-level (not vague).
- **Tests to add** is populated.
- **Documentation and specs to update** is populated.

If any section is thin, run **plan-story** to fill the gaps before proceeding.

## 2. Move to doing/

Move `docs/kanban/planned/S##-##-slug.md` → `docs/kanban/doing/S##-##-slug.md`.

Add a **Build notes** section at the end of the story using the shape in [`_templates/build-notes-entry.md`](../_templates/build-notes-entry.md). The first entry is always `Started implementation.`

## 3. Confirm impact against the codebase

Before writing code, open the files listed in the impact analysis and verify they are shaped as expected. If the codebase has diverged from the plan:

- Update the **Tasks** list to reflect reality.
- Append a **Build note** recording what changed and why.
- Add new `- [ ]` tasks for any scope that emerged; complete them before closing.

## 4. Implement in pipeline order

Work through changes in this order when the story spans multiple layers:

| Area | Path |
|------|------|
| Parser / AST | `compiler/src/parser/`, `compiler/src/ast/` |
| Typecheck | `compiler/src/typecheck/check.ts` |
| Codegen (bytecode) | `compiler/src/codegen/codegen.ts` |
| Codegen (JVM) | `compiler/src/jvm-codegen/codegen.ts` |
| JVM runtime | `runtime/jvm/src/` |
| Stdlib | `stdlib/kestrel/` |
| CLI / scripts | `scripts/` |

**As you go:**

- **Tick `- [x]`** immediately when a task is complete — do not batch.
- **Append a Build note** for every non-obvious decision, trade-off, or approach that did not work.
- **Add `- [ ]` tasks** if new scope is discovered; complete them before closing.
- Keep changes minimal: match project style, no drive-by refactors, `.js` import suffixes in TypeScript.

### Code quality

- New logic lives next to analogous cases (match arms, literal types, etc.).
- Shared behaviour is extracted only where duplication is real — not as speculative abstraction.
- Explicit return types on exported functions; no `any`.
- If JVM codegen changed, check the bytecode codegen for the same patterns (and vice versa) — keep backends in parity.
- Diagnostics reference the failing construct with a code consistent with `compiler/src/diagnostics/`.

## 5. Add tests

Add every test listed under **Tests to add**. Use project patterns:

- **Vitest** (`compiler/test/unit/` or `integration/`): `describe`/`it`/`expect`; `.js` import suffixes in TS.
- **Kestrel harness** (`tests/unit/*.test.ks`): `test:expect` / `test:assert`.
- **Conformance** (`tests/conformance/typecheck/` or `runtime/`): `.ks` files with `// EXPECT:` for invalid cases; `// <output>` comment-based goldens for runtime.
- **E2E** (`tests/e2e/scenarios/positive/` or `negative/`): positive cases need `.expected`; negative cases must exit non-zero.

Tests must cover: happy-path acceptance criteria, boundary / edge conditions, and regression guards for each behaviour the feature introduces. If a test is also a kestrel library test, place it alongside the library file.

## 6. Update specs and docs

For every item in **Documentation and specs to update**:

- Edit the `docs/specs/` file.
- Tick the checkbox in the story.
- Append a **Build note** if the spec change required a non-trivial decision.

Specs are the source of truth; keep them accurate.

## 7. Verify

Run the suites listed in [`_shared/verify.md`](../_shared/verify.md) for the triggers this story hit. Fix all failures before closing — do not advance the story phase on a red suite.

## 8. Close the story

1. Every **Task** is `[x]` (including any added during implementation).
2. Every **Documentation and specs to update** item is ticked.
3. **Build notes** capture material decisions.
4. Move `docs/kanban/doing/S##-##-slug.md` → `docs/kanban/done/S##-##-slug.md`.
5. Update the owning epic file in `docs/kanban/epics/unplanned/`:
   - Mark this story complete in the story list.
   - If all member stories are now in `done/`, report back to the user that all epic stories are complete.

## §B. Gate criteria — `planned/ → doing/ → done/`

A story may move from `planned/` to `doing/` only when:

- File lives in `docs/kanban/planned/` with the correct `S##-##-slug.md` name.
- `## Impact analysis`, `## Tasks`, `## Tests to add`, and `## Documentation and specs to update` sections all exist and are non-trivial.
- The owning `## Epic` link resolves.

A story may move from `doing/` to `done/` only when:

- Every `## Tasks` checkbox is `- [x]`.
- Every `## Documentation and specs to update` checkbox is `- [x]`.
- A `## Build notes` section exists with at least one dated entry.
- All required test suites listed in the verification matrix pass.
- All `## Acceptance Criteria` are observably satisfied.

## Examples

For a model completed story with substantive build notes, see [docs/kanban/done/S16-03-kestrel-cli-core-implementation.md](../../../docs/kanban/done/S16-03-kestrel-cli-core-implementation.md). Its Build notes record real implementation discoveries (codegen quirks, missing operators, async propagation) — not boilerplate. Aim for that signal-to-noise ratio.

## Related

- Plan a story (unplanned → planned): skill **plan-story**
- Create a story: skill **story-create**
- Create an epic: skill **epic-create**
- Kanban rules: `docs/kanban/README.md`
