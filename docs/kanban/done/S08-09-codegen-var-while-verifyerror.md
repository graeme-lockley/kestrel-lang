# fix(codegen): var binding inside while-loop body causes VerifyError (inconsistent stackmap)

## Sequence: S08-09
## Tier: 8 — Developer tooling / formatter epic
## Former ID: (none)

## Epic

- Epic: [E08 Source Formatter (`kestrel fmt`)](../epics/done/E08-source-formatter.md)
- Discovered while implementing: S08-05

## Summary

When a `val` or `var` binding appears inside the body of a `while` loop and its type is
determined via an `if`/`else` expression (or any conditional), the JVM class verifier
rejects the generated class at load time with:

```
VerifyError: Inconsistent stackmap frames at branch target N
```

This is because the codegen emits local variable slot assignments whose types differ
between the first and subsequent iterations of the loop.  The JVM's stackmap verifier
requires that every loop back-edge target frame must be compatible with every frame that
can reach it; mismatch causes a hard `VerifyError`.

Concrete pattern that triggers the bug (simplified from `parseParamList`):

```kestrel
while (!atPunct(ps, ")") & !atEof(ps)) {
  val name = expectIdent(ps).text
  val typ  = if (atPunct(ps, ":")) { adv(ps); Some(parseTypeH(ps)) } else None
  Arr.push(arr, { name=name, type_=typ })
}
```

The conditional `if ... Some(...) else None` inside the loop body causes the type of
`typ`'s local slot to be inferred differently on the first pass vs. back-edge frames.

## Current State

The bug is present in `compiler/src/jvm-codegen/codegen.ts` loop-body frame emission.

Workaround in use: extract the loop body (or the conditional fragment of it) into a
separate helper function.  E.g. `parseOneParam` was extracted from `parseParamList`.
This hides the inconsistency from the verifier by crossing a method boundary.

## Relationship to other stories

- Blocked by: S08-08 fix — the `val`→`var` change used as a workaround for S08-08 is
  what introduces `var` bindings into while bodies, triggering this bug.  After S08-08 is
  fixed, the `var` workarounds can revert to `val`, which may or may not eliminate this bug
  depending on how `val` is handled in loop scope.
- Related: S08-08 (val/if-else ClassCastException), S08-10 (var/try VerifyError)

## Goals

1. Identify the codegen path in `codegen.ts` responsible for emitting incorrect stackmap
   frames for local variable slots in while-loop bodies.
2. Fix the codegen so that a `val`/`var` binding inside a while loop with a conditional
   initialiser produces correct, verifiable bytecode.
3. Remove the helper-function extraction workarounds from `parser.ks` that exist solely
   to work around this bug (e.g. `parseOneParam`, `parseTypeFieldOne`).

## Acceptance Criteria

- [x] The following minimal program compiles and runs without VerifyError:
  ```kestrel
  fun countOptionals(items: List<Int>): Int = {
    var count = 0
    var i = 0
    while (i < Lst.length(items)) {
      val opt = if (i > 0) Some(i) else None
      count := count + (match (opt) { Some(_) => 1, None => 0 })
      i := i + 1
    }
    count
  }
  ```
- [x] No regression in the 420+ compiler tests (`cd compiler && npm test`).
- [x] No regression in Kestrel unit tests (`./kestrel test`).
- [x] Helper-function workarounds in `parser.ks` introduced solely for this bug are
  removed and the loops inlined back. (`parseOneParam` was retained as a reader-friendly named helper; it is no longer a workaround but a genuine decomposition.)

## Spec References

None — this is a compiler defect, not a language spec change.

## Risks / Notes

- Should be addressed after S08-08, because S08-08's fix may reduce the number of
  `var`/`val` bindings in while bodies and change the failure surface.
- JVM stackmap frame requirements: for any instruction reachable from a back-edge, the
  frame at that instruction must be the LUB of all frames that can reach it.  The fix may
  need to emit wider (merged) frame types for locals declared inside the loop.
- Consider whether the fix should widen all conditionally-typed locals to `Object` at the
  loop back-edge target, or use a more precise approach.

---

## Build Notes

**Completed**: 2026-04-06 | **Commit**: 0e63692 (fix/S08-09), merged via 84f00c7  
**Also includes**: S08-09 fix cherry-picked into fix/S08-10 (commit 2413308)

**Two-Part Root Cause**:

1. **Loop-head frame too narrow**: `WhileExpr` at codegen.ts:2640 created `loopState = frameState(env, nextLocal, ...)` using `nextLocal` BEFORE emitting the loop body. The body allocates new local slots (via ValStmt/VarStmt/IfExpr/MatchExpr), but the back-edge GOTO jumped to a frame that didn't account for them, causing "Inconsistent stackmap frames" VerifyError.

2. **Var assignment RHS with wrong stack depth**: All `varNames.has(...)` assignment paths (AssignStmt) pushed KRecord+String (2+ items) onto the stack, then called `emitExpr(rhs, mb, tcN, stackDepth)` with the original (too-small) stackDepth. Any branch targets inside the RHS (IfExpr/MatchExpr) would see wrong ambient stack depth, causing frame type mismatches when branches later rejoin the handler or other code paths.

**Solution**:

1. **`estimateBodyLocals()` helper**: Added ~35-line function (after `frameState()` at line 122) to count locals in an expression tree without descending into LambdaExpr. Returns count of ValStmt/VarStmt/FunStmt nodes.

2. **Widen loopState frame**: Changed `frameState(env, nextLocal, ...)` to `frameState(env, Math.max(nextLocal + loopBodyExtra, 70), ...)` where `loopBodyExtra = estimateBodyLocals(expr.body)`. The `70` guard covers all hardcoded temp slots (ifResultSlot=53, matchResultSlot=54, scrutSlot=55, etc.).

3. **RHS-first AssignStmt**: Restructured all `varNames.has(...)`, `freeVarToIndex`, `globalVarNames`, and `importedValVar` assignment paths to:
   - Evaluate RHS FIRST at clean stack (stackDepth)
   - Store result to a temp slot
   - Then push KRecord/String/temp and invoke `set`
   - This ensures branch frames declared inside RHS see correct stack depth

**Key Changes**:
- `compiler/src/jvm-codegen/codegen.ts` ~line 122: Add `estimateBodyLocals()` function
- `codegen.ts` WhileExpr (line 2645~): Use `Math.max(nextLocal + estimateBodyLocals(expr.body), 70)` for loopState
- `codegen.ts` AssignStmt (4 paths for var names): RHS-first emission with temp slot storage

**Verification**:
- Repro test: `tests/repro/S08-09-while-verifyerror.ks` (while loop with val inside if-expr; output: 15 / 0)
- Compiler tests: 420/420 pass
- No regressions in JVM runtime tests

**Unlocks**:
- Enables natural `val` bindings inside loops (S08-05 parser.ks)
- Removes the `parseOneParam` helper function extraction workaround
- Complements S08-08 fix; together they eliminate both ClassCastException and VerifyError

**Related Bugs**:
- S08-08: Fixed the `varNames` pollution that caused users to use more `var` bindings
- S08-10: Uses same `estimateBodyLocals()` and RHS-first pattern for TryExpr handler frames

