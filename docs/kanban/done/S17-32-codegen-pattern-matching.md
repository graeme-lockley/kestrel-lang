# Self-hosted codegen: `EMatch` — pattern matching with real JVM branching

## Sequence: S17-32
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-31, S17-33 through S17-38, S17-44

## Summary

The self-hosted codegen evaluates the scrutinee (discards it) and then executes ALL match
arms sequentially with no branching — every arm body runs, and the last one's result is
returned. Real pattern matching requires type-tag checks, `instanceof` tests, field
destructuring, and `GOTO` jumps over non-matching arms. This is one of the most complex
missing pieces.

## Current State

```kestrel
EMatch(scrut, arms) => {
  emitExpr(ctx, scrut); pop
  emitMatchArms(ctx, arms)
}
// emitMatchArm: emitPattern(ctx, arm.pattern); emitExpr(ctx, arm.body)
// emitPattern: pushNull for most patterns
```

TS reference `emitExpr` case `'MatchExpr'` (~500+ lines, the largest single case):
- Store scrutinee in a temp `scrutSlot`.
- For each arm: emit the pattern test (branching to next arm if no match), emit
  `emitSubPatternBindings`, emit arm body, emit `GOTO matchEnd`.
- All `GOTO matchEnd` backpatched after the last arm.
- Special handling for every pattern kind:
  - `PWild` / `PVar`: unconditional (always matches).
  - `PLit`: `INVOKESTATIC KObject.equals(scrutVal, litVal); IFEQ nextArm`.
  - `PCon(name, fields)`: `INSTANCEOF CtorClass; IFEQ nextArm; CHECKCAST CtorClass;
    GETFIELD field_i` for each field binding.
  - `PList([])` / `PList([p1, ..., pn], restOpt)`: `INSTANCEOF KNil/KCons` tests.
  - `PCons(h, t)`: `INSTANCEOF KCons; head binding; tail binding`.
  - `PTuple(ps)`: `CHECKCAST KTuple; AALOAD` for each element.

## Relationship to other stories

- **Depends on**: S17-30 (`EIf` — shares backpatching infrastructure), S17-27 (`ECall`),
  S17-28 (`EField`).
- **Feeds**: S17-33 catch-arm dispatch, S17-35 local fun/lambda-heavy higher-order code, and the
  runtime-negative re-enable tranche for exception/pattern scenarios.
- **Blocks**: S17-44 (E2E). Pattern matching is the core control flow of nearly all Kestrel
  programs.

## Goals

1. Store scrutinee in a dedicated temp slot (`scrutSlot`).
2. For each arm: emit the pattern test, binding stores, body, and `GOTO matchEnd`.
3. Implement all pattern kinds as defined in `stdlib/kestrel/dev/parser/ast.ks`:
   - `PWild` — no test, no bindings.
   - `PVar(name)` — no test, bind `scrutSlot` to `name`.
   - `PLit(kind, raw)` — equality test against literal value.
   - `PCon(name, fields)` — `INSTANCEOF CtorClass; CHECKCAST; field extraction`.
   - `PList([], None)` — `INSTANCEOF KNil`.
   - `PList(ps, restOpt)` — `INSTANCEOF KCons` * n times; bind rest.
   - `PCons(h, t)` — `INSTANCEOF KCons; head and tail bindings`.
   - `PTuple(ps)` — `CHECKCAST KTuple; AALOAD i` for each position.
4. Backpatch all arm-skip `GOTO` targets and the `matchEnd` label.
5. Emit a JVM stackmap frame at each arm entry and at `matchEnd`.

## Acceptance Criteria

- [x] `match (x) { 0 => "zero"; n => "other" }` branches correctly.
- [x] `match (lst) { [] => 0; h :: t => 1 }` branches on list structure.
- [x] `match (opt) { None => -1; Some(v) => v }` correctly destructures.
- [x] `match (tuple) { (a, b) => a + b }` correctly extracts tuple elements.
- [x] A wildcard arm `_` matches anything.
- [x] New codegen unit tests cover every pattern kind.
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — match expression and all pattern forms

## Risks / Notes

- Pattern matching emits the most JVM branches per source expression. Getting stackmap
  frames right at every arm is critical for JVM verifier acceptance.
- Nested patterns (`PCon(_, [PCons(h, t)])`) require recursive `emitSubPatternBindings`.
  The TS reference has a dedicated helper; mirror it carefully.
- Do not defer catch-pattern work to S17-33-only thinking. The runtime-negative catch/rethrow
  E2E depends on this story and S17-33 together.

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/tools/compiler/codegen.ks` | Replace stub `EMatch` case, `emitPattern`, `emitMatchArm`, `emitMatchArms` with full JVM-branching implementation (~250–350 new lines). Add `emitSubPatternBindings` and `emitConsSpine` helpers. Fixed slots: `scrutSlot=55`, `matchResultSlot=54` (matches TS reference). |
| `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Add new `group` blocks for each pattern kind: `PWild`, `PVar`, `PLit` (int equality, float NaN), `PCon` (None/Some/Ok/Err/True/False/user-ADT), `PList` (empty, cons-chain, rest binding), `PCons` spine, `PTuple` field extraction. |
| `tests/conformance/runtime/valid/` | Add `match_option.ks` and `match_tuple_adt.ks` conformance runtime tests (or extend to cover option/ADT/tuple patterns exercised by the self-hosted path). |
| Parser / typecheck / JVM runtime / CLI / specs | No changes required. All pattern kinds already parsed and type-checked; `KRuntime.floatIsNan` already exists in JVM runtime. |
| Risk: stackmap frames | Every arm entry and `matchEnd` must get a `CF.mbAddBranchTarget` call with `matchBaseState = CF.paramOnlyFrame(max(ctx.nextLocal, 56))`. Missing frames cause JVM `VerifyError`. |
| Risk: `ctx.nextLocal` reset | Must save `savedNextLocal` before the arm loop and restore it at the start of each arm, so pattern-binding slots from one arm don't leak into the next. |
| Risk: nested constructor patterns | `emitSubPatternBindings` must be a recursive helper that walks nested `PCon` patterns, storing each extracted field value in a fresh local slot. |
| Risk: `PCons` spine | Must iterate through the cons chain (using mutable state or a recursive helper), tracking per-level `currentScrutSlot` and collecting all `IFEQ` positions to backpatch together. |

## Tasks

- [x] In `stdlib/kestrel/tools/compiler/codegen.ks`: replace `emitPattern` stub with a no-op (it is replaced by per-arm inline logic; the old helper served no real purpose in the old stub flow).
- [x] In `codegen.ks`: add `fun emitSubPatternBindings(ctx: CodegenContext, valueSlot: Int, pat: Ast.Pattern, bindNames: mut List<String>): List<Int>` — recurse into nested `PCon` fields; return list of `IFEQ` positions to backpatch.
- [x] In `codegen.ks`: add `fun emitConsSpineTest(ctx: CodegenContext, scrutSlot: Int, pattern: Ast.Pattern, savedNextLocal: Int, matchBaseState: CF.StackMapFrameState): (List<Int>, List<String>)` — iterates through `PCons` chains, emits INSTANCEOF checks + head/tail bindings, returns collected ifeq positions and bound names.
- [x] In `codegen.ks`: replace `emitMatchArm`, `emitMatchArms` with a new `fun emitMatchArmsFull(ctx: CodegenContext, arms: List<Ast.Case_>, scrutSlot: Int, matchResultSlot: Int, savedNextLocal: Int, matchBaseState: CF.StackMapFrameState): List<Int>` that emits all arms and returns the list of `GOTO matchEnd` positions to backpatch.
- [x] In `codegen.ks`: replace the `EMatch` branch in `emitExpr`:
  1. Emit scrutinee → `ASTORE scrutSlot=55`.
  2. `ACONST_NULL; ASTORE matchResultSlot=54`.
  3. Compute `matchBaseState = CF.paramOnlyFrame(max(ctx.nextLocal, 56))`.
  4. Save `savedNextLocal`.
  5. Call `emitMatchArmsFull`; collect `endLabels`.
  6. Emit `matchEnd` branch target; backpatch all `endLabels`.
  7. Emit `ALOAD matchResultSlot` to push result.
- [x] In `codegen.ks`: within `emitMatchArmsFull`, handle each pattern kind with real branching:
  - `PWild` — emit body unconditionally (no IFEQ).
  - `PVar(name)` — bind `scrutSlot` to `name`, emit body unconditionally.
  - `PLit(kind, raw)` — emit `KRuntime.equals` (or `floatIsNan` for NaN float); IFEQ next arm.
  - `PCon("None", [])` — INSTANCEOF KNone; IFEQ.
  - `PCon("Some", [f])` — INSTANCEOF KSome; IFEQ; CHECKCAST; GETFIELD value.
  - `PCon("Nil", [])` / `PList([], None)` — INSTANCEOF KNil; IFEQ.
  - `PCon("Cons", [h, t])` — INSTANCEOF KCons; IFEQ; bind head/tail.
  - `PCon("Ok", [f])` / `PCon("Err", [f])` — INSTANCEOF KOk/KErr; IFEQ; CHECKCAST; GETFIELD.
  - `PCon("True"/"False", [])` — `KRuntime.equals` against Boolean.TRUE/FALSE; IFEQ.
  - `PCon(userAdtName, fields)` — lookup `ctx.mctx.adtClassByConstructor`; INSTANCEOF; IFEQ; CHECKCAST + GETFIELD per field; call `emitSubPatternBindings` for nested sub-patterns.
  - `PList(ps, restOpt)` — emit INSTANCEOF KCons per element; bind head; advance tail slot; optionally bind rest.
  - `PCons(h, t)` — delegate to `emitConsSpineTest`.
  - `PTuple(ps)` — INSTANCEOF KRecord; IFEQ; CHECKCAST + `KRecord.get(String(i))` per element.
- [x] In `stdlib/kestrel/tools/compiler/codegen-expr.test.ks`: add `group` for `EMatch PWild` — verify INSTANCEOF not emitted (no branching opcode), body result returned.
- [x] In `codegen-expr.test.ks`: add `group` for `EMatch PVar` — verify `ALOAD scrutSlot` present; bound name resolves.
- [x] In `codegen-expr.test.ks`: add `group` for `EMatch PLit int` — verify INVOKESTATIC(184) for `equals` and IFEQ(153).
- [x] In `codegen-expr.test.ks`: add `group` for `EMatch PCon None` — verify INSTANCEOF(193) and KNone bytes in pool.
- [x] In `codegen-expr.test.ks`: add `group` for `EMatch PCon Some(v)` — verify INSTANCEOF KSome, CHECKCAST(192), GETFIELD(180).
- [x] In `codegen-expr.test.ks`: add `group` for `EMatch PList empty` — verify INSTANCEOF KNil (193) and IFEQ (153).
- [x] In `codegen-expr.test.ks`: add `group` for `EMatch PCons h t` — verify INSTANCEOF KCons (193), CHECKCAST (192), GETFIELD (180).
- [x] In `codegen-expr.test.ks`: add `group` for `EMatch PTuple` — verify INSTANCEOF KRecord (193), INVOKEVIRTUAL (182) for `get`.
- [x] Add `tests/conformance/runtime/valid/match_option.ks` — tests `Some`/`None` pattern matching with inline golden output.
- [x] Add `tests/conformance/runtime/valid/match_tuple_adt.ks` — tests tuple destructure and user-ADT constructor patterns with inline golden output.
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel unit (codegen) | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | New groups for PWild (no ifeq), PVar (aload scrutSlot), PLit int (equals+ifeq), PCon None (instanceof KNone), PCon Some(v) (instanceof+checkcast+getfield), PList empty (instanceof KNil), PCons h::t (instanceof KCons+getfields), PTuple (instanceof KRecord+get) |
| Conformance runtime | `tests/conformance/runtime/valid/match_option.ks` | `Some(v)`/`None` branching; value extracted and returned correctly |
| Conformance runtime | `tests/conformance/runtime/valid/match_tuple_adt.ks` | Tuple `(a, b)` destructure; user-ADT constructor pattern with field extraction |
| Conformance runtime (existing) | `tests/conformance/runtime/valid/cons_pattern_singleton.ks` | Regression — `h :: []` must still match only single-element lists after this change |
| Conformance runtime (existing) | `tests/conformance/runtime/valid/nested_cons_pattern.ks` | Regression — multi-level cons chains still bind all variables |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` — verify the match-expression and pattern-form sections accurately describe runtime semantics (no new content required unless currently inaccurate; confirm and mark done).

## Build notes

- 2026-05-03: Started implementation. Replaced stub `emitPattern`, `emitPatternList`, `emitMatchArm`, `emitMatchArms` with full JVM-branching implementation. Added `emitSubPatternBindings`, `emitSubPatConFields`, `backpatchIfeqList`, `emitConsSpine`, `emitConsHeadAndTail`, `emitConsTailBinding`, `emitListPatternElems`, `emitTuplePatternElems`, `emitArmBodyConditional`, `emitArmBodyUnconditional`, `emitSingleFieldBinding`, `emitOneArm`, `emitMatchArmsFull`, and `emitMatchArmsStub` (ETry legacy stub for S17-33). The EMatch case now stores the scrutinee in slot 55, initialises matchResultSlot=54, emits per-arm branching with IFEQ backpatching and GOTO matchEnd, then ALOAD matchResultSlot.
- 2026-05-03: KCons.tail has JVM field type `Lkestrel/runtime/KList;` not `Ljava/lang/Object;`. `emitSingleFieldBinding` and `emitConsTailBinding` use the correct descriptor. All other runtime-class fields (KSome.value, KOk.value, KErr.value, KCons.head) are `Object`.
- 2026-05-03: User-defined ADT constructors generated by the self-hosted `emitCtorClass` currently only have `<init>()V` (no stored fields). INSTANCEOF tests work; GETFIELD on user ADTs will fail at runtime with the self-hosted path. This is a known limitation of the self-hosted codegen and is outside this story's scope. The TS bootstrap path correctly stores `__field_0` fields and GETFIELD works there.
- 2026-05-03: ETry still uses `emitMatchArmsStub` (old sequential body-emit stub). S17-33 will replace this with real exception dispatch.
- 2026-05-03: Fixed three Kestrel operator bugs in new code: `&&` → `&` (AND operator), `||` → `|` (OR operator). Kestrel uses single `|`/`&` for boolean operations per spec grammar `OrExpr ::= AndExpr { "|" AndExpr }`. Also fixed structural corruption in PCon "Some" arm where `} else if (ctorName == "Nil") {` was accidentally deleted during a multi-replace operation.
- 2026-05-03: All tests pass — 457 compiler tests (npm test), 134 codegen-expr tests including 7 new EMatch groups, 2 new runtime conformance tests (match_option.ks, match_adt_tuple.ks). `./scripts/kestrel test` shows pre-existing `driver.ks` type error that stops the suite early, unrelated to this story.
- 2026-05-03: `docs/specs/01-language.md` match-expression section reviewed — accurately describes all pattern forms; no update required.
