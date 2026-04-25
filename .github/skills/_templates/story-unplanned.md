# Unplanned story template

Used by **story-create §B** and **plan-epic**. Path:
`docs/kanban/unplanned/S##-##-slug.md`.

Section headings are **load-bearing** — `scripts/check-story.sh` matches
on them. Do not rename.

```markdown
# <Title>

## Sequence: S##-##
## Tier: <tier or Optional>
## Former ID: (none)

## Epic

- Epic: [EXX Name](../epics/unplanned/EXX-name.md)
- Companion stories: <list sibling S##-## ids, or "None">

## Summary

<One paragraph: what this story delivers and why.>

## Current State

<What exists today in the codebase that this story changes or builds on.>

## Relationship to other stories

<How this story relates to siblings in the same epic, or to stories in
other epics. Note any blocking dependencies.>

## Goals

- <Goal bullet.>

## Acceptance Criteria

- [ ] <Observable outcome that proves this story is done.>

## Spec References

- `docs/specs/<file>.md` — <relevant section>

## Risks / Notes

- <Risk, open question, or implementation note.>
```

**Do not add yet:** `## Impact analysis`, `## Tasks`, `## Tests to add`,
`## Documentation and specs to update`. Those are added when the story
is promoted to `planned/` by **plan-story** (see
[story-planned-additions.md](story-planned-additions.md)).
