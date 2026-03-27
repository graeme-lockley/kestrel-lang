# Kanban

Stories live in `docs/kanban/` with folders: **unplanned**, **backlog**, **doing**, **done**.

## Roadmap order (`unplanned/`)

The **full backlog** is kept in **`unplanned/`**. Files are named **`NN-slug.md`** where **`NN` is the priority sequence** (01 first, then 02, …). Lower numbers are higher priority.

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

Each story file includes **`## Sequence:`**, **`## Tier:`**, and often **`## Former ID:`** (the old numeric filename prefix, if any).

## Workflow

1. **unplanned** — Ordered roadmap. Pick the **lowest sequence number** that is still relevant (skip closed verification-only stories such as 28–30 when appropriate).
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
