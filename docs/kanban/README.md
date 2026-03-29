# Kanban

Stories live in `docs/kanban/` with folders: **unplanned**, **planned**, **doing**, **done**.

Work flows **in order**: `unplanned` → `planned` → `doing` → `done`. Do not skip **planned** unless the team explicitly agrees (for example a trivial regression or doc-only fix).

## Global sequence (`NN-slug.md`)

Every story file is named **`NN-slug.md`** where **`NN` is a globally unique sequence** across **unplanned**, **planned**, **doing**, and **done**. The number never changes when a file moves between folders.

- **`docs/kanban/done/`** — **01–49** (completed stories; lower numbers are not “newer,” they are the global index assigned at renumbering).
- **`docs/kanban/unplanned/`** — **50–67** (current roadmap queue). **Lower numbers are higher priority** within this band (50 first, then 51, …).
- **New roadmap items** use the next free integer (**68** onward) so IDs stay unique project-wide.

Each story file should include **`## Sequence:`** (same value as **`NN`**), **`## Tier:`**, and **`## Former ID:`** where useful (for example the previous filename prefix before a renumber, or `(none)` if there was no numeric prefix).

### Roadmap tiers (`unplanned/`, sequences 50–67)

| Tier | Sequences | Focus |
|------|-----------|--------|
| **4** | 50 | Stdlib stack `trace()` / stack traces |
| **5** | 51–52 | Broader test coverage (E2E negative, conformance) |
| **6** | 53–54 | Polish (block-expression codegen, disassembler) |
| **7** | 55–59 | Deferred large work (async, HTTP, arrays, URL, lockfile) |
| **Optional** | 60–63 | Language sugar, VM float work, fixtures, spread follow-up |
| **(follow-up)** | 64 | JSON / `Result` errors, remove `value` builtins |
| **8** | 65–67 | Networking expansion: TCP/TLS sockets (`kestrel:socket`), REST-capable HTTP client (`kestrel:http` extensions), lightweight routing (`kestrel:web` or as specified) |

Completed stories in **`done/`** retain their **`## Tier:`** lines from delivery; there is no separate tier table for **01–49** here—open the file for context.

The **`planned/`** folder holds the same filenames (moved from `unplanned/` when promoted); **`doing/`** and **`done/`** likewise.

## Phases (gates)

| Phase | Meaning |
|-------|---------|
| **unplanned** | High-level feature intent: **summary**, **current state**, **relationships**, **goals**, **acceptance criteria**, **spec references**, and **risks / notes**. **Not** build-ready. |
| **planned** | Same content as unplanned, plus **impact analysis**, concrete **Tasks**, **Tests to add**, **Documentation and specs to update**, and optional **Notes** (may absorb or extend unplanned risks). Still **not** executing implementation—this is the planning gate before code. |
| **doing** | Implementation in progress. Tasks are ticked (and may be added) as the build proceeds; append **Build notes** as you learn. |
| **done** | Complete: every task checked, acceptance satisfied, **all required tests passing** (see exit criteria). |

### `unplanned/`

**Entry criteria**

- The idea is captured as a single markdown story with a title and assigned **`NN-slug.md`** (`NN` is globally unique; on the roadmap, lower `NN` means higher priority within the unplanned queue).
- Initial **Tier** is chosen (or “Optional / verification”).

**Exit criteria (before moving to `planned/`)**

- **Summary** states the outcome in one place.
- **Current state** explains what exists today (compiler, VM, stdlib, tests) and gaps.
- **Relationship to other stories** calls out dependencies, ordering, or merges (by sequence or path), or states **None** if truly isolated.
- **Goals** list the concrete outcomes you want (numbered or bulleted)—the “why and what” before the pass/fail **Acceptance criteria**.
- **Acceptance criteria** are testable and agreed (even if high level).
- **Spec references** list the `docs/specs/` areas that must stay authoritative.
- **Risks / notes** capture known hazards, constraints, performance or compatibility concerns, open technical questions, and links—anything that informs planning and implementation.

**Must not** include: a **Tasks** checkbox grid, exhaustive per-layer test matrices, or full **Impact analysis** tables—those belong in **planned**. A one-line reminder that tasks will be added in **planned** is fine inside **Risks / notes** if helpful.

### `planned/`

**Entry criteria**

- Story satisfies all **unplanned exit** criteria.
- File is **moved** from `unplanned/` to `planned/` (same filename).

**Exit criteria (before moving to `doing/`)**

- **Impact analysis** covers compiler, VM, stdlib, scripts, and tests as applicable (what files/areas change, risk, roll-forward/rollback). It should **incorporate or reference** bullet risks from unplanned **Risks / notes** (expand into file-level impact where needed).
- **Tasks** section exists with concrete checkboxes (implementation + verification steps).
- **Tests to add** lists harness layers (e.g. Vitest paths, `tests/unit/*.test.ks`, conformance files, `zig build test`) with intent per item.
- **Documentation and specs to update** lists every `docs/specs/` (and other docs) file to change.
- **Notes** (optional) holds research spikes, planning-only open questions, or links—anything useful for the implementer beyond what is already under **Risks / notes**.

**Optional section: `## Notes`** — free-form; does not replace acceptance criteria or tasks. Unplanned **Risks / notes** stay in the file when you promote; add **Notes** if you need a separate planning scratchpad.

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

## Goals

## Acceptance Criteria

## Spec References

## Risks / Notes
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
