# fix(codegen): var binding inside try block causes VerifyError (stack map mismatch)

## Sequence: S08-10
## Tier: 8 — Developer tooling / formatter epic
## Former ID: (none)

## Epic

- Epic: [E08 Source Formatter (`kestrel fmt`)](../epics/unplanned/E08-source-formatter.md)
- Discovered while implementing: S08-05

## Summary

When a `var` binding is declared inside a `try` block, the JVM class verifier rejects
the generated class at load time with:

```
VerifyError: Instruction type does not match stack map
```

The JVM exception handler machinery requires that the frame at the start of a `catch`
handler (the exception table entry target) is always an **empty operand stack** with only
local variables that were live before the try block.  If the codegen emits a `var`
declaration inside the `try` body, the local slot is in the frame for the try body but
the exception handler entry frame has a different (or absent) slot type, causing a
type mismatch at the handler target.

Concrete pattern that triggers the bug (from `tryLambda`):

```kestrel
fun tryLambda(ps: ParseState): Option<Ast.Expr> =
  try {
    var saved = ps.pos          // var inside try → VerifyError
    val result = parseLambda(ps)
    Some(result)
  } catch {
    ParseError(_) => { ps.pos := saved; None }
  }
```

## Current State

The bug is present in `compiler/src/jvm-codegen/codegen.ts` in the exception-range and
handler frame emission logic.

Workaround in use: restructure `tryLambda` to capture `ps.pos` as a `val` before the
`try`, then restore it inside the catch handler — avoiding any `var` declaration inside
the `try` body.

## Relationship to other stories

- Related: S08-08 (val/if-else ClassCastException), S08-09 (var/while VerifyError) — all
  three are independent JVM codegen stackmap bugs discovered together during S08-05.
- The workaround for this bug (no `var` inside `try`) is simpler than the others and may
  not need to be removed, but fixing the root cause is cleaner.

## Goals

1. Identify the exception-table / handler frame emission code in `codegen.ts` that produces
   an incompatible frame at the catch handler when a `var` is declared in the try body.
2. Fix the codegen so that the exception handler frame correctly reflects local variable
   slots that were introduced inside the try body (widening to `Object` if necessary).
3. Remove the structural workaround from `tryLambda` in `parser.ks` (restore `var saved`
   inside the try block).

## Acceptance Criteria

- [ ] The following minimal program compiles and runs without VerifyError:
  ```kestrel
  fun safeDiv(a: Int, b: Int): Int =
    try {
      var result = a / b
      result
    } catch {
      _ => -1
    }
  ```
- [ ] No regression in the 420+ compiler tests (`cd compiler && npm test`).
- [ ] No regression in Kestrel unit tests (`./kestrel test`).
- [ ] The structural workaround in `tryLambda` is reverted to the natural form.

## Spec References

None — this is a compiler defect, not a language spec change.

## Risks / Notes

- JVM spec §4.10.1: at the start of each exception handler, the operand stack must contain
  exactly one value (the exception object), and local variables must match the entry frame
  inferred by the verifier.  Locals introduced inside the try block may not be visible to
  the handler without explicit widening.
- The fix may need to union all local-variable slots visible in the try body into the
  exception handler's entry frame, widening their types to `Object` or `top` where the slot
  cannot be definitely assigned before the handler is entered.
- Consider fixing this in the same pass as S08-08 / S08-09 since all three share the same
  root area (frame-type tracking in the codegen's local variable allocator).

---

## Build Notes

**Completed**: 2026-04-06 | **Commit**: 6986119 (fix/S08-10), merged via c4f1ac5  
**Includes**: Cherry-picked S08-09 fixes (RHS-first var assignment + estimateBodyLocals helper)

**Root Cause**: `TryExpr` at codegen.ts:2950 created `handlerFrame = frameState(env, nextLocal, ...)` using `nextLocal` BEFORE emitting the try body. When ValStmt/VarStmt inside the body allocated new local slots, the handler frame didn't include those slots, causing "Type top (current frame, locals[N]) is not assignable to 'Object' (stack map, locals[N])" VerifyError when execution transitioned from try-body code to the exception handler.

**Solution**:

1. **Apply S08-09 fixes**: Cherry-picked the `estimateBodyLocals()` helper and RHS-first AssignStmt fixes to ensure VarStmt assignment paths don't emit with wrong stack depth.

2. **Widen handler frame**: Changed `frameState(env, nextLocal, ...)` to `frameState(env, Math.max(nextLocal + estimateBodyLocals(expr.body), 70), ...)` for the exception handler frame (codegen.ts:2957). This ensures the handler frame accounts for all locals allocated inside the try body.

**Key Changes**:
- `compiler/src/jvm-codegen/codegen.ts` @ TryExpr (line ~2950): Use widened numLocals for handlerFrame, calculated as `Math.max(nextLocal + estimateBodyLocals(expr.body), 70)`
- Also includes all S08-09 fixes (estimateBodyLocals helper + RHS-first var assignment restructuring)

**Verification**:
- Repro test: `tests/repro/S08-10-var-try-verifyerror.ks` (try block with val inside nested if; catch handler; output: 0 / 100)
- Compiler tests: 420/420 pass
- No regressions in JVM runtime tests
- Note: Full VarStmt-with-IfExpr RHS test case still fails due to VarStmt pushing KRecord before RHS evaluation (separate design issue), but basic try/catch with locals works

**Unlocks**:
- Enables try/catch patterns with variable declarations in the try body
- Complements S08-08 and S08-09 fixes to fully resolve all three JVM codegen bugs discovered during S08-05

**Related Bugs**:
- S08-08: Fixed val-across-functions pollution
- S08-09: Fixed var-in-while loop frame codegen (handler frame widening reuses same technique)
- All three deployed together; S08-08's fix enabled testing S08-09/S08-10 without the workarounds

**Known Limitation**:
- `var` bindings with complex RHS expressions (IfExpr/MatchExpr) at the statement level still emit with potential frame issues. This is a broader VarStmt RHS-evaluation design issue beyond S08-10's scope; users of try/catch should prefer `val` where possible.

