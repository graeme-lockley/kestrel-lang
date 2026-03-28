# Union and Intersection Types: Full Runtime Support

## Sequence: 14
## Tier: 3 — Complete the core language
## Former ID: 145

## Summary

Union (`A | B`) and intersection (`A & B`) are parsed and represented in the type checker (`InternalType` has `union` and `inter`). **Narrowing** with **`is`** already refines union scrutinees (sequence **13**). This story adds **subtyping** (`unifySubtype`) and **call-site constraint solving** (try symmetric `unify` on arguments, then `unifySubtype` on failure) so members of a union work at parameters, annotations, assignment, and function returns. Values at run time stay **concrete**; there is no heap “union value” tag. **`.kbc`** keeps a **minimal** type blob; **`.kti`** continues to carry `union` / `inter` in **`SerType`**.

## Tasks

- [x] Implement `unifySubtype` and call / `fun_check` arrow handling in `compiler/src/types/unify.ts`
- [x] Wire `unifyWithBlame` (subtype + arrow modes) in `compiler/src/typecheck/check.ts`
- [x] Document `.kbc` erasure vs `.kti` in specs **01, 03, 04, 05, 06, 07, 08**, umbrella doc; **kti-format** / **10-compile-diagnostics** reviewed (no format/code change)
- [x] Tests: `unify.test.ts`, `typecheck-integration.test.ts`, conformance `union_intersection_subtyping.ks` / `union_not_subtype_of_int_param.ks`, `tests/unit/union_intersection.test.ks`
- [x] Comments: `compiler/src/bytecode/write.ts`, `vm/src/vm_bytecode_tests.zig`
- [x] Gates: `npm test` (compiler), `./scripts/kestrel test`, `zig build test`, `./scripts/run-e2e.sh`

## Current State (completed)

- **Type checker:** `unifySubtype` implements union/intersection assignability; **application** uses unify-then-subtype on parameters and unify-then-subtype (with union/inter return var bind) on the call result; **assignment** / **annotated bindings** / **function return** use subtype where applicable; **pipe** uses `arrowMode: 'call'`.
- **`.kbc`:** Placeholder type table unchanged; specs and `writeKbc` comment state normative **erasure** of `|`/`&` in the blob.
- **VM:** No new type tags; header comment documents omission by design.

## Dependencies

- Sequence **13** — **done**.

## Acceptance Criteria

### Specification and documentation

- [x] **01-language.md** — §3.6 note on assignability + link to 06/05
- [x] **06-typesystem.md** — §3 subtyping rules, §8 assignment, §9 **03** row, §10 item 8
- [x] **03-bytecode-format.md** — §6.3 paragraph on union/inter erasure vs `.kti`
- [x] **04-bytecode-isa.md** — short note under `KIND_IS` for union-typed `e`
- [x] **05-runtime-model.md** — static-only `|`/`&`, `.kbc` / `.kti` pointer
- [x] **07-modules.md** — §5 type encoding points to `kti-format` and `.kbc` difference
- [x] **kti-format.md** — reviewed; **SerType** unchanged
- [x] **08-tests.md** — new test paths listed
- [x] **10-compile-diagnostics.md** — reviewed; existing **Cannot unify** / **type:unify** still apply
- [x] **Kestrel_v1_Language_Specification.md** — umbrella bullet updated

### Implementation

- [x] **Unification / subtyping** — `unifySubtype` + call / `fun_check` modes
- [x] **Constraint positions** — calls, pipes, block/top val/var annotations, assign, `FunDecl` return, `FunStmt` check
- [x] **Code generators** — no semantic change required; `.kbc` comment only
- [x] **Cross-module** — `.kti` path unchanged; no new regressions observed

### Tests

- [x] **`compiler/test/unit/typecheck/unify.test.ts`** — `unifySubtype` cases
- [x] **`compiler/test/integration/typecheck-integration.test.ts`** — union param accept / reject
- [x] **`tests/conformance/typecheck/`** — valid + invalid `.ks`
- [x] **`tests/unit/union_intersection.test.ks`**
- [x] **VM** — comment in `vm_bytecode_tests.zig`
- [x] **`types-file.test.ts`** — reviewed; no new cases required for this change
- [x] **Suite gates** — all passed (Mar 2026)

## Spec References

- **01-language** — §3.6 types, §3.2 / **`is`** (with **13**)
- **06-typesystem** — §1, §3–§5, §8–§10
- **03-bytecode-format** — §6.2–§6.3 (type table)
- **04-bytecode-isa** — **`KIND_IS`** and **`is`** lowering
- **05-runtime-model** — value model vs type-level `|` / `&`
- **07-modules** — §5 types / imports
- **kti-format** — **`SerType`**
- **08-tests** — §2.2, §2.4, §3.5
- **10-compile-diagnostics** — type errors

## Relationship to sequence 13

Story **13** delivered **`e is T`**, **`KIND_IS`**, narrowing in **`if` / `while`**, and diagnostics. This story completes **using** union (and intersection where the spec demands) in the **full constraint graph**, and aligns **`.kbc`** / specs with **erasure** at module binary boundaries while **`.kti`** retains rich types.
