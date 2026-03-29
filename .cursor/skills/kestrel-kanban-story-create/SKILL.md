---
name: kestrel-kanban-story-create
description: >-
  Creates a new Kestrel kanban story in docs/kanban/unplanned with correct
  sequence, tier, and required sections. Use when adding a roadmap item,
  splitting a story, or drafting unplanned work before planning gates.
---

# Kestrel Kanban — create a story (unplanned)

Use this for **new** work that enters the roadmap at **`docs/kanban/unplanned/`**.

## Before you write

1. Read [docs/kanban/README.md](../../../docs/kanban/README.md) for **unplanned entry/exit** criteria and the **tier table**.
2. Pick the next free **`NN`** in the roadmap (or an explicit sequence agreed with the team). Filename: **`NN-slug.md`** (two digits, hyphen, short kebab-case slug).
3. Check for **duplicates** or **superseded** stories in `unplanned/` and `done/`.

## File location and name

- Path: `docs/kanban/unplanned/NN-slug.md`
- Keep **Sequence** in the body aligned with **`NN`** in the filename.

## Required sections (unplanned)

Use the template from `docs/kanban/README.md`. Every unplanned story must have:

- Title (`# …`)
- `## Sequence: NN`
- `## Tier: …` (or Optional / verification)
- `## Former ID:` if migrating from an old id scheme
- `## Summary`
- `## Current State`
- `## Relationship to other stories` (or explicit **None** / **N/A** if isolated)
- `## Goals` — concrete numbered or bulleted outcomes (what you want beyond pass/fail acceptance lines)
- `## Acceptance Criteria` (testable bullets; can use `- [ ]` for tracking while still unplanned if useful)
- `## Spec References` (concrete `docs/specs/…` pointers)
- `## Risks / Notes` — hazards, constraints, performance, JVM/VM/host concerns, open questions, links; optional one-line pointer that **Tasks** / **Tests to add** land in **planned**

## Do not add (yet)

- **Impact analysis**, **Tasks** checkbox grid, **Tests to add**, **Documentation and specs to update** — those belong in **`planned/`** when the story is promoted.

## After the file exists

- Ensure the story meets **unplanned exit** criteria before moving it to `planned/` (use skill **`kestrel-kanban-story-migrate`**).

## Related

- Migrate phases: `.cursor/skills/kestrel-kanban-story-migrate/SKILL.md`
- Full gates: `docs/kanban/README.md`
- Implementation: `.cursor/skills/kestrel-feature-delivery/SKILL.md` (only once the story is in **`doing/`**)
