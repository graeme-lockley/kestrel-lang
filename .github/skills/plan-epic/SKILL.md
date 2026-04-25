---
name: plan-epic
version: 1.0.0
description: >-
  Decomposes a Kestrel kanban epic into an ordered set of feature stories.
  Reads the epic, explores the codebase and relevant specs, identifies the
  right story boundaries and implementation order, creates each story file in
  docs/kanban/unplanned/, and updates the epic's story list. Use when an epic
  exists but has no stories yet, or when an epic needs to be fully decomposed
  before planning begins.
inputs:
  - epic_id: "epic identifier (EXX)"
outputs:
  - "creates one docs/kanban/unplanned/S##-##-slug.md per story"
  - "updates the epic's ## Stories section with the ordered list"
allowed-tools: [read_file, list_dir, file_search, grep_search, semantic_search, create_file, replace_string_in_file, multi_replace_string_in_file, manage_todo_list]
forbids: ["git push", "git push --force", "git reset --hard", "rm -rf"]
---

# Kestrel kanban — plan an epic

Canonical rules: **[docs/kanban/README.md](docs/kanban/README.md)**. This skill produces a set of ordered, unplanned stories from an epic. Each resulting story is ready for **plan-story** to flesh out into a fully-planned implementation.

## Inputs

- **epic_id** — the epic identifier (e.g. `E03`).

## Outputs / Side effects

- Creates one `docs/kanban/unplanned/S##-##-slug.md` per decomposed story, using [`_templates/story-unplanned.md`](../_templates/story-unplanned.md).
- Updates the epic's `## Stories` section with the ordered list.
- No commits. The author commits.

## 1. Read the epic

Open `docs/kanban/epics/unplanned/EXX-slug.md`. Read every section: **Summary**, **Implementation Approach** (if present), **Dependencies**, and **Epic Completion Criteria**. Identify:

- The scope boundary — what this epic must deliver by the time it is done.
- Any stated ordering or architectural constraints.
- Dependencies on other epics or stories that bound what can be done first.

## 2. Explore the codebase and specs

For each area the epic touches, find the current state:

| Area | Key paths |
|------|-----------|
| Parser | `compiler/src/parser/` |
| Typecheck | `compiler/src/typecheck/check.ts` |
| Codegen (JVM) | `compiler/src/jvm-codegen/codegen.ts` |
| AST | `compiler/src/ast/` |
| Stdlib | `stdlib/kestrel/` |
| JVM runtime | `runtime/jvm/src/` |
| CLI / scripts | `scripts/` |
| Specs | `docs/specs/` |

Note: existing implementations, gaps vs. the epic's goals, and which pieces are independent vs. sequentially blocked.

## 3. Identify story boundaries

Decompose the epic into the smallest stories that can each be built, tested, and reviewed independently. Good story boundaries:

- One coherent user-observable or pipeline change per story.
- Each story has a clear **done state** — something testable and verifiable.
- Stories that depend on others come later in the list; independent stories can be parallel.
- Prefer more smaller stories over fewer larger ones — a story should be completable in one focused session.

## 4. Determine implementation order

Order the stories so that:

- Foundational changes (types, AST nodes, runtime classes) come first.
- Dependent features come after their dependencies.
- Independent stories are grouped and noted as "can be done in any order".

## 5. Choose story ids and assign tiers

- Find the next free story index within this epic across `docs/kanban/unplanned/` and `docs/kanban/done/`.
- Assign a **Tier** from the tier table in `docs/kanban/README.md` (or "Optional") consistent with the epic's own tier.
- Filenames: `S<epic-id>-<index>-slug.md`.

## 6. Create each story file

For each story, create `docs/kanban/unplanned/S##-##-slug.md` using the canonical shape in [`_templates/story-unplanned.md`](../_templates/story-unplanned.md).

Required sections (load-bearing — do not rename):

- `# <Title>`, `## Sequence: S##-##`, `## Tier:`, `## Former ID: (none)`
- `## Epic` (with `Companion stories: <list sibling S##-## ids>`)
- `## Summary`, `## Current State`, `## Relationship to other stories`, `## Goals`
- `## Acceptance Criteria`, `## Spec References`, `## Risks / Notes`

Write concrete, accurate content for every section based on what you found in steps 2–4. **Do not** add Tasks, Impact analysis, or Tests to add — those go in `planned/` via **plan-story** (see [`_templates/story-planned-additions.md`](../_templates/story-planned-additions.md)).

## 7. Update the epic file

Replace the `## Stories` section with the ordered list:

```markdown
## Stories (ordered — implement sequentially)

1. [S##-##-slug.md](../../unplanned/S##-##-slug.md) — <one-line description>
2. ...
```

Include a note after the list if any stories are independent and can be done in parallel.

## Examples

For a model decomposed epic, see [docs/kanban/epics/done/E14-self-hosting-compiler.md](../../../docs/kanban/epics/done/E14-self-hosting-compiler.md). It demonstrates good story boundaries (14 stories), explicit parallelism notes, and a Key-design-decisions section motivating the ordering.

## Related

- Create the epic first: skill **epic-create**
- Add a single story: skill **story-create**
- Plan an individual story (unplanned → planned): skill **plan-story**
- Build a story (planned → done): skill **build-story**
- Kanban rules: `docs/kanban/README.md`
