# Self-hosted codegen: `EList`, `ECons`, `ETuple`, `ETemplate`, and `EPipe`

## Sequence: S17-29
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-28, S17-30 through S17-38, S17-44

## Summary

The self-hosted codegen stubs `EList`, `ECons`, `ETuple`, `ETemplate`, and `EPipe`: all
variants evaluate sub-expressions, discard them, and push `null`. This means list literals,
cons cell construction, tuples, string interpolation, and the pipe operator are all broken.

## Current State

- `EList(elems)`: calls `emitListElems` (which walks and discards), then `pushNull`.
- `ECons(h, t)`: evaluates head and tail, discards both, pushes `null`.
- `ETuple(xs)`: evaluates all elements, discards them, pushes `null`.
- `ETemplate(parts)`: calls `emitTemplateParts` (which walks and discards), then `pushNull`.
- `EPipe(_op, l, r)`: evaluates both sides, discards, pushes `null`.

TS reference:
- `EList`: build a `KList` via `KList.cons(head, tail)` calls from right to left; the empty
  list is `KNil.INSTANCE`.
- `ECons`: emit head, emit tail, call `KList.cons(Object, Object)`.
- `ETuple`: emit `new Object[n]`, store each element via `AASTORE`, wrap in `KTuple`.
- `ETemplate`: build string by concatenating parts using `KString.append` or a
  `StringBuilder` pattern.
- `EPipe`: rewrite to a call (`l |> f` becomes `f(l)`, `f |> g` becomes `g ∘ f` etc.) and
  delegate to `ECall`.

## Relationship to other stories

- **Depends on**: S17-27 (`ECall` — list cons and tuple constructors use method calls).
- **Recommended after**: S17-28, so list/template-heavy code reuses already-correct call and
  record/value paths.
- **Feeds**: the first positive E2E re-enable slice for core async/task and collection-heavy
  scenarios.
- **Blocks**: S17-44 (E2E). List literals and string templates are ubiquitous in Kestrel.

## Goals

1. `EList(elems)`: fold from right over elements, starting with `KNil.INSTANCE`, calling
   `KList.cons(elem, acc)` for each element. Handle spread elements.
2. `ECons(h, t)`: emit `h`, emit `t`, emit `INVOKESTATIC KList.cons(Object,Object)Object`.
3. `ETuple(xs)`: emit `BIPUSH n; ANEWARRAY Object; DUP; BIPUSH i; <emit xi>; AASTORE` for
   each element, then `INVOKESTATIC KTuple.of(Object[])`.
4. `ETemplate(parts)`: fold parts with `KString.append` calls. Literal string parts emit
   `LDC_W`; expression parts emit `emitExpr` then a `KObject.toString` call.
5. `EPipe("|>", l, r)`: rewrite `l |> r` as `ECall(r, [l])` and delegate; handle
   `"|>>"` (composition) by building a lambda if needed.

## Acceptance Criteria

- [ ] `[1, 2, 3]` compiles to a `KList` with three elements in the correct order.
- [ ] `h :: t` compiles and produces a cons cell.
- [ ] `(1, "two", True)` compiles to a `KTuple` with three elements.
- [ ] `"Hello ${name}!"` compiles and concatenates correctly.
- [ ] `lst |> List.map(f)` compiles and produces the mapped list.
- [ ] New codegen unit tests cover each construction and the pipe rewrite.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — list expressions, tuples, string templates, pipe operator

## Risks / Notes

- Spread elements in list literals (`[...rest, x]`) require additional handling; check the
  TS reference for the exact pattern.
- `EPipe` operator precedence rewriting must match the parser's fixity table exactly.
- This story is a good boundary for re-enabling positive scenarios in slices: once calls,
  records, operators, and these collection/template forms are real, the core async/task scenarios
  can start coming back before networked tests do.

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/tools/compiler/codegen.ks` — `emitExpr` | Replace 5 stub arms (`ECons`, `EPipe`, `ETemplate`, `EList`, `ETuple`) with correct bytecode emission. The existing private helpers `emitListElems` and `emitTemplateParts` become dead code (safe to leave in place). |
| `stdlib/kestrel/tools/compiler/codegen.ks` — `EList` | Fold from right: empty → `GETSTATIC KNil.INSTANCE`; non-empty → allocate two local slots (`listTemp`, `elemTemp`), iterate right-to-left; `LElem(e)` → `NEW KCons / DUP / emitExpr(e) / ASTORE elemTemp / ALOAD elemTemp / ALOAD listTemp / CHECKCAST KList / INVOKESPECIAL KCons.<init> / ASTORE listTemp`; `LSpread(e)` → `emitExpr(e) / ASTORE elemTemp / ALOAD elemTemp / ALOAD listTemp / INVOKESTATIC KRuntime.listPrependAll / ASTORE listTemp`. Finally `ALOAD listTemp`. |
| `stdlib/kestrel/tools/compiler/codegen.ks` — `ECons` | Allocate 2 local slots. Emit head → store. Emit tail → store. `NEW KCons / DUP / ALOAD headSlot / ALOAD tailSlot / CHECKCAST KList / INVOKESPECIAL KCons.<init>`. |
| `stdlib/kestrel/tools/compiler/codegen.ks` — `ETuple` | `NEW KRecord / DUP / INVOKESPECIAL <init>`. For each element at index `i`: `DUP / LDC_W(Str.show(i)) / emitExpr(elem) / INVOKEVIRTUAL KRecord.set`. Mirrors the TS reference which encodes tuple positional fields as "0", "1", … in `KRecord` (confirmed by spec §01-language §425 and `TupleExpr` in `codegen.ts`). |
| `stdlib/kestrel/tools/compiler/codegen.ks` — `ETemplate` | `NEW StringBuilder / DUP / INVOKESPECIAL <init>`. For each `TmplLit(s)`: `LDC_W(s) / INVOKEVIRTUAL StringBuilder.append(String)`; for each `TmplExpr(e)`: `emitExpr(e) / INVOKESTATIC KRuntime.formatOne / INVOKEVIRTUAL StringBuilder.append(String)`. Finally `INVOKEVIRTUAL StringBuilder.toString`. |
| `stdlib/kestrel/tools/compiler/codegen.ks` — `EPipe` | `"\|>"`: if right is `ECall(fn, args)` → `emitExpr(ECall(fn, left :: args))`; else → `emitExpr(ECall(right, [left]))`. `"<\|"`: if left is `ECall(fn, args)` → `emitExpr(ECall(fn, Lst.append(args, [right])))` ; else → `emitExpr(ECall(left, [right]))`. Matches TS `PipeExpr` case in `codegen.ts`. |
| `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Add test groups: `EList` (empty + 3-element), `ECons`, `ETuple` (real KRecord fields), `ETemplate` (real StringBuilder), `EPipe` (call rewrite). Assert bytecodes emitted (e.g., `getstatic` for `KNil.INSTANCE`, `invokespecial` for `KCons.<init>`, `new_ StringBuilder`, `invokevirtual StringBuilder.toString`). |
| `tests/unit/lists.test.ks` | Already written; will start passing under the self-hosted compiler once `EList`/`ECons` are fixed. No edits needed. |
| `tests/unit/tuples.test.ks` | Already written; will start passing once `ETuple` is fixed. No edits needed. |
| `tests/unit/pipes.test.ks` | Already written; will start passing once `EPipe` is fixed. No edits needed. |
| JVM runtime (`runtime/jvm/src/`) | No changes required. `KNil`, `KCons`, `KList`, `KRecord`, `KRuntime.listPrependAll`, `KRuntime.formatOne`, `java.lang.StringBuilder` already exist. |
| Specs / docs | No changes required; behaviour is already documented in `docs/specs/01-language.md`. |
| **Compatibility** | These are pure stub replacements; no existing passing test is at risk. The only risk is the spread-element path and correct right-to-left fold order for `EList`. |

## Tasks

- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks`, implement `EList` in `emitExpr`: replace `{ emitListElems(ctx, elems); pushNull(ctx) }` with the fold-from-right `KNil`/`KCons`/`listPrependAll` loop described in the impact analysis. Use `ctx.nextLocal` to allocate `listTemp` and `elemTemp` slots (bump `ctx.nextLocal` by 2).
- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks`, implement `ECons` in `emitExpr`: replace the discard+pushNull stub with 2-slot allocation, emit head/tail into slots, `NEW KCons / DUP / ALOAD headSlot / ALOAD tailSlot / CHECKCAST KList / INVOKESPECIAL KCons.<init>`.
- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks`, implement `ETuple` in `emitExpr`: replace the discard+pushNull stub with `NEW KRecord / DUP / INVOKESPECIAL <init>` then iterate elements emitting `DUP / LDC_W(index string) / emitExpr(elem) / INVOKEVIRTUAL KRecord.set` for each.
- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks`, implement `ETemplate` in `emitExpr`: replace `{ emitTemplateParts(ctx, parts); pushNull(ctx) }` with `NEW StringBuilder / DUP / INVOKESPECIAL <init>` then per-part append logic using `KRuntime.formatOne` for expression parts, ending with `INVOKEVIRTUAL StringBuilder.toString`.
- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks`, implement `EPipe` in `emitExpr`: replace the discard+pushNull stub with an ECall rewrite — `|>` prepends left as first arg; `<|` appends right as last arg — and delegate to `emitExpr`.
- [ ] In `stdlib/kestrel/tools/compiler/codegen-expr.test.ks`, add a test group `"EList empty"` that calls `CG.emitExpr(t.ctx, EList([]))` and asserts opcode `178` (`getstatic`) is at offset 0 (KNil.INSTANCE) and overall bytes are valid.
- [ ] In `stdlib/kestrel/tools/compiler/codegen-expr.test.ks`, add a test group `"EList non-empty"` that calls `CG.emitExpr(t.ctx, EList([LElem(ELit("int","1")), LElem(ELit("int","2"))]))` and asserts bytes are emitted and do not start with `aconstNull` (opcode 1).
- [ ] In `stdlib/kestrel/tools/compiler/codegen-expr.test.ks`, add a test group `"ECons"` that calls `CG.emitExpr(t.ctx, ECons(ELit("int","1"), EList([])))` and asserts the bytecode contains an `invokespecial` (opcode 183) for `KCons.<init>`.
- [ ] In `stdlib/kestrel/tools/compiler/codegen-expr.test.ks`, add a test group `"ETuple real"` that calls `CG.emitExpr(t.ctx, ETuple([ELit("int","10"), ELit("int","20")]))` and asserts the constant pool contains the UTF-8 key "0" (field name for first tuple element).
- [ ] In `stdlib/kestrel/tools/compiler/codegen-expr.test.ks`, add a test group `"ETemplate real"` that calls `CG.emitExpr(t.ctx, ETemplate([TmplLit("x="), TmplExpr(ELit("int","7"))]))` and asserts the constant pool contains the UTF-8 bytes for "StringBuilder" and the bytecode ends (before areturn) with `invokevirtual` (opcode 182) for `toString`.
- [ ] In `stdlib/kestrel/tools/compiler/codegen-expr.test.ks`, add a test group `"EPipe forward"` that calls `CG.emitExpr(t.ctx, EPipe("|>", ELit("int","3"), EIdent("f")))` and asserts bytes are emitted and do not start with `aconstNull` (opcode 1).
- [ ] Run `cd compiler && npm run build && npm test`
- [ ] Run `./scripts/kestrel test`
- [ ] Run `./scripts/run-e2e.sh`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel codegen unit | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | `EList([])` emits `getstatic` for `KNil.INSTANCE` (opcode 178 at offset 0); `EList([e1,e2])` emits real bytecode (not null); `ECons(h,t)` emits `invokespecial KCons.<init>` (opcode 183); `ETuple([e1,e2])` emits `KRecord` with field "0" in the constant pool; `ETemplate([TmplLit,TmplExpr])` emits `StringBuilder` pattern (opcode 182 for `toString`); `EPipe("|>",…)` emits non-null result. |
| Kestrel harness | `tests/unit/lists.test.ks` | Already present — construction, sum, head, nested match, GC stress. Will pass once `EList`/`ECons` are fixed. |
| Kestrel harness | `tests/unit/tuples.test.ks` | Already present — pair access, mixed-type, nested tuples. Will pass once `ETuple` is fixed. |
| Kestrel harness | `tests/unit/pipes.test.ks` | Already present — forward pipe, backward pipe, pipe with multi-arg function. Will pass once `EPipe` is fixed. |
| Conformance runtime | `tests/conformance/runtime/valid/conform_string_interp_println.ks` | Already present — `"hello ${who}"` print. Will pass once `ETemplate` is fixed. |
| Conformance runtime | `tests/conformance/runtime/valid/list_find.ks` | Already present — list literal construction and list-search functions. Will pass once `EList` is fixed. |

## Documentation and specs to update

- [ ] `docs/specs/01-language.md` — No change needed; list expressions, tuples, string templates, and pipe operator semantics are already documented correctly. Verify after implementation that no discrepancy exists between spec and emitted behaviour.
