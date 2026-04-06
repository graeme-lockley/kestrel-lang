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
