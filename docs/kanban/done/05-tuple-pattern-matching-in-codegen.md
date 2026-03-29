# Tuple Pattern Matching in Codegen

## Sequence: 05
## Tier: 1 — Fix broken language
## Former ID: 02

## Summary

Tuple patterns `(p1, p2, p3)` are parsed and typed but may not be fully handled in codegen's match compilation. Since tuples are compiled as records with numeric field names, tuple pattern matching needs to destructure by field index.

## Current State

- Parser handles tuple patterns: `(a, b)` parsed as `TuplePattern`.
- Type checker handles tuple types and patterns.
- Codegen compiles tuple expressions as records with fields named `"0"`, `"1"`, etc.
- Codegen `compilePattern` may not have a specific case for `TuplePattern` -- needs verification.
- `tests/unit/tuples.test.ks` tests tuple creation and field access but not tuple pattern matching in `match`.

## Tasks

- [x] Typecheck: `bindPattern` errors for tuple arity / non-tuple scrutinee; `checkExhaustive` for tuple types; Vitest cases
- [x] Bytecode codegen: full `hasTuplePattern` path with `GET_FIELD`, nested tuples, literals, wildcards, multi-case
- [x] JVM codegen: `TuplePattern` in `MatchExpr` via `KRecord.get`
- [x] `tests/unit/match.test.ks` tuple group + conformance valid/invalid
- [x] Spec updates: 01-language, 04-bytecode-isa, 05-runtime-model, 06-typesystem, 08-tests
- [x] Verify: `npm test` (compiler), `./scripts/kestrel test`, `zig build test` (vm)

## Acceptance Criteria

### Implementation

- [x] Verify codegen handles `TuplePattern` in match cases (destructuring to individual elements).
- [x] If not handled, implement: for `(a, b) => expr`, emit GET_FIELD on the scrutinee record with field indices 0, 1, etc., binding to pattern variables.

### Unit and conformance tests (exhaustive coverage)

Work is not complete until tests cover **runtime behaviour** (Kestrel harness), **type-level rules** (conformance), and **compiler** checks where the codebase already tests lowering.

**Kestrel harness (`./scripts/kestrel test`)**

- [x] Extend **`tests/unit/match.test.ks`** with a dedicated **`tuple patterns`** group that exercises, at minimum:
  - **Simple destructuring:** arity 2 and arity ≥3 (e.g. `(x, y) => …`, `(a, b, c) => …`) on a scrutinee that is a tuple literal and on a scrutinee returned from a function.
  - **Nested tuple patterns:** e.g. `((a, b), c) => …` and at least one deeper nesting consistent with existing tuple tests.
  - **Wildcards:** `(_, y) => …`, multiple `_` in one pattern, and a mix of `_` and bound names.
  - **Literal sub-patterns in tuple slots:** e.g. `(x, "hello") => …` (and optionally other primitive literals per slot) alongside variable slots.
  - **Mixed product types:** tuple scrutinee whose components differ in type (e.g. `Int`, `String`, `Bool`) to ensure binding and codegen agree with typing.
  - **Exhaustiveness with tuple arms:** a `match` where at least one arm is a tuple pattern and remaining coverage is via another tuple pattern or a catch-all (`_` or variable), consistent with the type checker.
- [x] Optionally add or extend **`tests/unit/tuples.test.ks`** only if it keeps tuple-focused tests grouped there; avoid duplicating the same assertions in two files.

**Conformance (`tests/conformance/typecheck/`)**

- [x] Add **`valid`** snippets proving tuple patterns type-check and exhaustive `match` on a tuple type is accepted (including nested tuple patterns where applicable).
- [x] Add **`invalid`** snippets with `// EXPECT:` for: tuple pattern arity ≠ scrutinee tuple arity, tuple pattern against a non-tuple scrutinee, and any other static errors the checker already guarantees for tuple patterns.

**Compiler (Vitest, `cd compiler && npm test`)**

- [x] Add or extend **`compiler/test/`** coverage if the repo already asserts match lowering (e.g. bytecode shape, disassembly snapshots, or JVM backend output). If no such tests exist yet, add **targeted** tests for tuple-pattern arms only—enough to lock in GET_FIELD/index binding behaviour—without broad unrelated codegen refactors.

### Spec updates (required on completion)

Impacted specs must be **read and updated** so documented behaviour matches the implementation and tests.

- [x] **[`docs/specs/01-language.md`](../../specs/01-language.md)** — **§3.2** (`Pattern` / `MatchExpr`): ensure tuple patterns in `match` are described consistently with the grammar (tuple vs grouping). **§3.4** (Tuples): state explicitly that tuple `match` destructuring aligns with the runtime record representation (positional fields `"0"`, `"1"`, …) where that belongs in the narrative.
- [x] **[`docs/specs/04-bytecode-isa.md`](../../specs/04-bytecode-isa.md)** — **§5 (Relation to Language)** (and **§5.1** only if closure/tuple interaction matters): document how **tuple pattern** arms are lowered (e.g. `GET_FIELD` / sequential binding vs `MATCH` for ADT dispatch), so bytecode chapters match codegen.
- [x] **[`docs/specs/05-runtime-model.md`](../../specs/05-runtime-model.md)** — **Tuples / RECORD**: cross-check that positional tuple fields used by pattern destructuring match the runtime model (field order 0, 1, …).
- [x] **[`docs/specs/06-typesystem.md`](../../specs/06-typesystem.md)** — **Pattern matching / tuples:** confirm exhaustiveness and compatibility rules for tuple patterns are stated or cross-linked so they match the checker and the new conformance files.
- [x] **[`docs/specs/08-tests.md`](../../specs/08-tests.md)** — note that **`tests/unit/match.test.ks`** (tuple pattern group) and the new **conformance** cases are part of the expected coverage for tuple `match`.

## Spec References (starting points)

- [`01-language.md`](../../specs/01-language.md) §3.2 — `Pattern` (tuple vs grouping in parentheses)
- [`01-language.md`](../../specs/01-language.md) §3.4 — Tuple literals and tuple patterns
- [`04-bytecode-isa.md`](../../specs/04-bytecode-isa.md) §5 — Records, tuples, and match-related lowering
- [`05-runtime-model.md`](../../specs/05-runtime-model.md) — RECORD / tuple representation
- [`06-typesystem.md`](../../specs/06-typesystem.md) — Tuple types and pattern matching
