# Language: `is` Type Narrowing

## Sequence: 18
## Tier: 3 — Complete the core language
## Former ID: 13

## Summary

The `is` keyword is reserved (spec **01 §2.4**) and described for **type narrowing** in conditionals (`if (x is T) { ... }`). Within the **then**-branch, the type of `x` is narrowed to `original_type & T` (spec **06 §4**, **06 §8** narrowing row). Spec **06** also states that `is` checks **structural conformance** (record shape, ADT constructor tag, etc.).

This story specified and implemented **`e is T`** as a full expression (grammar in **01 §3.2**), type narrowing in **`if`** / **`while`**, **`KIND_IS`** and related lowering on VM and JVM, diagnostics, tests, and spec updates.

## Current State

- **Lexer:** `is` in `KEYWORDS` (`compiler/src/lexer/types.ts`).
- **Parser / AST:** `IsExpr` (`expr`, `testedType`); `parseIsExpr` — **`is`** binds tighter than `==` and looser than `&` (`AndExpr` → `IsExpr` → `RelExpr`).
- **Type checker:** `refinementMeetScrutTarget`, record subset meet, union arms, opaque rules; **`if`** / **`while`** narrow **`IdentExpr`** subjects; else branch unrefined; codes `type:narrow_impossible`, `type:narrow_opaque`.
- **Codegen:** VM **`KIND_IS` (0x25)** plus MATCH/EQ/record probes; JVM parity via `KRuntime`.
- **Tests:** Vitest `is-narrowing.test.ts`, parse integration, conformance `narrowing_*.ks`, `tests/unit/narrowing.test.ks`, VM bytecode tests.

## Acceptance Criteria

### Specification and documentation (keep specs consistent with behaviour)

- [x] **01-language.md §3.2:** Expression grammar for **`e is T`**, precedence/associativity, `f() is Int | String` disambiguation, runtime truth summary.
- [x] **01-language.md §3.2 (prose):** §3.2.2 type test — structural conformance aligned with **06 §4**.
- [x] **06-typesystem.md §4 (and §8):** Standalone **`e is T`**, **`while`** narrowing, **else** unrefined; checklist §10 item 9.
- [x] **03-bytecode-format.md** / **04-bytecode-isa.md:** **`KIND_IS` 0x25**, operands, stack effect, discriminant table.
- [x] **05-runtime-model.md:** §1.0 observable rules for **`is`** at runtime; cross-link **04**.
- [x] **08-tests.md §2.2 / §3.5:** Concrete paths for `is` / narrowing / **KIND_IS**.
- [x] **10-compile-diagnostics.md §4:** **`type:narrow_impossible`**, **`type:narrow_opaque`**.
- [x] **06-typesystem.md §10 (Implementor checklist):** Narrowing item added.
- [x] **Kestrel_v1_Language_Specification.md:** Narrowing / `is` aligned with 01/06.

### Implementation

- [x] **Parser + AST:** **`e is T`**; result type **`Bool`**.
- [x] **Type checker:** Narrowing in **`if`** then and **`while`** body; **else** unrefined; standalone **`e is T`**.
- [x] **Refinement validity:** Impossible narrow and opaque rules enforced.
- [x] **Codegen (VM):** Runtime checks per specs.
- [x] **Codegen (JVM):** Same semantics via **`KRuntime`**.

### Tests (exhaustive coverage — required)

- [x] **`compiler/test/integration/parse.test.ts`:** `is` forms and precedence.
- [x] **`compiler/test/unit/typecheck/is-narrowing.test.ts`:** Dedicated narrowing cases.
- [x] **`tests/conformance/typecheck/valid/` and `invalid/`:** `narrowing_*.ks`, **`// EXPECT:`** on invalid.
- [x] **`tests/unit/narrowing.test.ks`:** Runtime boolean and ADT/record/prim cases.
- [x] **VM (`vm/`):** **`zig build test`** includes **`KIND_IS`** bytecode tests.
- [x] **`cd compiler && npm test` and `./scripts/kestrel test`:** Full suites pass.

## Spec References

- **01-language** §2.4, §3.2, §3.6
- **06-typesystem** §1, §4, §8, §10
- **03-bytecode-format**, **04-bytecode-isa**, **05-runtime-model**
- **07-modules** §5.3
- **08-tests** §2.2, §3.5
- **10-compile-diagnostics** §4

## Dependencies (for downstream)

- Sequence **19** (union/intersection runtime) — union narrowing coordinates with this work.

## Tasks

- [x] Parser, AST, typecheck, diagnostics for `is`
- [x] VM + JVM codegen and runtime probes
- [x] Conformance + Vitest + `narrowing.test.ks` + VM bytecode tests
- [x] Update normative specs (01, 03, 04, 05, 06, 08, 10) and `Kestrel_v1_*`
- [x] Run `npm run build`, `npm test`, `./scripts/kestrel test`, `zig build test`, `./scripts/run-e2e.sh`
