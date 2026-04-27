# Self-hosted codegen: `EMatch` — pattern matching with real JVM branching

## Sequence: S17-32
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-31, S17-33 through S17-38, S17-42

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
- **Blocks**: S17-42 (E2E). Pattern matching is the core control flow of nearly all Kestrel
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

- [ ] `match (x) { 0 => "zero"; n => "other" }` branches correctly.
- [ ] `match (lst) { [] => 0; h :: t => 1 }` branches on list structure.
- [ ] `match (opt) { None => -1; Some(v) => v }` correctly destructures.
- [ ] `match (tuple) { (a, b) => a + b }` correctly extracts tuple elements.
- [ ] A wildcard arm `_` matches anything.
- [ ] New codegen unit tests cover every pattern kind.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — match expression and all pattern forms

## Risks / Notes

- Pattern matching emits the most JVM branches per source expression. Getting stackmap
  frames right at every arm is critical for JVM verifier acceptance.
- Nested patterns (`PCon(_, [PCons(h, t)])`) require recursive `emitSubPatternBindings`.
  The TS reference has a dedicated helper; mirror it carefully.
- Do not defer catch-pattern work to S17-33-only thinking. The runtime-negative catch/rethrow
  E2E depends on this story and S17-33 together.
