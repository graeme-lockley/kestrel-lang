# Self-hosted codegen: `EList`, `ECons`, `ETuple`, `ETemplate`, and `EPipe`

## Sequence: S17-29
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-28, S17-30 through S17-38, S17-42

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
- **Blocks**: S17-42 (E2E). List literals and string templates are ubiquitous in Kestrel.

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
