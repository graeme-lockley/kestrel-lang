---
name: epic-create
description: >-
  Creates a new Kestrel kanban epic in docs/kanban/epics/unplanned/ from a
  description. Assigns the next free epic id, writes the required sections, and
  leaves the story list empty for plan-epic or story-create to fill. Use when
  starting a new area of work that will span multiple stories.
---

# Kestrel kanban — create an epic

Canonical rules: **[docs/kanban/README.md](docs/kanban/README.md)**.

## 1. Choose the epic id

List `docs/kanban/epics/unplanned/` and `docs/kanban/epics/done/` to find all used epic ids. Pick the next free integer. Filename: **`EXX-slug.md`** (e.g. `E06-type-inference-improvements.md`).

## 2. Write the epic file

Path: `docs/kanban/epics/unplanned/EXX-slug.md`

Required sections:

```markdown
# Epic EXX: <Title>

## Status

Unplanned

## Summary

<One paragraph: what this epic delivers and why it matters.>

## Stories

(None yet — use plan-epic to decompose, or story-create to add individual stories.)

## Dependencies

<Other epics or external requirements this epic depends on, or "None".>

## Epic Completion Criteria

- <Bullet per observable outcome that proves the epic is done.>
```

Optional section **`## Implementation Approach`** — add when the epic has a significant architectural approach worth recording (e.g. "uses Project Loom virtual threads").

## 3. After the file exists

- Link the epic from any stories that belong to it (their `## Epic` section).
- Run **plan-epic** to decompose the epic into ordered stories, or add stories one at a time with **story-create**.
- Move the epic to `docs/kanban/epics/done/` only when all member stories are in `docs/kanban/done/`.

## Related

- Decompose into stories: skill **plan-epic**
- Add a single story: skill **story-create**
- Kanban rules: `docs/kanban/README.md`
