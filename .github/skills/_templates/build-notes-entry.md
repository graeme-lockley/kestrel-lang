# Build notes

Used by **build-story** and **build-epic**. Append entries to a story's
`## Build notes` section as work progresses.

## Section header (created on entry to `doing/`)

```markdown
## Build notes

- YYYY-MM-DD: Started implementation.
```

## Entry shape

```markdown
- YYYY-MM-DD: <one-line decision, surprise, or trade-off>
```

## When to add an entry

- Started, paused, or resumed implementation.
- A non-obvious technical decision (e.g. chose approach A over B).
- An approach that did not work, with a brief reason.
- Scope discovered mid-implementation that added new tasks.
- A spec or impact-analysis item turned out to be wrong.

## When **not** to add an entry

- Routine task completion (just tick the `- [x]`).
- Cosmetic edits with no design content.
- "Ran the tests" — only note failures and how they were resolved.

## Date sourcing

Use the date from the runtime environment, not from memory. See
[`_shared/conventions.md`](../_shared/conventions.md).
