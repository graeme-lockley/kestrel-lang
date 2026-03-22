# Kanban

Stories live in `docs/kanban/` with folders: **unplanned**, **backlog**, **doing**, **done**.

## Roadmap order (`unplanned/`)

The **full backlog** is kept in **`unplanned/`**. Files are named **`NN-slug.md`** where **`NN` is the priority sequence** (01 first, then 02, …). Lower numbers are higher priority.

This order matches the “usable language” plan:

| Tier | Sequences | Focus |
|------|-----------|--------|
| **1** | 01–03 | Fix broken language (features that parse but misbehave) |
| **2** | 04–06 | Harden the runtime (safety, VM tests, overflow/divzero tests) |
| **3** | 07–10 | Complete the core language (modules, narrowing, unions) |
| **4** | 11–13 | Stdlib and test harness depth |
| **5** | 14–15 | Broader test coverage (E2E negative, conformance) |
| **6** | 16–17 | Polish (codegen cleanup, disassembler) |
| **7** | 18–22 | Deferred large work (async, HTTP, arrays, URL, lockfile) |
| **Optional** | 23–26 | Language sugar, VM verification, fixtures, archival spread note |

Each story file includes **`## Sequence:`**, **`## Tier:`**, and often **`## Former ID:`** (the old numeric filename prefix, if any).

## Workflow

1. **unplanned** — Ordered roadmap. Pick the **lowest sequence number** that is still relevant (skip closed verification-only stories such as 24–26 when appropriate).
2. **backlog** — Optional staging: empty by default; move a story here if you want a “next up” slice without renumbering. See `backlog/README.md`.
3. **doing** — Active work. When starting a story, move it here and add a **Tasks** section with checkboxes.
4. **done** — Completed. Move the story here when all tasks are ticked.

## When picking up a story

1. Move the file from `unplanned/` (or `backlog/`) to `doing/`.
2. Add a **Tasks** section, e.g.:
   ```markdown
   ## Tasks
   - [ ] Task 1
   - [ ] Task 2
   ```
3. Tick tasks as you go: `- [x] Task 1`.

## When completing a story

1. Ensure all tasks are ticked.
2. Move the story from `doing/` to `done/`.

## Story format

Stories are markdown files. Include: title, summary, current state, acceptance criteria, spec references, and **tasks** once the story is in **doing**.

Agent workflow: `.cursor/rules/kanban-workflow.mdc`.
