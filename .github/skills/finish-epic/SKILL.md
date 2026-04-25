---
name: finish-epic
version: 1.0.0
description: >-
  Closes a Kestrel kanban epic by auditing every member story for completed
  tasks and satisfied acceptance criteria, validating epic-level objectives,
  running the required full test suites, and moving the epic from
  docs/kanban/epics/unplanned/ to docs/kanban/epics/done/ only when all gates
  are green. Accepts an epic identifier (for example E01).
inputs:
  - epic_id: "epic identifier (EXX)"
outputs:
  - "verifies every member story is in done/ with all tasks ticked"
  - "runs the verification matrix (Epic close trigger)"
  - "moves docs/kanban/epics/unplanned/EXX-*.md to docs/kanban/epics/done/ when all gates pass"
  - "creates a single docs(kanban): close epic EXX commit"
allowed-tools: [read_file, list_dir, file_search, grep_search, replace_string_in_file, run_in_terminal, manage_todo_list]
forbids: ["git push", "git push --force", "git reset --hard", "git commit --amend", "git rebase", "rm -rf"]
---

# Kestrel kanban - finish an epic

Canonical rules: [docs/kanban/README.md](docs/kanban/README.md).

Use this skill to close an epic only after story-level and epic-level completion criteria are objectively satisfied.

When anything goes wrong at any step, follow [`_shared/failure-protocol.md`](../_shared/failure-protocol.md).

## Inputs

- **epic_id** — the epic identifier (e.g. `E01`).

## Outputs / Side effects

- Verifies every member story is in `done/` with all tasks/acceptance/docs ticked.
- Runs the verification matrix under the **Epic close** trigger.
- Moves `docs/kanban/epics/unplanned/EXX-*.md` → `docs/kanban/epics/done/` only when all gates pass.
- Creates one `docs(kanban): close epic EXX <slug>` commit.
- **Does not push** to any remote.
- **Never** auto-ticks a story's checkboxes.

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

## 2. Run deterministic epic gate

Run exactly one authoritative command:

```bash
scripts/check-epic.sh EXX
```

It must exit 0 before this skill can continue. This gate is deterministic and already includes per-story validation by calling `scripts/check-story.sh` for each member listed in `## Stories`.

`scripts/check-epic.sh` enforces:

- Every required epic section exists.
- Every member story is in `done/` and passes `check-story.sh`.
- No `- [ ]` boxes remain in `## Epic Completion Criteria`.
- `## Status` is exactly `Done`.

If it exits non-zero, halt and report blockers. Do not bypass or replace this with manual checklist review.

## 4. Run required verification suites

Run all suites listed in [`_shared/verify.md`](../_shared/verify.md) under the **Epic close** trigger. Every suite must pass for the epic to close.

If any suite fails, do not move the epic; report the failing command and blocker details per [`_shared/failure-protocol.md`](../_shared/failure-protocol.md).

## 5. Keep closure mechanical

Do not manually tick story checkboxes or hand-approve closure criteria. Story/epic closure is mechanical:

1. `scripts/check-epic.sh EXX` must pass.
2. Required verification suites under **Epic close** in [`_shared/verify.md`](../_shared/verify.md) must pass.
3. Only then may the epic be moved to `epics/done/`.

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

## Examples

For a model closed epic, see [docs/kanban/epics/done/E15-bootstrap-jar-self-hosting-handoff.md](../../../docs/kanban/epics/done/E15-bootstrap-jar-self-hosting-handoff.md). Status is Done, every member story link points into `done/`, and every Epic Completion Criterion is verifiably satisfied by the listed stories.

## Guardrails

- Never move an epic to `done/` if any member story is outside `done/`.
- Never move an epic to `done/` if required tests fail.
- Never silently ignore unchecked story tasks/acceptance criteria.
- Prefer explicit blocker reporting with file references over assumptions.
