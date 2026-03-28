---
name: kestrel-feature-delivery
description: >-
  Delivers a Kestrel language or compiler feature end-to-end: review the kanban
  story and specs, implement across typecheck/codegen/JVM/tests/docs, then verify
  tests and code quality. Use when implementing or finishing a feature from
  docs/kanban, when the user asks for full feature delivery, or when work must
  touch compiler plus tests plus specs.
---

# Kestrel feature delivery

Use this workflow for **kanban-driven** or **spec-driven** features in this repo. It complements [AGENTS.md](../../../AGENTS.md) and [.cursor/rules/kanban-workflow.mdc](../../rules/kanban-workflow.mdc).

## Phase 1 — Review the feature

Before writing code:

1. **Locate the story** — Usually `docs/kanban/unplanned/NN-slug.md` (ordered by `NN`), or `doing/` if already started. Read summary, **current state**, **acceptance criteria**, **spec references**.
2. **Extract concrete requirements** — Turn acceptance criteria into a mental or written checklist (implementation, tests, spec files to update).
3. **Read impacted specs** — Open the linked `docs/specs/*.md` sections so implementation and docs stay aligned (language, typesystem, bytecode, runtime, tests).
4. **Skim the codebase** — Find existing handlers (e.g. parser → `check.ts` → `codegen/codegen.ts` → `jvm-codegen/codegen.ts`). Note gaps vs the story.
5. **Refine the story** - Update the story to ensure that it is complete and the references in the story are accurate.  Ask any clarifying questions.  Pay particular attention to:
  - expand the acceptance criteria to amke refernce to an exhaustive set of unit tests to verify the automation, and
  - expand the acceptable criteria to update the list of impacted specs
6. **Kanban** — When starting work: move the story to `docs/kanban/doing/`, add a **Tasks** section with checkboxes; tick as you go. On completion: all tasks done → `docs/kanban/done/`.

## Phase 2 — Build the feature

Implement in **pass order** when the change spans the pipeline:

| Area | Path | Notes |
|------|------|--------|
| Parser / AST | `compiler/src/parser/`, `compiler/src/ast/` | Only if grammar or nodes change |
| Typecheck | `compiler/src/typecheck/check.ts` | Exhaustiveness, `bindPattern`, unification, diagnostics |
| Bytecode codegen | `compiler/src/codegen/codegen.ts` | Primary VM backend |
| JVM codegen | `compiler/src/jvm-codegen/codegen.ts` | **Keep parity** with bytecode for `match`, records, tuples, etc. |
| VM / runtime | `vm/` | Only if opcodes or runtime behaviour change |
| CLI / scripts | `scripts/` | If user-visible commands change |

**Tests (mandatory layers):**

- **Vitest** — `cd compiler && npm run build && npm test`. Add or extend `compiler/test/unit/` or `compiler/test/integration/` (e.g. typecheck conformance, exhaustiveness).
- **Kestrel harness** — `./scripts/kestrel test` from repo root; add cases in `tests/unit/*.test.ks` per [AGENTS.md](../../../AGENTS.md).
- **Typecheck conformance** — `tests/conformance/typecheck/valid/` and `invalid/` with `// EXPECT:` on invalid files; picked up by `compiler/test/integration/typecheck-conformance.test.ts`.
- **VM** — `cd vm && zig build test` when VM or bytecode semantics change.

**Specs** — Update every `docs/specs/` file the story lists (and any others behaviour touches). Specs are source of truth.

**Scope** — Match project style: minimal diff, no drive-by refactors, `.js` import suffixes in TS, Vitest + `describe`/`it` patterns.

- If building a kestrel library, the tests must be alongide the library file, otherwise the bulk of the tests must be the unit tests in `tests/unit`
- Ensure that tests are exhaustive, consider boundary conditions, and with minimal overlaps

## Phase 3 — Review the built feature

Treat this as a **hard gate** before calling the work done.

### Verification commands

Run from repo root (adjust if the feature is compiler-only):

```bash
cd compiler && npm run build && npm test
./scripts/kestrel test
cd vm && zig build test
./scripts/run-e2e.sh
```

Fix failures before merging or handing off.

### Code quality checklist

- **Structure** — New logic lives next to analogous cases (e.g. match arms together); shared behaviour extracted only when duplication is real (e.g. literal tests for stack slot vs scrutinee).
- **Naming / types** — Matches surrounding modules; explicit types on exported functions; no `any`.
- **Bindings** — Pattern/match temp locals use existing helpers (`nextPatternBindSlot`, env cleanup after arms) to avoid slot collisions.
- **Dual backend** — If bytecode `MatchExpr` (or similar) changed, JVM `MatchExpr` was checked for the same patterns.
- **Diagnostics** — User-facing errors reference the failing construct; codes consistent with `compiler/src/diagnostics/`.
- **Dead ends** — No stray `TODO`s for required story items; no disabled tests unless justified.

### Story closure

- Acceptance criteria and kanban **Tasks** are ticked.
- Story file is in `docs/kanban/done/` with completed tasks.

## Quick copy-paste checklist

```
Review: [ ] story read  [ ] specs read  [ ] code locations found  [ ] kanban in doing/
Build:  [ ] typecheck  [ ] codegen  [ ] jvm-codegen (if applicable)  [ ] vm (if applicable)
Tests:  [ ] compiler npm test  [ ] kestrel test  [ ] conformance .ks  [ ] zig test (if applicable)
Docs:   [ ] docs/specs updated  [ ] story → done  [ ] e2e (if applicable)
Review: [ ] no lints  [ ] parity  [ ] minimal diff
```

## Related paths

- Kanban workflow: `docs/kanban/README.md`
- Conformance README: `tests/conformance/typecheck/README.md` (if present)
