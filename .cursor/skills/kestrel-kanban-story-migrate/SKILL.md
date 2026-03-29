---
name: kestrel-kanban-story-migrate
description: >-
  Moves a Kestrel kanban story between unplanned, planned, doing, and done with
  the right content updates and entry/exit gates. Use when promoting a story,
  starting implementation, or closing work.
---

# Kestrel Kanban — migrate a story between phases

Canonical rules: **[docs/kanban/README.md](../../../docs/kanban/README.md)**. This skill is a checklist for agents; do not skip gates without explicit team agreement.

## Conventions

- **Move** the file (same `NN-slug.md` name): `unplanned/` → `planned/` → `doing/` → `done/`.
- **Never** change `NN` in the filename when moving (priority stays tied to the roadmap).
- Update the markdown **in place** as required by the target phase.

---

## A. `unplanned/` → `planned/`

### Preconditions (unplanned exit)

Story has complete: Summary, Current State, Relationship to other stories, Acceptance criteria, Spec references.

### Actions

1. Move `docs/kanban/unplanned/NN-slug.md` → `docs/kanban/planned/NN-slug.md`.
2. Add sections (if missing):
   - `## Impact analysis` — areas touched (compiler, VM, stdlib, scripts), risks, compatibility.
   - `## Tasks` — concrete `- [ ]` items covering implementation and verification.
   - `## Tests to add` — list planned tests by layer (Vitest paths, `tests/unit/*.test.ks`, conformance, Zig, E2E) and what each proves.
   - `## Documentation and specs to update` — explicit `docs/specs/` and other doc paths.
3. Optional: `## Notes` — spikes, links, open questions.

### Stop here until

Planned exit criteria met: impact, tasks, test list, and doc/spec list are substantive enough that an implementer can start without guessing.

---

## B. `planned/` → `doing/`

### Preconditions (planned exit)

All planned sections filled; team agrees the story is ready to build.

### Actions

1. Move `docs/kanban/planned/NN-slug.md` → `docs/kanban/doing/NN-slug.md`.
2. Add (if missing):

```markdown
## Build notes

- YYYY-MM-DD: Started implementation.
```

3. During implementation: tick **Tasks**, append **Build notes**, add new `- [ ]` tasks if scope emerges (complete them before **done**).

---

## C. `doing/` → `done/`

### Preconditions (doing exit)

- All **Tasks** are `[x]`.
- Acceptance criteria satisfied (or documented deferrals with follow-up stories).
- Tests run and pass per [AGENTS.md](../../../AGENTS.md) and the story’s own **Tests to add** / verification list.

### Actions

1. Run verification (adjust to the story):
   - `cd compiler && npm run build && npm test`
   - `./scripts/kestrel test` from repo root
   - `cd vm && zig build test` when bytecode/VM/runtime changes
   - `./scripts/run-e2e.sh` when user-visible behaviour or integration warrants it
2. Move `docs/kanban/doing/NN-slug.md` → `docs/kanban/done/NN-slug.md`.
3. Final pass: ensure **Documentation and specs to update** items are done or explicitly deferred in the story text.

---

## Skipping `planned/`

Only for **explicitly agreed** trivial work (doc-only, single-file regression). Record the exception in **Build notes** or **Notes**. Default path remains **unplanned → planned → doing → done**.

## Related

- Create new stories: `.cursor/skills/kestrel-kanban-story-create/SKILL.md`
- Build the feature: `.cursor/skills/kestrel-feature-delivery/SKILL.md`
- Subagents: `.cursor/agents/kanban-*.md`
