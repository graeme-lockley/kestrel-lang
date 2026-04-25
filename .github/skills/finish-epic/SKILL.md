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

Use this skill to close an epic. The closure is fully mechanical — a single script enforces every gate, runs all required test suites, updates links, moves the epic, and commits.

## Inputs

- **epic_id** — the epic identifier (e.g. `E01`).

## Outputs / Side effects

- Sets `## Status` to `Done` in the epic file.
- Verifies every member story passes `scripts/check-story.sh`.
- Runs all Epic close test suites from [`_shared/verify.md`](../_shared/verify.md).
- Moves `docs/kanban/epics/unplanned/EXX-*.md` → `docs/kanban/epics/done/`.
- Updates all story files that link to the epic (unplanned → done).
- Creates one `docs(kanban): close epic EXX <slug>` commit.
- **Does not push** to any remote.
- **Never** auto-ticks a story's checkboxes.

## 1. Run the finish-epic script

```bash
scripts/finish-epic.sh EXX
```

The script runs the following non-skippable sequence and exits non-zero on the first failure:

1. Locate epic file (must be in `epics/unplanned/`).
2. Set `## Status` to `Done`.
3. Pre-flight gate: `scripts/check-epic.sh` must exit 0.
4. Test suites (all four from the Epic close trigger in `_shared/verify.md`).
5. Move epic file to `epics/done/`.
6. Update story epic links (`unplanned` → `done`) in all kanban phase folders.
7. Postcondition gate: `scripts/check-epic.sh` must exit 0.
8. Commit with message `docs(kanban): close epic EXX <slug>`.

If the script exits non-zero, read its output, fix the reported blocker, and re-run. Do not attempt manual workarounds.

## 2. Report outcome

After the script exits 0, report:

- Epic ID and final file location.
- Exit output from the script (step results).
- Any follow-up items (e.g. stories with pre-existing issues caught by the gate).

## Examples

For a model closed epic, see [docs/kanban/epics/done/E15-bootstrap-jar-self-hosting-handoff.md](../../../docs/kanban/epics/done/E15-bootstrap-jar-self-hosting-handoff.md). Status is Done, every member story link points into `done/`, and every Epic Completion Criterion is verifiably satisfied by the listed stories.

## Guardrails

- Never move an epic to `done/` if any member story is outside `done/`.
- Never move an epic to `done/` if required tests fail.
- Never silently ignore unchecked story tasks/acceptance criteria.
- Prefer explicit blocker reporting with file references over assumptions.
