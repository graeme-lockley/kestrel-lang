# Conventions

Cross-cutting reminders that apply to every skill in this folder.

## Date sourcing

Use the date from the runtime environment, **not** from memory or
training data. Most skills surface the current date in their context;
when adding a `YYYY-MM-DD` build note, use that date verbatim.

If the runtime date is not available, ask the author rather than
guessing.

## Tick boxes immediately, never batch

When `build-story` or `build-epic` completes a task:

- Mark the corresponding `- [ ]` as `- [x]` **immediately** \u2014 same
  edit, same step.
- Do **not** batch checkbox ticks until the end of the session.
- Batched ticks make Build notes incoherent and break partial
  resumption after a failure.

This applies equally to `## Tasks`, `## Documentation and specs to
update`, and `## Acceptance Criteria`.

## Commit cadence

- One conventional-commit per logical unit (story plan, story
  implementation, epic refresh, epic close).
- Never combine unrelated changes in one commit.
- See [`../_templates/commit-messages.md`](../_templates/commit-messages.md) for
  patterns.

## Push policy

- Skills **never** push. The author pushes after review.
- This is enforced by the `forbids` list in each SKILL.md frontmatter.

## Working tree hygiene

- A skill must start from a clean working tree (or a tree containing
  only the in-progress story's changes).
- If unrelated modifications are present, halt per
  [`failure-protocol.md`](failure-protocol.md) \u00a74.

## Imports & code style (TypeScript edits)

- `.js` extensions in TypeScript imports.
- Match surrounding style; no drive-by refactors.
- Explicit return types on exported functions; no `any`.

## Imports & code style (Kestrel edits)

- Prefer string interpolation `"${a}${b}"` over `append(a, b)`.
- Test group names use `kestrel:` module reference style
  (e.g. `"kestrel:data/list"`).
