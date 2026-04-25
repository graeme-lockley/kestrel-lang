# Glossary — Kestrel agent skills

Definitions used by the skills in this folder. The canonical kanban rules
are in [docs/kanban/README.md](../../docs/kanban/README.md); this file
defines only the terms that recur in skill prose.

## Epic

A multi-story container in `docs/kanban/epics/`. File naming `EXX-slug.md`
where `XX` is a zero-padded integer (e.g. `E03`). Active epics live in
`epics/unplanned/`; completed epics in `epics/done/`. Epics are closed by
the **finish-epic** skill, never silently.

## Story

A single roadmap item in `docs/kanban/<phase>/`. File naming
`S##-##-slug.md` where the first `##` is the epic id and the second `##`
is the story index within that epic. The id is **stable** across phase
moves.

## Phase

The folder a story currently lives in:

| Phase | Folder |
|-------|--------|
| future | `docs/kanban/future/` (no `S##-##` prefix; pre-roadmap ideas) |
| unplanned | `docs/kanban/unplanned/` |
| planned | `docs/kanban/planned/` |
| doing | `docs/kanban/doing/` |
| done | `docs/kanban/done/` |

## Gate

The set of conditions that must hold before a story may move to the next
phase. Gates are documented inline in `plan-story` (§A) and `build-story`
(§B), and enforced by `scripts/check-story.sh`.

## Tier

A priority/scope band defined in
[docs/kanban/README.md](../../docs/kanban/README.md). Each story records
its tier in a `## Tier:` line.

## Sequence

The `S##-##` identifier of a story, recorded in a `## Sequence:` line in
the story body. Always equals the filename's `S##-##` prefix.

## Slug

The human-readable, kebab-case suffix of a story or epic filename
(e.g. `tail-optimization-self-recursion`).

## Build note

A dated bullet under a story's `## Build notes` section, recording a
material implementation decision, surprise, or trade-off. Added during
the **doing** phase by **build-story**.

## Tasks (story section)

A checkbox list under `## Tasks` populated by **plan-story** and ticked
by **build-story**. Every item must be `- [x]` before the story moves to
`done/`.

## Impact analysis

A table under `## Impact analysis` listing every code/spec area a story
modifies. Authored by **plan-story**.

## Tests to add

A table under `## Tests to add` listing test files and their intent.
Authored by **plan-story**, executed by **build-story**.

## Documentation and specs to update

A checkbox list under `## Documentation and specs to update` that
**build-story** ticks as it edits each doc/spec.

## Acceptance criteria

The bullet list under `## Acceptance Criteria` describing observable
outcomes that prove the story is done. Authored at **unplanned** time.

## Epic completion criteria

The bullet list under `## Epic Completion Criteria` describing
observable outcomes that prove the epic is done. Verified by
**finish-epic**.
