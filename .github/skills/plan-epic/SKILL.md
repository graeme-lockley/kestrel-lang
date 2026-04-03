---
name: plan-epic
description: >-
  Decomposes a Kestrel kanban epic into an ordered set of feature stories.
  Reads the epic, explores the codebase and relevant specs, identifies the
  right story boundaries and implementation order, creates each story file in
  docs/kanban/unplanned/, and updates the epic's story list. Use when an epic
  exists but has no stories yet, or when an epic needs to be fully decomposed
  before planning begins.
---

# Kestrel kanban — plan an epic

Canonical rules: **[docs/kanban/README.md](docs/kanban/README.md)**. This skill produces a set of ordered, unplanned stories from an epic. Each resulting story is ready for **plan-story** to flesh out into a fully-planned implementation.

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

For each story, create `docs/kanban/unplanned/S##-##-slug.md` using the **story-create** template. Required sections:

```markdown
# <Title>

## Sequence: S##-##
## Tier: <tier>
## Former ID: (none)

## Epic

- Epic: [EXX Name](../epics/unplanned/EXX-name.md)
- Companion stories: <list sibling S##-## ids>

## Summary

## Current State

## Relationship to other stories

## Goals

## Acceptance Criteria

## Spec References

## Risks / Notes
```

Write concrete, accurate content for every section based on what you found in steps 2–4. **Do not** add Tasks, Impact analysis, or Tests to add — those go in `planned/` via **plan-story**.

## 7. Update the epic file

Replace the `## Stories` section with the ordered list:

```markdown
## Stories (ordered — implement sequentially)

1. [S##-##-slug.md](../../unplanned/S##-##-slug.md) — <one-line description>
2. ...
```

Include a note after the list if any stories are independent and can be done in parallel.

## Related

- Create the epic first: skill **epic-create**
- Add a single story: skill **story-create**
- Plan an individual story (unplanned → planned): skill **plan-story**
- Build a story (planned → done): skill **build-story**
- Kanban rules: `docs/kanban/README.md`
