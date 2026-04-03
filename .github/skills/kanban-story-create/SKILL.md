---
name: kanban-story-create
description: >-
  Creates a new Kestrel kanban story in docs/kanban/unplanned with correct
  sequence, tier, and required sections; or captures pre-roadmap items in
  docs/kanban/future. Use when adding a roadmap item, splitting a story,
  drafting unplanned work, or recording investigations before they are stories.
---

# Kestrel Kanban — create a story

## A. Future (investigations / ideas) — optional pre-roadmap

Use **`docs/kanban/future/`** when the work is **not** ready for the prioritized queue: spikes, performance observations, "maybe later" features without acceptance criteria yet.

1. Read [docs/kanban/README.md](docs/kanban/README.md) section **Future (investigations and ideas)**.
2. Filename: **`slug.md`** only (**no `NN-` prefix**, no global sequence).
3. Content: free-form; include a **`## Kind`** (e.g. investigation / idea) and enough context for later promotion.
4. **Do not** add **Sequence**, **Tier**, or full unplanned sections until promoting to **unplanned** (use **kanban-story-migrate**).

---

## B. Unplanned (roadmap)

Use this for **new** work that enters the roadmap at **`docs/kanban/unplanned/`**.

## Before you write (unplanned)

1. Read [docs/kanban/README.md](docs/kanban/README.md) for **unplanned entry/exit** criteria and the **tier table**.
2. Pick the next free **global `NN`** across **unplanned**, **planned**, **doing**, and **done** (see [docs/kanban/README.md](docs/kanban/README.md) for the tier table). Filename: **`NN-slug.md`** (two digits or more as needed, hyphen, short kebab-case slug).
3. Check for **duplicates** or **superseded** stories in `unplanned/` and `done/`.

## File location and name (unplanned)

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

- Ensure the story meets **unplanned exit** criteria before moving it to `planned/` (use skill **`kanban-story-migrate`**).

## Related

- **Future** items and promotion: skill **kanban-story-migrate** (section 0)
- Migrate roadmap phases: skill **kanban-story-migrate**
- Full gates: `docs/kanban/README.md`
- Implementation: skill **feature-delivery** (only once the story is in **`doing/`**)
