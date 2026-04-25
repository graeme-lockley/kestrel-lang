# Epic file template

Used by **epic-create**. Path: `docs/kanban/epics/unplanned/EXX-slug.md`.

Replace `EXX`, `<Title>`, and the placeholder content. Keep section
headings exactly as shown — `scripts/check-epic.sh` matches on them.

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

Optional section: **`## Implementation Approach`** — add when the epic
has a significant architectural approach worth recording (e.g. "uses
Project Loom virtual threads").

When stories exist, replace the `## Stories` block with:

```markdown
## Stories (ordered — implement sequentially)

1. [S##-##-slug.md](../../unplanned/S##-##-slug.md) — <one-line description>
2. ...
```
