# Block Expression Codegen Cleanups

## Sequence: 53
## Tier: 6 — Polish
## Former ID: 20

## Summary

The BlockExpr codegen has several workarounds and magic numbers that should be cleaned up for maintainability. These are internal code quality issues, not user-facing bugs, but they make the codegen harder to understand and extend.

## Current State

- Placeholder padding (`\x00_${i}` map entries) used to advance `blockEnv.size` so the next `ValStmt`/`VarStmt` slot does not collide with `$discard`, instead of an explicit next-slot counter.
- Magic number `2` used in **two** places: `blockLocalStart` (when `needsDiscard`) and the floor for `nextSlot` when there are block-level `FunStmt`s. Both enforce “do not use local slots 0 or 1 inside a closure body”: slot `0` is `__env`, slot `1` is the first parameter of the enclosing closure (see comments at ~827–837 in `compiler/src/codegen/codegen.ts`).
- **SET_FIELD** leaves **Unit** on the stack; some paths store it into `$discard`, `unitTemp`, or reuse another local (e.g. `envTemp` in the single recursive-closure path); other paths (e.g. record **AssignStmt** via `FieldExpr`) call `emitSetField` without an adjacent discard—behavior must stay stack-correct per ISA.
- Internal `blockEnv` keys (`$discard`, `\x00_record`, `\x00_closure`, `\x00_unit`, padding keys) are undocumented conventions.
- `$discard` is reserved when the block has `ExprStmt` or `AssignStmt` (`needsDiscard`).

**Done:** `BlockExpr` uses explicit `nextBlockSlot` after reserving `$discard` and mutual-recursion temps; `CLOSURE_BLOCK_FIRST_FREE_LOCAL` and `BLOCK_ENV_*` constants document closure layout and reserved keys; record `FieldExpr` assignments store **SET_FIELD**’s Unit into `$discard` when present; `parseLowSurrogateAfterHigh` in `stdlib/kestrel/json.ks` works around nested-`match` codegen so JSON surrogate pairs parse correctly (full suite green).

## Relationship to other stories

- **None** as a hard dependency. Adjacent polish item **54** (disassembler) is unrelated functionally.
- If this story introduces named constants or small helpers, **54** might eventually reference the same names in comments only—no ordering requirement.

## Goals

1. Make block local slot allocation explicit and readable (no reliance on `Map` size hacks where avoidable).
2. Document why closure bodies need a minimum local index of `2` (or equivalent), so future edits do not reintroduce env/param clobber bugs.
3. Make SET_FIELD stack cleanup consistent or clearly documented per path (Unit on stack after `SET_FIELD` where applicable).
4. Document internal `blockEnv` key conventions in one place (file-level or adjacent to `BlockExpr` case).
5. Preserve bytecode behavior: no semantic or performance regressions for blocks, nested `fun`, mutual recursion, and discard-heavy paths.

## Acceptance Criteria

- [x] Replace placeholder padding with explicit next-block-slot tracking in the local allocator (or equivalent), without changing emitted `LOAD_LOCAL`/`STORE_LOCAL` indices for existing programs.
- [x] Replace magic number `2` everywhere it means “first slot after `__env` (0) and first enclosing param (1)” with a named constant or a single derived value, plus a short comment tying it to `liftedEnv.set('__env', 0)` and `params` at `i + 1` in mutual/single closure lowering.
- [x] Audit **SET_FIELD** (and related stack effects) on all `BlockExpr` statement paths; either unify discard/temp handling or add a brief comment per branch explaining why no extra pop/store is emitted (must remain consistent with `docs/specs/04-bytecode-isa.md` for **SET_FIELD**).
- [x] Add a comment block (or file-level section) listing internal `blockEnv` keys: `$discard`, `\x00_record`, `\x00_closure`, `\x00_unit`, padding keys `\x00_${i}` (or their replacement), and any new reserved keys introduced by the refactor.
- [x] **Regression:** full project verification green — at minimum the same commands as [AGENTS.md](../../../AGENTS.md) / `./scripts/test-all.sh`: `cd compiler && npm run build && npm test`, `cd vm && zig build test`, `./scripts/run-e2e.sh`, `./scripts/kestrel test`, and `./scripts/kestrel test --target jvm` (JVM must pass even when bytecode codegen is the only edited compiler path).
- [x] **`docs/specs/`:** no semantic or ISA changes expected; if implementation discoveries require clarifying **SET_FIELD** stack effect or local layout, update the relevant spec(s) and tick the corresponding item under **Documentation and specs to update** during implementation.

## Spec References

- [docs/specs/04-bytecode-isa.md](../../specs/04-bytecode-isa.md) — **SET_FIELD** stack effect; locals mapping is compiler-defined but must stay consistent with emitted code.
- [docs/specs/05-runtime-model.md](../../specs/05-runtime-model.md) — stack/locals model (sanity check only).
- [docs/specs/08-tests.md](../../specs/08-tests.md) — points at block/closure coverage locations; update only if new test files or harness paths are added.

## Risks / notes

- **Closure slot layout** is easy to break: lowering assumes captured env at local 0 and params from 1 upward; wrong `blockLocalStart` or `nextSlot` floors cause overwrite bugs (historically bus errors).
- **ValStmt/VarStmt slot assignment** currently uses `blockEnv.size`; any refactor must keep the same numeric slots for emitted `LOAD_LOCAL`/`STORE_LOCAL` or update all consumers consistently.
- **Phase 2 / mutual recursion** paths share `sharedRecordTemp`, `closureTemp`, `unitTemp`; padding and fun-slot reservation interact—run full `functions.test.ks` and mutual-recursion cases after each logical change.
- **SET_FIELD** leaves `Unit` on the stack in mutual-recursion patching; branches that use `unitTemp` vs `$discard` vs reusing `envTemp` must remain correct. Blocks **without** expr/assign statements do not allocate `$discard`; branches that guard on `discardSlot !== undefined` must stay correct.
- **WhileExpr** uses a similar discard key (`discKey`); out of scope unless the implementer deliberately unifies patterns in the same PR.

## Impact analysis

| Area | Change |
|------|--------|
| **Compiler / VM bytecode** | `compiler/src/codegen/codegen.ts` — `BlockExpr` case: slot reservation, `blockEnv` bookkeeping, optional comments/constants at module or function scope. |
| **Compiler / JVM** | No **planned** codegen edits in `compiler/src/jvm-codegen/codegen.ts` (different model: `nextLocal`). Regression still required: `./scripts/kestrel test --target jvm`. |
| **VM / Zig** | None expected; run `cd vm && zig build test` as part of full verification. |
| **stdlib / scripts** | `stdlib/kestrel/json.ks` — extract `parseLowSurrogateAfterHigh` (nested `match` in `parseUnicodeEscape` produced wrong continuation index for UTF-16 surrogate pairs; broke `json.test.ks` until fixed). |
| **Tests** | Existing suites per **Tests to add**; no new compiler unit file (slot logic not extracted as pure helper). |
| **Risk** | Medium-low: behavior-preserving refactor; highest risk is subtle slot miscounts in nested closures and mutual `fun` blocks. Rollback is revert single-file codegen change. |

## Tasks

- [x] Introduce explicit **next free local** (or equivalent) for the block body so `ValStmt`/`VarStmt` no longer depend on dummy `\x00_*` keys solely to bump `blockEnv.size`; remove or minimize placeholder padding while preserving slot numbers for existing emitted code paths.
- [x] Add a **named constant** (e.g. minimum slot after closure prologue) replacing bare `2` where it means “first slot after `__env` (0) and first param (1)”; tie the comment to lifted lambda env layout (`liftedEnv.set('__env', 0)`, params at `i + 1`).
- [x] Audit all **`SET_FIELD`** and **optional `$discard` / temp** branches in `BlockExpr` (including **AssignStmt** `FieldExpr`, capture `AssignStmt`, namespace setter, imported var setter); document or unify so stack depth invariants stay obvious.
- [x] Add a **comment block** (or file-level section) listing internal `blockEnv` keys: `$discard`, `\x00_record`, `\x00_closure`, `\x00_unit`, padding keys, and any remaining reserved keys after cleanup.
- [x] Run verification: `./scripts/test-all.sh` from repo root (or equivalent commands in **Tests to add** / **Acceptance criteria**). If anything fails, fix or document before closing.

## Tests to add

**New tests:** None required for story acceptance unless the refactor extracts testable helpers or fixes a discovered bug. If slot allocation moves into a pure helper, add `compiler/test/unit/codegen-block*.test.ts` (or extend an existing codegen unit file) with assertions on reserved indices or opcode patterns for a minimal `BlockExpr` fixture.

**Regression matrix (all must pass; no behavior change):**

| Layer | Paths / intent |
|-------|----------------|
| **Compiler (Vitest)** | `cd compiler && npm run build && npm test` — full suite including conformance (`tests/conformance/**`). Particularly relevant: `compiler/test/unit/compile.test.ts` (nested `FunStmt` in block), `compiler/test/integration/typecheck-integration.test.ts` (block-local `fun`, while/break blocks), `compiler/test/integration/parse.test.ts` (block/`BlockExpr` parsing), `compiler/test/unit/mutual-tail-codegen.test.ts` (codegen smoke). |
| **VM (Zig)** | `cd vm && zig build test`. |
| **E2E** | `./scripts/run-e2e.sh`. |
| **Kestrel unit (VM target)** | `./scripts/kestrel test` — includes `tests/unit/functions.test.ks` (nested blocks, nested `fun`, mutual recursion, discard, closures), `tests/unit/blocks.test.ks` (val/var/nested blocks), `tests/unit/lambdas.test.ks` (closures), `tests/unit/tail_mutual_recursion.test.ks`, `tests/unit/tail_self_recursion.test.ks`, `tests/unit/while.test.ks` (loop discard parallels). |
| **Kestrel unit (JVM target)** | `./scripts/kestrel test --target jvm` — same Kestrel tests on JVM backend. |
| **Conformance (via `npm test`)** | e.g. `tests/conformance/runtime/valid/conform_closure_val_vs_var.ks`; typecheck blocks/`break`/`continue` in `tests/conformance/typecheck/valid/break_continue_while.ks`, `tests/conformance/typecheck/invalid/nested_fun_return_type_mismatch.ks`, etc. |

**Convenience:** `./scripts/test-all.sh` runs compiler tests, VM tests, E2E, then Kestrel unit tests for both VM and JVM targets.

## Documentation and specs to update

### `docs/specs/`

- **Default:** none — behavior-preserving refactor; local layout remains compiler-defined per [04-bytecode-isa.md](../../specs/04-bytecode-isa.md).
- **If needed during implementation:** [docs/specs/04-bytecode-isa.md](../../specs/04-bytecode-isa.md) — only if audit shows the documented **SET_FIELD** stack effect is wrong or ambiguous relative to emitted code.
- **If new tests or harness paths are added:** [docs/specs/08-tests.md](../../specs/08-tests.md) — align references with any new files or suites.

### Other in-repo documentation

- **`compiler/src/codegen/codegen.ts`** — comments and named constants per acceptance criteria (internal developer documentation).

### Explicitly out of scope

- **`AGENTS.md`**, **`docs/kanban/`** — no update unless verification commands change (unlikely).

## Notes

- Consider extracting `BLOCK_ENV_DISCARD_KEY` / `BLOCK_ENV_RECORD_KEY`-style constants if that improves grepability without widening the diff; keep names private to the codegen module.
- The `WhileExpr` / loop discard path uses a similar `$discard`-style key (`discKey`); out of scope unless the implementer unifies patterns in the same PR deliberately.

## Build notes

- 2026-03-29: Story moved from **planned** to **doing** after expanding tests/docs acceptance to match kanban planned exit criteria and repo verification (`test-all.sh`, JVM target).
- 2026-03-29: **BlockExpr** — Replaced `\x00_${i}` padding with `nextBlockSlot`; added `CLOSURE_BLOCK_FIRST_FREE_LOCAL`, `BLOCK_ENV_DISCARD_KEY` / `BLOCK_ENV_RECORD_KEY` / `BLOCK_ENV_CLOSURE_KEY` / `BLOCK_ENV_UNIT_KEY`, file-level doc of reserved keys; `fun` slot base uses `Math.max(nextBlockSlot, CLOSURE_BLOCK_FIRST_FREE_LOCAL)`; record `FieldExpr` **AssignStmt** now stores **SET_FIELD** Unit into `$discard` when allocated; short comments on other assign branches; fixed `emitPhase2` wrapper indentation/bracing.
- 2026-03-29: **`stdlib/kestrel/json.ks`** — Surrogate-pair tail split into `parseLowSurrogateAfterHigh` so `parse("\"\\uD834\\uDD1E\"")` returns a single scalar string (nested `match` in `parseUnicodeEscape` previously yielded wrong continuation index / `trailing garbage at 1`). `./scripts/test-all.sh` and `./scripts/kestrel test --target jvm` green.
