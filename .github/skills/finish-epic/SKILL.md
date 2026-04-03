---
name: finish-epic
description: >-
  Closes a Kestrel kanban epic by auditing every member story for completed
  tasks and satisfied acceptance criteria, validating epic-level objectives,
  running the required full test suites, and moving the epic from
  docs/kanban/epics/unplanned/ to docs/kanban/epics/done/ only when all gates
  are green. Accepts an epic identifier (for example E01).
---

# Kestrel kanban - finish an epic

Canonical rules: [docs/kanban/README.md](docs/kanban/README.md).

Use this skill to close an epic only after story-level and epic-level completion criteria are objectively satisfied.

## Input

- Epic identifier: `EXX` (example: `E01`)

## 1. Locate epic and member stories

1. Find the epic file in:
   - `docs/kanban/epics/unplanned/EXX-*.md` (active epic)
   - or `docs/kanban/epics/done/EXX-*.md` (already complete)
2. If epic is already in `epics/done/`, stop and report no action needed.
3. Read the epic fully, including:
   - `## Stories`
   - `## Epic Completion Criteria` (or equivalent objectives/acceptance section)
4. Extract all member story IDs from the epic story list (for example `S01-01` ... `S01-11`).

## 2. Verify story phase and checklist completeness

For each member story:

1. Locate the story file across:
   - `docs/kanban/unplanned/`
   - `docs/kanban/planned/`
   - `docs/kanban/doing/`
   - `docs/kanban/done/`
2. Fail epic closure if any member story is not in `docs/kanban/done/`.
3. Read each story and verify:
   - `## Tasks` has no unchecked `- [ ]` items.
   - `## Acceptance Criteria` has no unchecked `- [ ]` items (or each criterion is explicitly satisfied in the story text/build notes).
   - Any required docs/spec updates in story checklists are complete.
4. If any story fails these checks, do not close epic; report blockers by file and line.

## 3. Verify epic-level criteria

1. Reconcile epic-level completion criteria/objectives against current story outcomes.
2. Confirm no unresolved epic-level blockers remain (for example deferred scope not tracked by follow-up).
3. If epic criteria are not fully satisfied, stop and report exactly what is missing.

## 4. Run required verification suites

Run from repository root:

```bash
cd compiler && npm run build && npm test
./scripts/kestrel test
./scripts/run-e2e.sh
```

Optional (when runtime/JVM changes are part of epic scope):

```bash
cd runtime/jvm && bash build.sh
```

Rules:

- All required suites must pass to close the epic.
- If any suite fails, do not move epic; report the failing command and blocker details.

## 5. Close remaining story bookkeeping (if needed)

If all tests pass and only bookkeeping remains:

1. For any member story still in `doing/` but otherwise complete:
   - mark final task/acceptance checkboxes as complete where evidence exists,
   - move story file to `docs/kanban/done/`.
2. Ensure story `## Epic` links still resolve after epic move.

## 6. Move epic to done

Only when all gates above are green:

1. Update epic status to `Done`.
2. Ensure epic story list entries are marked complete and links point to `../../done/S##-##-*.md`.
3. Move epic file:

```bash
mv docs/kanban/epics/unplanned/EXX-*.md docs/kanban/epics/done/
```

4. Update any affected story epic links from `../epics/unplanned/...` to `../epics/done/...` where necessary.

## 7. Report outcome

Provide:

- Epic ID and final location
- Story audit summary (all member stories done + checklist status)
- Test commands executed and pass/fail result
- Any follow-up items (if epic was not moved)

## Guardrails

- Never move an epic to `done/` if any member story is outside `done/`.
- Never move an epic to `done/` if required tests fail.
- Never silently ignore unchecked story tasks/acceptance criteria.
- Prefer explicit blocker reporting with file references over assumptions.
