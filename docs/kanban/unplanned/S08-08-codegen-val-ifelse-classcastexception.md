# fix(codegen): val binding used across if/else branches causes ClassCastException

## Sequence: S08-08
## Tier: 8 — Developer tooling / formatter epic
## Former ID: (none)

## Epic

- Epic: [E08 Source Formatter (`kestrel fmt`)](../epics/unplanned/E08-source-formatter.md)
- Discovered while implementing: S08-05

## Summary

When a `val` binding is declared before an `if`/`else` expression and the bound value is
used in both branches (or returned from the whole expression), the JVM codegen generates
incorrect bytecode that boxes the value as a `KRecord` in one code path but not the other.
At runtime this causes a `ClassCastException` of the form:
`<ActualType> cannot be cast to KRecord`.

Concrete pattern that triggers the bug:

```kestrel
fun parseArrowType(ps: ParseState): AstType = {
  val left = parseAppType(ps)          // returns e.g. ATPrim
  if (atPunct(ps, "->")) {
    adv(ps)
    ATFun(left, parseArrowType(ps))    // left used here: correctly typed
  } else
    left                               // left returned here: incorrectly boxed
}
```

The same class of bug appears anywhere a `val` is used in both branches of an `if`/`else`.

## Current State

The bug is present in `compiler/src/jvm-codegen/codegen.ts`.  It was first encountered
during S08-05 (parser.ks) in the `parseArrowType`, `parseConsExpr`, `parseIsExpr`,
`parsePowExpr`, and `parsePattern` functions.

Workaround in use: replace `val` with `var` for affected bindings.  This avoids the
ClassCastException but interacts badly with Bug S08-09 (var-in-while VerifyError).

## Relationship to other stories

- Blocks: full resolution of S08-05 (parser.ks needs clean `val` usage in most functions)
- Related: S08-09 (var/while VerifyError), S08-10 (var/try VerifyError) — the three bugs
  interact: workarounds for this bug introduce the other two

## Goals

1. Identify the exact codegen path in `codegen.ts` that produces incorrect KRecord boxing
   for a `val` that flows into multiple branches of an `if`/`else`.
2. Fix the codegen so that `val left = expr; if (...) { use left } else left` compiles to
   correct bytecode without KRecord wrapping.
3. Remove the `val`→`var` workarounds from `stdlib/kestrel/dev/parser/parser.ks`.

## Acceptance Criteria

- [ ] The following minimal program compiles and runs without ClassCastException:
  ```kestrel
  fun f(b: Bool): Int = {
    val x = 42
    if (b) x + 1 else x
  }
  ```
- [ ] No regression in the 420+ compiler tests (`cd compiler && npm test`).
- [ ] No regression in Kestrel unit tests (`./kestrel test`).
- [ ] The `val`→`var` workarounds introduced in `parser.ks` for this bug are reverted.

## Spec References

None — this is a compiler defect, not a language spec change.

## Risks / Notes

- The fix must not interfere with KRecord boxing that IS intentional (record construction).
- Verify the fix against all three affected patterns: `val` in if-true only, if-false only,
  and in both branches.
- After fixing this bug, re-check whether S08-09 and S08-10 still manifest (the `var`
  workarounds used for this bug may be the direct cause of those VerifyErrors).
