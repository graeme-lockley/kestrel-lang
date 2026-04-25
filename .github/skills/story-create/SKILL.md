---
name: story-create
version: 1.0.0
description: >-
  Creates a new Kestrel kanban story in docs/kanban/unplanned/ or
  docs/kanban/future/, linked to an existing epic. Use when adding a roadmap
  item to an existing epic, splitting a story, or capturing a pre-roadmap idea.
inputs:
  - epic_id: "owning epic id (EXX); omit for a future/ idea"
  - title: "story title"
outputs:
  - "creates docs/kanban/unplanned/S##-##-slug.md (roadmap) or docs/kanban/future/slug.md (idea)"
  - "appends the new story to the owning epic's ## Stories list (roadmap only)"
allowed-tools: [read_file, list_dir, file_search, create_file, replace_string_in_file, manage_todo_list]
forbids: ["git push", "git push --force", "git reset --hard", "rm -rf"]
---

# Kestrel kanban — create a story

Canonical rules: **[docs/kanban/README.md](docs/kanban/README.md)**.

## Inputs

- **epic_id** — owning epic (`EXX`). Omit for a `future/` idea.
- **title** — story title.

## Outputs / Side effects

- Roadmap: creates `docs/kanban/unplanned/S##-##-slug.md` and appends the story to the owning epic's `## Stories` list.
- Future: creates `docs/kanban/future/slug.md` only.
- No commits.

---

## A. Future (investigations / ideas) — optional pre-roadmap

Use **`docs/kanban/future/`** when the work is **not** ready for the prioritized queue: spikes, observations, or "maybe later" ideas without clear acceptance criteria.

Use the canonical shape in [`_templates/story-future.md`](../_templates/story-future.md):

1. Filename: **`slug.md`** only — no `S##-##-` prefix, no story id.
2. Include a **`## Kind`** line (e.g. `investigation / idea / spike`).
3. Do **not** add **Sequence**, **Tier**, or full unplanned sections until promoting the file from `future/` to `unplanned/` (rename to `S##-##-slug.md` and add the sections listed in section B).

---

## B. Unplanned (roadmap story)

### Before you write

1. Identify the owning epic in `docs/kanban/epics/unplanned/`. The epic must already exist — create it first with **epic-create** if needed.
2. Find the next free story index within that epic (scan `docs/kanban/unplanned/` and `done/` for `S<epic-id>-*` filenames).
3. Check for duplicates or superseded stories in `unplanned/` and `done/`.
4. Read [docs/kanban/README.md](docs/kanban/README.md) for tier definitions and unplanned entry/exit criteria.

### File location and name

- Path: `docs/kanban/unplanned/S##-##-slug.md`
- `##-##` = epic id — story index within that epic (e.g. `S03-04`).
- Keep `## Sequence: S##-##` in the body aligned with the filename.

### Required sections

Use the canonical shape in [`_templates/story-unplanned.md`](../_templates/story-unplanned.md). Required sections (load-bearing — do not rename):

- `# <Title>`
- `## Sequence: S##-##`
- `## Tier: <tier or Optional>`
- `## Former ID: (none)`
- `## Epic`
- `## Summary`
- `## Current State`
- `## Relationship to other stories`
- `## Goals`
- `## Acceptance Criteria`
- `## Spec References`
- `## Risks / Notes`

**Do not add yet:** Impact analysis, Tasks, Tests to add, Documentation and specs to update — those belong in `planned/` (added by **plan-story**, see [`_templates/story-planned-additions.md`](../_templates/story-planned-additions.md)).

### After the file exists

- Add the story to the owning epic's **Stories** list with a markdown link and one-line description.
- Ensure the story meets unplanned exit criteria before promoting to `planned/` (see **plan-story §A**).

## Examples

For a model unplanned story, see [docs/kanban/done/S01-17-task-cancellation-api.md](../../../docs/kanban/done/S01-17-task-cancellation-api.md). The original unplanned sections (Summary, Current State, Goals, Acceptance Criteria, Spec References, Risks) demonstrate the level of concreteness expected.

## Related

- Create the epic first: skill **epic-create**
- Plan the story (add tasks, tests, impact): skill **plan-story**
- Kanban rules: `docs/kanban/README.md`
