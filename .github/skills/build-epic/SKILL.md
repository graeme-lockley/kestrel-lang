---
name: build-epic
description: >-
  Builds a Kestrel kanban epic end-to-end: reviews and refreshes the epic plan,
  then iterates through every member story in sequence — planning each to
  planned/, committing it, building it with build-story, verifying tests pass
  and specs are updated, and committing the result. Stops short of closing the
  epic so the author can review before marking done.
---

# Kestrel kanban — build an epic

Canonical rules: **[docs/kanban/README.md](docs/kanban/README.md)**.

This skill drives a full epic from planning through implementation, one story at a time, leaving the epic open for author review. It delegates story planning to **plan-story** and story implementation to **build-story**. Do **not** call **finish-epic** at the end — the author reviews and closes manually.

## Input

Epic identifier: `EXX` (example: `E02`)

## 0. Clarify before starting

Before doing any work, check for ambiguities that would block later steps. Ask the author if:

- The epic identifier is not supplied or does not resolve to a file.
- Two or more stories have unresolved inter-story dependencies that would make sequential execution wrong.
- Any story depends on work outside this epic that is not yet done.
- The epic contains a story in `doing/` or `done/` that the author may not want re-processed.

Raise these as explicit questions with suggested defaults. Do not guess silently.

---

## 1. Locate the epic

Find the epic file in `docs/kanban/epics/unplanned/EXX-*.md`.

- If the epic is already in `docs/kanban/epics/done/`, stop and report that nothing remains to build.
- If the epic file is not found in either location, report the problem and halt.

Read the epic file in full: objectives, dependencies, design notes, and — critically — the **`## Stories`** section.

---

## 2. Review and refresh the epic plan

Compare the epic's current content against the state of the codebase and the status of its member stories:

- Has the codebase changed since the epic was written in ways that affect its design, goals, or risks?
- Are any stories already in `planned/`, `doing/`, or `done/`? Record their current phase.
- Are the dependencies listed in the epic still accurate?
- Are there risks or notes that are now invalidated or need updating?

Make any necessary edits to the epic file. Commit the updated epic if anything changed using the commit-message style in [`_templates/commit-messages.md`](../_templates/commit-messages.md):

```bash
git add docs/kanban/epics/unplanned/EXX-*.md
git commit -m "docs(kanban): refresh EXX epic plan before build"
```

If nothing needed changing, skip the commit and note that the epic plan was reviewed and is current.

---

## 3. Build each story in sequence

Extract the **ordered story list** from the epic's `## Stories` section. Process stories **strictly sequentially** — never in parallel, even if **plan-epic** marked them as independent. Sequential execution is required so that:

- Test suites run in a known state.
- Build notes form a coherent timeline.
- Failures halt the epic at a deterministic point.

For each story `S##-##-slug.md`, in order:

### 3a. Determine current phase

Locate the story file across all kanban folders:

| Story is in | Action |
|-------------|--------|
| `future/` | Halt — story is not roadmap-ready. Ask the author before proceeding. |
| `unplanned/` | Proceed to 3b (plan-story). |
| `planned/` | Skip 3b; proceed to 3c (build-story). |
| `doing/` | Skip 3b and 3c prologue; proceed to 3c (resume build-story). |
| `done/` | Skip this story entirely; log it as already complete. |

### 3b. Plan the story (unplanned → planned)

Use the **plan-story** skill to add the full implementation plan:

1. Read the story in full.
2. Explore all codebase areas the story touches.
3. Read all referenced specs.
4. Add **Impact analysis**, **Tasks**, **Tests to add**, and **Documentation and specs to update** sections.
5. Move the file from `docs/kanban/unplanned/` to `docs/kanban/planned/`.

Commit the planned story:

```bash
git add docs/kanban/unplanned/S##-##-slug.md docs/kanban/planned/S##-##-slug.md
git commit -m "docs(kanban): plan S##-## <slug>"
```

### 3c. Build the story (planned → done)

Use the **build-story** skill to implement the story:

1. Move the story to `docs/kanban/doing/`.
2. Confirm the impact analysis against the current codebase; update tasks if scope has shifted.
3. Implement all tasks in pipeline order (parser → typecheck → codegen → JVM codegen → JVM runtime → stdlib → CLI).
4. Tick each task `[x]` immediately on completion.
5. Add tests for every item in **Tests to add**.
6. Update every doc/spec in **Documentation and specs to update** and tick each item.
7. Append **Build notes** for any non-obvious decision or scope change.

### 3d. Verify

Run the suites listed in [`_shared/verify.md`](../_shared/verify.md) for the triggers this story hit. Fix all failures before continuing to the next story.

Confirm:

- [ ] All **Tasks** are `[x]`.
- [ ] All **Documentation and specs to update** items are `[x]`.
- [ ] All required test suites pass.

If any check fails, do not move the story to `done/` until it is resolved.

### 3e. Commit and close the story

Move `docs/kanban/doing/S##-##-slug.md` → `docs/kanban/done/S##-##-slug.md`.

Commit all implementation changes and the story move together using a meaningful conventional-commit type (see [`_templates/commit-messages.md`](../_templates/commit-messages.md)) that reflects the dominant change. Do **not** use a generic message like "build story S##-##".

```bash
git add -A
git commit -m "<type>(<scope>): <concise description of what the story implements>"
```

---

## 4. Report and stop

After all stories are processed (complete, skipped, or blocked), produce a summary:

```
Epic EXX build summary
======================
Stories processed : N
  Completed now   : N  (S##-##, S##-##, ...)
  Already done    : N  (S##-##, ...)
  Skipped / blocked: N (S##-## — reason)

All required tests: PASS / FAIL (list failures if any)

The epic has NOT been closed. Review the implementation and run
finish-epic when satisfied.
```

Do **not** move the epic file to `docs/kanban/epics/done/`. Do **not** call **finish-epic**. Leave that to the author.

---

## Examples

For a model closed epic, see [docs/kanban/epics/done/E14-self-hosting-compiler.md](../../../docs/kanban/epics/done/E14-self-hosting-compiler.md) and one of its built stories, e.g. [S14-11-compiler-driver-pipeline.md](../../../docs/kanban/done/S14-11-compiler-driver-pipeline.md). The pair shows what an epic looks like after every member story has been built and committed.

## Related

- Plan a single story: skill **plan-story**
- Build a single story: skill **build-story**
- Close a completed epic: skill **finish-epic**
- Create a new epic: skill **epic-create**
- Kanban rules: `docs/kanban/README.md`
