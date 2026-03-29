# Block Expression Codegen Cleanups

## Sequence: 53
## Tier: 6 — Polish
## Former ID: 20

## Summary

The BlockExpr codegen has several workarounds and magic numbers that should be cleaned up for maintainability. These are internal code quality issues, not user-facing bugs, but they make the codegen harder to understand and extend.

## Current State

- Placeholder padding used instead of explicit next-block-slot tracking.
- Magic number `2` for `blockLocalStart` -- unclear why this value.
- Optional SET_FIELD discard pattern -- sometimes the result of SET_FIELD is discarded with an extra slot.
- Internal `blockEnv` keys are undocumented conventions.
- `$discard` slot pattern for expression statements within blocks.

Implementation today lives primarily in `compiler/src/codegen/codegen.ts` (`case 'BlockExpr'`), including closure slot layout (`__env` at 0, first param at 1), mutual-recursion record temps (`\x00_record`, `\x00_closure`, `\x00_unit`), and dummy map entries `\x00_${i}` to advance `blockEnv.size` after reserving `$discard`.

## Relationship to other stories

- **None** as a hard dependency. Adjacent polish item **54** (disassembler) is unrelated functionally.
- If this story introduces named constants or small helpers, **54** might eventually reference the same names in comments only—no ordering requirement.

## Goals

1. Make block local slot allocation explicit and readable (no reliance on `Map` size hacks where avoidable).
2. Document why closure bodies need a minimum local index of `2` (or equivalent), so future edits do not reintroduce env/param clobber bugs.
3. Make SET_FIELD stack cleanup consistent or clearly documented per path (Unit on stack after `SET_FIELD`).
4. Document internal `blockEnv` key conventions in one place (file-level or adjacent to `BlockExpr` case).
5. Preserve bytecode behavior: no semantic or performance regressions for blocks, nested `fun`, mutual recursion, and discard-heavy paths.

## Acceptance Criteria

- [ ] Replace placeholder padding with explicit next-block-slot tracking in the local allocator.
- [ ] Replace magic number `2` for `blockLocalStart` with a named constant or computed value with a comment explaining its derivation.
- [ ] Clean up SET_FIELD discard pattern -- either always discard or document when the result is used.
- [ ] Add code comments documenting internal `blockEnv` keys and their purposes.
- [ ] Ensure no regression: all existing tests (compiler unit + Kestrel unit + E2E) continue to pass.

## Spec References

- None (internal code quality). No change to language semantics.

## Risks / notes

- **Closure slot layout** is easy to break: lowering assumes captured env at local 0 and params from 1 upward; wrong `blockLocalStart` or `nextSlot` floors cause overwrite bugs (historically bus errors).
- **ValStmt/VarStmt slot assignment** currently uses `blockEnv.size`; any refactor must keep the same numeric slots for emitted `LOAD_LOCAL`/`STORE_LOCAL` or update all consumers consistently.
- **Phase 2 / mutual recursion** paths share `sharedRecordTemp`, `closureTemp`, `unitTemp`; padding and fun-slot reservation interact—run full `functions.test.ks` and mutual-recursion cases after each logical change.
- **SET_FIELD** leaves `Unit` on the stack; branches that skip `emitStoreLocal(discardSlot)` when `$discard` is missing must remain correct for blocks without expr/assign statements.

## Impact analysis

| Area | Change |
|------|--------|
| **Compiler / VM bytecode** | `compiler/src/codegen/codegen.ts` — `BlockExpr` case: slot reservation, `blockEnv` bookkeeping, optional comments/constants at module or function scope. |
| **Compiler / JVM** | No change required for acceptance unless the team chooses parallel clarity edits in `compiler/src/jvm-codegen/codegen.ts` (different model: `nextLocal`); default scope is bytecode only. |
| **VM / Zig** | None. |
| **stdlib / scripts** | None. |
| **Tests** | Existing coverage is the safety net (`tests/unit/functions.test.ks`, tail/mutual tests, compiler Vitest). Add targeted tests only if a new invariant is introduced (e.g. dedicated codegen unit test for slot layout). |
| **Risk** | Medium-low: behavior-preserving refactor; highest risk is subtle slot miscounts in nested closures and mutual `fun` blocks. Rollback is revert single-file codegen change. |

## Tasks

- [ ] Introduce explicit **next free local** (or equivalent) for the block body so ValStmt/VarStmt no longer depend on dummy `\x00_*` keys solely to bump `blockEnv.size`; remove or minimize placeholder padding while preserving slot numbers for existing emitted code paths.
- [ ] Add a **named constant** (e.g. minimum slot after closure prologue) replacing bare `2` where it means “first slot after `__env` (0) and first param (1)”; tie the comment to lifted lambda env layout (`liftedEnv.set('__env', 0)`, params at `i + 1`).
- [ ] Audit all **`SET_FIELD` + optional `$discard`** branches in `BlockExpr` / related assign paths; either always pop/store Unit to a documented temp when the stack must be balanced, or add a short comment per branch explaining why discard is skipped.
- [ ] Add a **comment block** (or file-level section) listing internal `blockEnv` keys: `$discard`, `\x00_record`, `\x00_closure`, `\x00_unit`, and any remaining reserved keys after cleanup.
- [ ] Run verification: `cd compiler && npm run build && npm test`; `./scripts/kestrel test`; `./scripts/run-e2e.sh`. Run `cd vm && zig build test` if any bytecode emission changes are suspected to affect opcode sequences (usually unchanged).

## Tests to add

| Layer | Intent |
|-------|--------|
| **Existing `tests/unit/functions.test.ks`** | Primary regression suite for nested blocks, nested `fun`, mutual recursion, discard after Unit, closure over block locals—must stay green; no new cases required unless a bug is found during refactor. |
| **Existing `tests/unit/tail_mutual_recursion.test.ks`** | Covers tail/mutual paths that stress block-like lowering; run as part of `./scripts/kestrel test`. |
| **Compiler Vitest** | `cd compiler && npm test` — catches codegen/parser integration regressions. |
| **Optional** | If slot logic is extracted to a testable helper, add `compiler/test/unit/codegen-block*.test.ts` (or extend an existing codegen test file) with focused assertions on reserved slot indices for a minimal `BlockExpr` fixture. |

## Documentation and specs to update

- **None** in `docs/specs/` (no user-visible semantics).
- **In-repo**: comments only in `compiler/src/codegen/codegen.ts` (and constants colocated there) per acceptance criteria.

## Notes

- Consider extracting `BLOCK_ENV_DISCARD_KEY` / `BLOCK_ENV_RECORD_KEY`-style constants if that improves grepability without widening the diff; keep names private to the codegen module.
- The `WhileExpr` / loop discard path uses a similar `$discard`-style key (`discKey`); out of scope unless the implementer unifies patterns in the same PR deliberately.
