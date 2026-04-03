---
name: feature-delivery
description: >-
  Delivers a Kestrel language or compiler feature end-to-end: locates the
  kanban story, applies plan-story (if unplanned) and build-story (if planned
  or doing), then verifies tests and story closure. Use when asked to deliver a
  feature from docs/kanban without specifying a phase, or when the story needs
  to move all the way from unplanned to done in one session.
---

# Kestrel feature delivery

End-to-end feature workflow. For single-phase work, use the focused skills directly: **plan-story** (unplanned → planned) or **build-story** (planned → done).

## Determine the story's phase

1. Locate the story file in `docs/kanban/`:
   - `future/` — not roadmap-ready. Promote to `unplanned/` using **kanban-story-create** first.
   - `unplanned/` — needs planning. Apply **plan-story**, then continue below.
   - `planned/` or `doing/` — ready to build. Apply **build-story**.
   - `done/` — already complete.

2. Open the owning epic file (`docs/kanban/epics/unplanned/EXX-*.md`) for cross-story dependencies.

## Apply the right skills

| Story is in | Action |
|-------------|--------|
| `future/` | Use **kanban-story-create** (promote) → then `unplanned/` row |
| `unplanned/` | Use **plan-story** → then `planned/` row |
| `planned/` | Use **build-story** |
| `doing/` | Resume with **build-story** (step 3 onwards) |

## After build-story completes

- All tasks are `[x]`, specs updated, tests green.
- Story is in `docs/kanban/done/`.
- Epic is updated; move to `docs/kanban/epics/done/` if all member stories are done.

## Related

- Plan a story: skill **plan-story**
- Build a story: skill **build-story**
- Phase gates: skill **kanban-story-migrate**
- Create stories: skill **kanban-story-create**
- Kanban rules: `docs/kanban/README.md`
