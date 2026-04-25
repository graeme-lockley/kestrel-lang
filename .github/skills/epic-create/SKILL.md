---
name: epic-create
version: 1.0.0
description: >-
  Creates a new Kestrel kanban epic in docs/kanban/epics/unplanned/ from a
  description. Assigns the next free epic id, writes the required sections, and
  leaves the story list empty for plan-epic or story-create to fill. Use when
  starting a new area of work that will span multiple stories.
inputs:
  - title: "epic title and one-paragraph description"
outputs:
  - "creates docs/kanban/epics/unplanned/EXX-slug.md from the epic template"
allowed-tools: [read_file, list_dir, file_search, create_file, replace_string_in_file, manage_todo_list]
forbids: ["git push", "git push --force", "git reset --hard", "rm -rf"]
---

# Kestrel kanban — create an epic

Canonical rules: **[docs/kanban/README.md](docs/kanban/README.md)**.

## Inputs

- **title** — epic title and a paragraph describing what it delivers.

## Outputs / Side effects

- Creates `docs/kanban/epics/unplanned/EXX-slug.md` using [`_templates/epic.md`](../_templates/epic.md).
- No commits. The author commits the new file.

## 1. Choose the epic id

List `docs/kanban/epics/unplanned/` and `docs/kanban/epics/done/` to find all used epic ids. Pick the next free integer. Filename: **`EXX-slug.md`** (e.g. `E06-type-inference-improvements.md`).

## 2. Write the epic file

Path: `docs/kanban/epics/unplanned/EXX-slug.md`.

Use the canonical shape in [`_templates/epic.md`](../_templates/epic.md). Fill in title, summary, dependencies, and epic completion criteria. Leave the **Stories** section as `(None yet — use plan-epic to decompose, or story-create to add individual stories.)` until stories exist.

Do not invent additional sections. The optional **Implementation Approach** section may be added when an architectural choice is worth recording (see the template).

## 3. After the file exists

- Link the epic from any stories that belong to it (their `## Epic` section).
- Run **plan-epic** to decompose the epic into ordered stories, or add stories one at a time with **story-create**.
- Move the epic to `docs/kanban/epics/done/` only when all member stories are in `docs/kanban/done/`.

## Examples

For a model epic file, see [docs/kanban/epics/done/E15-bootstrap-jar-self-hosting-handoff.md](../../../docs/kanban/epics/done/E15-bootstrap-jar-self-hosting-handoff.md). It has a compact Summary, concrete Dependencies referencing prior epics, and six precise Epic Completion Criteria.

## Related

- Decompose into stories: skill **plan-epic**
- Add a single story: skill **story-create**
- Kanban rules: `docs/kanban/README.md`
