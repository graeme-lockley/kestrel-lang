# Kanban

Stories live in `docs/kanban/` with folders: **future**, **unplanned**, **planned**, **doing**, **done**.

Epics live in `docs/kanban/epics/` with folders: **unplanned** and **done**. Stories are grouped under one epic, and epics are moved to `epics/done/` once all member stories are complete.

Work flows **in order** on the roadmap: `unplanned` → `planned` → `doing` → `done`. Do not skip **planned** unless the team explicitly agrees (for example a trivial regression or doc-only fix).

The **`future/`** folder is **outside** that pipeline: it holds investigations and ideas **before** they become roadmap items (see [Future (investigations and ideas)](#future-investigations-and-ideas)).

## Story IDs (`S##-##-slug.md`)

Epic-grouped roadmap stories use **`S##-##-slug.md`** where:

- The first `##` is the epic id.
- The second `##` is the story index within that epic.

The `S##-##` id never changes when a story moves between `unplanned`, `planned`, `doing`, and `done`.

Legacy roadmap stories may still use older `NN-slug.md` names. Do not rename legacy completed stories unless explicitly requested.

**`future/`** does **not** use this prefix: files there are named **`slug.md`** only (kebab-case, no numeric priority). When an item graduates to the roadmap, it is renamed to **`S##-##-slug.md`** and moved to **`unplanned/`**.

- **`docs/kanban/done/`** — **01–54** (completed stories; lower numbers are not "newer," they are the global index assigned at renumbering).
- **`docs/kanban/planned/`** — **55–58** (JVM-only backend pivot — in planning).
- **`docs/kanban/unplanned/`** — **59–71** (current roadmap queue). **Lower numbers are higher priority** within this band (59 first, then 60, …).
- **New roadmap items** use the next free integer (**72** onward) so IDs stay unique project-wide.

Each story file should include **`## Sequence:`** (same value as **`S##-##`**), **`## Tier:`**, and **`## Former ID:`** where useful (for example the previous filename prefix before a renumber, or `(none)` if there was no numeric prefix).

Each roadmap story should also include **`## Epic`** with a markdown link to exactly one epic file under `docs/kanban/epics/unplanned/` or `docs/kanban/epics/done/`.

## Epics

Epics are cross-story containers that let related work move together at the planning level while stories still flow through `unplanned -> planned -> doing -> done` individually.

- Active epic files live in `docs/kanban/epics/unplanned/`.
- Completed epic files live in `docs/kanban/epics/done/`.
- Epic filename format: `EXX-slug.md` (for example `E03-http-and-networking-platform.md`).
- Each epic file should include: title, status, summary, story list with links, dependency notes, and epic completion criteria.

### Epic completion rule

Move an epic from `docs/kanban/epics/unplanned/` to `docs/kanban/epics/done/` only when:

- Every member story is in `docs/kanban/done/`.
- Epic-level acceptance/completion notes are satisfied.
- Any deferred scope is explicitly linked as a follow-up epic or story.

### Roadmap tiers

| Tier | Sequences | Location | Focus |
|------|-----------|----------|--------|
| **4** | 50 | done | Stdlib stack `trace()` / stack traces |
| **5** | 51–52 | done | Broader test coverage (E2E negative, conformance) |
| **6** | 53–54 | done | Polish (block-expression codegen, disassembler) |
| **8 (pivot)** | 55–58 | planned | JVM-only backend pivot (docs, scripts, VM removal, specs) |
| **7** | 59–63 | unplanned | Deferred large work (async, HTTP, arrays, URL, lockfile) |
| **Optional** | 64–67 | unplanned | Language sugar, VM float work, fixtures, spread follow-up |
| **8** | 68–70 | unplanned | Networking expansion: TCP/TLS sockets (`kestrel:socket`), REST-capable HTTP client (`kestrel:http` extensions), lightweight routing (`kestrel:web` or as specified) |
| **Optional** | 71 | unplanned | Test harness UX (compact suite spinner) |

Completed stories in **`done/`** retain their **`## Tier:`** lines from delivery; there is no separate tier table for **01-49** here-open the file for context.

The **`planned/`** folder holds the same filenames (moved from `unplanned/` when promoted); **`doing/`** and **`done/`** likewise.

## Future (investigations and ideas)

**`docs/kanban/future/`** captures **ideas under investigation** that are **not** ready to live on the prioritized **unplanned** queue. Use it for performance notes, spikes, "maybe someday" features, and cross-cutting observations where **goals and acceptance are still unclear**.

### Naming

- Filename: **`slug.md`** (short kebab-case slug). **No `S##-##-` prefix** and **no story id** until the item is promoted.
- Body: free-form, but should make clear this is **not** a committed story (for example a **`## Kind`** line: investigation / idea / spike).

### Relationship to the roadmap

- **`future/`** is **not** ordered by priority. Nothing in this folder is implied to be "next" after a given `NN` in **unplanned/**.
- Items here **do not** need unplanned entry/exit criteria, tiers, or acceptance tests until promoted.

### Promotion to `unplanned/`

When the team decides an item is real roadmap work:

1. Choose the owning epic id and next free story index within that epic.
2. **Move** and **rename**: `future/slug.md` → `unplanned/S##-##-slug.md`.
3. Fill standard **unplanned** sections (including **`## Sequence: S##-##`**, **`## Tier:`**, **Summary**, **Current State**, **Goals**, **Acceptance criteria**, **Spec references**, **Risks / notes**).

### Future template (minimal)

```markdown
# <Title>

## Kind

Investigation / idea / spike - not on the numbered roadmap.

## Context

## Questions or opportunities

## Promotion

When actionable: move to `unplanned/S##-##-<slug>.md` with full unplanned sections.
```

## Phases (gates)

| Phase | Meaning |
|-------|---------|
| **unplanned** | High-level feature intent: **summary**, **current state**, **relationships**, **goals**, **acceptance criteria**, **spec references**, and **risks / notes**. **Not** build-ready. |
| **planned** | Same content as unplanned, plus **impact analysis**, concrete **Tasks**, **Tests to add**, **Documentation and specs to update**, and optional **Notes** (may absorb or extend unplanned risks). Still **not** executing implementation-this is the planning gate before code. |
| **doing** | Implementation in progress. Tasks are ticked (and may be added) as the build proceeds; append **Build notes** as you learn. |
| **done** | Complete: every task checked, acceptance satisfied, **all required tests passing** (see exit criteria). |

### `unplanned/`

**Entry criteria**

- The idea is captured as a single markdown story with a title and assigned **`S##-##-slug.md`** (epic id + story index within epic).
- Initial **Tier** is chosen (or "Optional / verification").
- **Epic** link exists and points to a real file in `docs/kanban/epics/unplanned/` (or `epics/done/` for archival edits).

**Exit criteria (before moving to `planned/`)**

- **Summary** states the outcome in one place.
- **Current state** explains what exists today (compiler, JVM runtime, stdlib, tests) and gaps.
- **Relationship to other stories** calls out dependencies, ordering, or merges (by sequence or path), or states **None** if truly isolated.
- **Goals** list the concrete outcomes you want (numbered or bulleted)-the "why and what" before the pass/fail **Acceptance criteria**.
- **Acceptance criteria** are testable and agreed (even if high level).
- **Spec references** list the `docs/specs/` areas that must stay authoritative.
- **Risks / notes** capture known hazards, constraints, performance or compatibility concerns, open technical questions, and links-anything that informs planning and implementation.

**Must not** include: a **Tasks** checkbox grid, exhaustive per-layer test matrices, or full **Impact analysis** tables-those belong in **planned**. A one-line reminder that tasks will be added in **planned** is fine inside **Risks / notes** if helpful.

### `planned/`

**Entry criteria**

- Story satisfies all **unplanned exit** criteria.
- File is **moved** from `unplanned/` to `planned/` (same filename).

**Exit criteria (before moving to `doing/`)**

- **Impact analysis** covers compiler, JVM runtime, stdlib, scripts, and tests as applicable (what files/areas change, risk, roll-forward/rollback). It should **incorporate or reference** bullet risks from unplanned **Risks / notes** (expand into file-level impact where needed).
- **Tasks** section exists with concrete checkboxes (implementation + verification steps).
- **Tests to add** lists harness layers (e.g. Vitest paths, `tests/unit/*.test.ks`, conformance files, E2E scenarios) with intent per item.
- **Documentation and specs to update** lists every `docs/specs/` (and other docs) file to change.
- **Notes** (optional) holds research spikes, planning-only open questions, or links-anything useful for the implementer beyond what is already under **Risks / notes**.

**Optional section: `## Notes`** - free-form; does not replace acceptance criteria or tasks. Unplanned **Risks / notes** stay in the file when you promote; add **Notes** if you need a separate planning scratchpad.

### `doing/`

**Entry criteria**

- Story satisfies all **planned exit** criteria.
- File is **moved** from `planned/` to `doing/`.

**Exit criteria (before moving to `done/`)**

- Every **Task** is `[x]` (add new tasks if scope grew; then complete them too).
- **Build notes** capture material decisions, surprises, and follow-ups worth keeping in the story.
- Implementation matches **acceptance criteria** and listed spec updates are either done or explicitly deferred with a tracked follow-up.
- **Tests**: required suites pass per [AGENTS.md](../../AGENTS.md) (at minimum `cd compiler && npm run build && npm test`, `./scripts/kestrel test`; add E2E/conformance when the story demands it).

### `done/`

**Entry criteria**

- Story satisfies all **doing exit** criteria.
- File is **moved** from `doing/` to `done/`.
- Verification commands have been run successfully for the change set.

**Exit criteria**

- Terminal state: no further moves. Optional housekeeping: link follow-up stories in the file if work continues elsewhere.

## Workflow summary

1. **Optional:** Capture raw investigations or ideas in **`future/`** (`slug.md`, no `S##-##-` prefix). Promote to **`unplanned/`** when the work is ready for the roadmap.
2. **Draft** in `unplanned/` until unplanned exit criteria are met.
3. **Plan** in `planned/` until planned exit criteria are met.
4. **Implement** in `doing/`; tick tasks; append build notes.
5. **Close** in `done/` when tests pass and tasks are complete.

## Story templates

### Unplanned template

```markdown
# <Title>

## Sequence: S##-##
## Tier: <tier or Optional>
## Former ID: (if any)

## Epic

- Epic: [EXX Name](../epics/unplanned/EXX-name.md)

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

- [ ] ...

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

- YYYY-MM-DD: ...
```

## Automation and agents

- Cursor rule: `.cursor/rules/kanban-workflow.mdc`
- Skills: `.github/skills/epic-create/`, `story-create/`, `plan-epic/`, `kanban-story-migrate/`, `plan-story/`, `build-story/`
- Subagents: `.cursor/agents/kanban-*.md` (including **`kanban-future-author`** for **`future/`** items)

## Deprecated: `backlog/`

The **`backlog/`** folder is **deprecated**. Use **`planned/`** as the buffer between roadmap and implementation. See [backlog/README.md](backlog/README.md).
