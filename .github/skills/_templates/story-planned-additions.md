# Planned story additions

Used by **plan-story**. Append these sections to a story while moving it
from `unplanned/` to `planned/`. Do not modify the existing unplanned
sections except to fix factual errors.

## Section 1 — Impact analysis

```markdown
## Impact analysis

| Area | Change |
|------|--------|
| <component> | <what changes — file/function level> |
```

Cover: parser, typecheck, codegen (bytecode), codegen (JVM), JVM
runtime, stdlib, scripts, tests, docs/specs. State the nature of the
change, compatibility risk, and rollback notes where relevant.
Incorporate (do not silently drop) any bullets from `## Risks / Notes`.

## Section 2 — Tasks

```markdown
## Tasks

- [ ] <implementation change — file and function level>
- [ ] ...
- [ ] Run `cd compiler && npm run build && npm test`
- [ ] Run `./scripts/kestrel test`
```

Rules:

- One `- [ ]` per discrete file-level or function-level change.
- Pipeline order: parser → typecheck → codegen → JVM codegen → JVM
  runtime → stdlib → CLI.
- Add the relevant verification commands as their own tasks (see
  [`_shared/verify.md`](../_shared/verify.md) for the trigger matrix).

## Section 3 — Tests to add

```markdown
## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest unit | `compiler/test/unit/…` | … |
| Vitest integration | `compiler/test/integration/…` | … |
| Kestrel harness | `tests/unit/<feature>.test.ks` | … |
| Conformance typecheck | `tests/conformance/typecheck/…` | … |
| Conformance runtime | `tests/conformance/runtime/…` | … |
| E2E positive | `tests/e2e/scenarios/positive/…` | … |
| E2E negative | `tests/e2e/scenarios/negative/…` | … |
```

Include only the layers this story actually touches. For each entry
state *what* the test asserts: happy-path acceptance, boundary/edge
conditions, regression guards.

## Section 4 — Documentation and specs to update

```markdown
## Documentation and specs to update

- [ ] `docs/specs/<file>.md` — <what section, what to change>
- [ ] ...
```

Every file listed in `## Spec References` needs an entry. Add other
docs (AGENTS.md, guide.md, etc.) only if they already document the
affected feature.
