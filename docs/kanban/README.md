# Kanban

Stories live in `docs/kanban/` with folders: **unplanned**, **planned**, **doing**, **done**.

Work flows **in order**: `unplanned` → `planned` → `doing` → `done`. Do not skip **planned** unless the team explicitly agrees (for example a trivial regression or doc-only fix).

## Roadmap order (`unplanned/`)

The **prioritized feature list** lives in **`unplanned/`**. Files are named **`NN-slug.md`** where **`NN` is the priority sequence** (01 first, then 02, …). Lower numbers are higher priority.

This order matches the “usable language” plan:

| Tier | Sequences | Focus |
|------|-----------|--------|
| **1** | 01–07 | Fix broken language (pattern matching gaps, while loops, tail optimization) |
| **2** | 08–10 | Harden the runtime (safety, VM tests, overflow/divzero tests) |
| **3** | 11–14 | Complete the core language (modules, narrowing, unions) |
| **4** | 15–17 | Stdlib and test harness depth |
| **5** | 18–19 | Broader test coverage (E2E negative, conformance) |
| **6** | 20–21 | Polish (codegen cleanup, disassembler) |
| **7** | 22–26 | Deferred large work (async, HTTP, arrays, URL, lockfile) |
| **Optional** | 27–30 | Language sugar, VM verification, fixtures, archival spread note |

Each story file should include **`## Sequence:`**, **`## Tier:`**, and often **`## Former ID:`** (the old numeric filename prefix, if any).

The **`planned/`** folder holds the same filenames (moved from `unplanned/` when promoted); **`doing/`** and **`done/`** likewise. **Sequence and tier do not change** when a file moves—priority remains defined by the original `NN` in the name.

## Phases (gates)

| Phase | Meaning |
|-------|---------|
| **unplanned** | High-level feature intent: what it is, where things stand, how it relates to other work, acceptance criteria, spec pointers. **Not** build-ready. |
| **planned** | Same content as unplanned, plus impact analysis, concrete **Tasks**, tests to add, docs/specs to touch, and optional **Notes**. Still **not** executing implementation—this is the planning gate before code. |
| **doing** | Implementation in progress. Tasks are ticked (and may be added) as the build proceeds; append **Build notes** as you learn. |
| **done** | Complete: every task checked, acceptance satisfied, **all required tests passing** (see exit criteria). |

### `unplanned/`

**Entry criteria**

- The idea is captured as a single markdown story with a title and assigned **`NN-slug.md`** (sequence reflects priority in the roadmap).
- Initial **Tier** is chosen (or “Optional / verification”).

**Exit criteria (before moving to `planned/`)**

- **Summary** states the outcome in one place.
- **Current state** explains what exists today (compiler, VM, stdlib, tests) and gaps.
- **Relationship to other stories** calls out dependencies, ordering, or merges (by sequence or path).
- **Acceptance criteria** are testable and agreed (even if high level).
- **Spec references** list the `docs/specs/` areas that must stay authoritative.

**Must not** include: detailed implementation tasks, exhaustive test matrices, or impact tables—those belong in **planned**.

### `planned/`

**Entry criteria**

- Story satisfies all **unplanned exit** criteria.
- File is **moved** from `unplanned/` to `planned/` (same filename).

**Exit criteria (before moving to `doing/`)**

- **Impact analysis** covers compiler, VM, stdlib, scripts, and tests as applicable (what files/areas change, risk, roll-forward/rollback).
- **Tasks** section exists with concrete checkboxes (implementation + verification steps).
- **Tests to add** lists harness layers (e.g. Vitest paths, `tests/unit/*.test.ks`, conformance files, `zig build test`) with intent per item.
- **Documentation and specs to update** lists every `docs/specs/` (and other docs) file to change.
- **Notes** (optional) holds research spikes, open questions, or links—anything useful for the implementer.

**Optional section: `## Notes`** — free-form; does not replace acceptance criteria or tasks.

### `doing/`

**Entry criteria**

- Story satisfies all **planned exit** criteria.
- File is **moved** from `planned/` to `doing/`.

**Exit criteria (before moving to `done/`)**

- Every **Task** is `[x]` (add new tasks if scope grew; then complete them too).
- **Build notes** capture material decisions, surprises, and follow-ups worth keeping in the story.
- Implementation matches **acceptance criteria** and listed spec updates are either done or explicitly deferred with a tracked follow-up.
- **Tests**: required suites pass per [AGENTS.md](../../AGENTS.md) (at minimum `cd compiler && npm run build && npm test`, `./scripts/kestrel test`, and `cd vm && zig build test` when VM/bytecode touched; add E2E/conformance when the story demands it).

### `done/`

**Entry criteria**

- Story satisfies all **doing exit** criteria.
- File is **moved** from `doing/` to `done/`.
- Verification commands have been run successfully for the change set.

**Exit criteria**

- Terminal state: no further moves. Optional housekeeping: link follow-up stories in the file if work continues elsewhere.

## Workflow summary

1. **Draft** in `unplanned/` until unplanned exit criteria are met.
2. **Plan** in `planned/` until planned exit criteria are met.
3. **Implement** in `doing/`; tick tasks; append build notes.
4. **Close** in `done/` when tests pass and tasks are complete.

## Story templates

### Unplanned template

```markdown
# <Title>

## Sequence: NN
## Tier: <tier or Optional>
## Former ID: (if any)

## Summary

## Current State

## Relationship to other stories

## Acceptance Criteria

## Spec References
```

### Planned additions (keep all unplanned sections; add)

```markdown
## Impact analysis

## Tasks

- [ ] …

## Tests to add

## Documentation and specs to update

## Notes

(Optional.)
```

### Doing additions

- Tick **Tasks** in place; add sub-tasks if needed.
- Add or extend:

```markdown
## Build notes

- YYYY-MM-DD: …
```

## Automation and agents

- Cursor rule: `.cursor/rules/kanban-workflow.mdc`
- Skills: `.cursor/skills/kestrel-kanban-story-create/SKILL.md`, `.cursor/skills/kestrel-kanban-story-migrate/SKILL.md`
- Subagents: `.cursor/agents/kanban-*.md`

## Deprecated: `backlog/`

The **`backlog/`** folder is **deprecated**. Use **`planned/`** as the buffer between roadmap and implementation. See [backlog/README.md](backlog/README.md).
