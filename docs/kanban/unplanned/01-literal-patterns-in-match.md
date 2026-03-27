# Literal Patterns in Match (Int, Float, String, Char, Unit)

## Sequence: 01
## Tier: 1 — Fix broken language
## Former ID: 85

## Summary

Integer and string literal patterns in `match` are parsed into `LiteralPattern` nodes, but the type checker does not type-check them and the Zig VM bytecode path does not emit comparisons, so they do not work at runtime. This story scope includes **Char**, **Float**, and **Unit** literal patterns as additional primitive literal forms that should behave like other primitive literal patterns (scrutinee unification + constant load + `EQ` in codegen). **Bool** patterns use `True` / `False` as constructor patterns and the existing `MATCH` jump table; they are already supported and stay out of scope here except where AST overlap requires cleanup.

## Current State

Verified against the tree at the time of this story update:

- **Parser** — [`compiler/src/parser/parse.ts`](../../../compiler/src/parser/parse.ts) `parsePatternPrimary` (approx. lines 1182–1185): accepts **`int` and `string`** tokens only and builds `LiteralPattern`. **`char` / `float` tokens and unit `()` are not handled** in pattern position today: they fall through to the error/recovery path and do not produce a primitive literal pattern.
- **AST** — [`compiler/src/ast/nodes.ts`](../../../compiler/src/ast/nodes.ts) `LiteralPattern`: `literal` is `'int' | 'string' | 'true' | 'false'` (approx. lines 391–395). There is **no `'char'`, `'float'`, or `'unit'`** variant yet. The `'true' | 'false'` variants are unused by the parser for patterns: `True` / `False` are parsed as `ConstructorPattern` (same file / `parsePatternPrimary` approx. lines 1173–1180).
- **Type checker** — [`compiler/src/typecheck/check.ts`](../../../compiler/src/typecheck/check.ts): inner `bindPattern` (inside `MatchExpr`, approx. lines 790–848) has **no branch for `LiteralPattern`**; literal cases add no constraints and produce no bindings, so scrutinee/literal type mismatches are not reported. **`checkExhaustive`** (approx. lines 400–451) only enforces constructor coverage for **ADT** (`kind === 'app'`) scrutinees; it **does not** treat primitive scrutinees (`Int`, `Float`, `String`, `Char`, `Unit`) with literal cases as requiring a catch-all.
- **Codegen (Zig VM / `.kbc`)** — [`compiler/src/codegen/codegen.ts`](../../../compiler/src/codegen/codegen.ts) `MatchExpr` (approx. lines 1485–1631): ADT/list matches use `MATCH` and a jump table when `hasAdtPatterns && config`. Otherwise the **fallback** only meaningfully handles a **single** leading `VarPattern` or `TuplePattern` on the scrutinee; **`LiteralPattern` is not handled**, and multiple literal arms are not compiled as a compare chain.
- **Codegen (JVM)** — [`compiler/src/jvm-codegen/codegen.ts`](../../../compiler/src/jvm-codegen/codegen.ts) `MatchExpr` (approx. lines 1206–1399): handles list/constructor/cons/var/wildcard cases in a loop; **no `LiteralPattern` arm** for `match` (literal comparison exists for **catch** blocks only, approx. lines 1707+). JVM and VM bytecode should be updated together so both targets behave consistently.

## Design Notes

- ADT patterns: `MATCH` + jump table by constructor tag.
- Primitive literal patterns (Int, Float, String, Char, Unit): sequential **compare chain** — load scrutinee, load constant, `EQ`, `JUMP_IF_FALSE` to the next case; on success run the arm body then jump to the common end. Reuse the same constant-pool / `ConstTag` paths as scalar literals (see `literalToConstant` in codegen for expressions).
- A single `match` may not mix **incompatible** strategies on the same scrutinee in a useful way; the type checker should reject scrutinee/literal mismatches. (Mixing only literal + `_` / variable on the same primitive scrutinee is the intended shape.)
- **Exhaustiveness:** For scrutinee types with **large or infinite** domains (`Int`, `Float`, `String`, `Char`), any match that includes **at least one** literal pattern must include a **catch-all** (`_` or a variable pattern) so the match is exhaustive. `Unit` is a singleton domain and is exhaustive if `()` is matched.

## Acceptance Criteria

### Type checker

- [ ] `bindPattern` for `LiteralPattern`: unify scrutinee with `Int` / `Float` / `String` / `Char` / `Unit` according to `pattern.literal`; diagnose when unification fails.
- [ ] `checkExhaustive`: when the scrutinee is (after `apply`) a **primitive** `Int`, `Float`, `String`, or `Char`, if **any** case uses `LiteralPattern`, require a catch-all (`WildcardPattern` or `VarPattern`) somewhere in the case list; otherwise emit a non-exhaustive match error (reuse or extend `CODES.type.non_exhaustive_match` with a clear message).
- [ ] `checkExhaustive`: when scrutinee is `Unit`, `match (u) { () => ... }` is exhaustive; if literal-pattern matching on `Unit` omits `()` and has no catch-all, report non-exhaustive.

### Parser and AST

- [ ] Extend `LiteralPattern` / parser so **char**, **float**, and **unit `()`** literals in pattern position produce `LiteralPattern` with `literal: 'char' | 'float' | 'unit'` (and align [01-language.md](../../specs/01-language.md) `NonConsPattern` accordingly, including `FLOAT` and `Unit`).

### Codegen

- [ ] Zig VM path: for matches whose arms include primitive literal patterns (and no conflicting ADT-only strategy), emit the compare chain described above; support `_` and variable patterns as catch-alls (variable binds the scrutinee value like today’s fallback).
- [ ] JVM path: add `LiteralPattern` handling to `MatchExpr` consistent with the VM semantics (equality on boxed/unboxed values as appropriate for the JVM lowering).

### Specs (must be updated to match behaviour)

- [ ] [docs/specs/01-language.md](../../specs/01-language.md) — pattern grammar (`NonConsPattern`): primitive literal patterns include `INTEGER`, `FLOAT`, `STRING`, `CHAR_LITERAL`, and `Unit` (`()`); update §3.2 narrative accordingly.
- [ ] [docs/specs/06-typesystem.md](../../specs/06-typesystem.md) — §5 exhaustiveness for primitive literal matches (`Int`, `Float`, `String`, `Char`, `Unit` singleton semantics); §8 pattern typing for all primitive literal patterns.
- [ ] [docs/specs/04-bytecode-isa.md](../../specs/04-bytecode-isa.md) — document lowering of primitive literal `match` using `EQ` / `JUMP_IF_FALSE` (not only `MATCH`).
- [ ] [docs/specs/03-bytecode-format.md](../../specs/03-bytecode-format.md) — only if constant tags or examples need to mention literal patterns explicitly (cross-reference 04).
- [ ] [docs/specs/05-runtime-model.md](../../specs/05-runtime-model.md) — brief note that `==` / `EQ` applies to Char, Float, and Unit values in literal-match compare chains (consistent with 01 §3.2.1 deep equality), if not already implied.

### Tests (exhaustive coverage expectation)

**Vitest (compiler)** — add or extend tests under [`compiler/test/`](../../../compiler/test/):

- [ ] **Parser:** `LiteralPattern` for `int`, `float`, `string`, `char`, and `unit` tokens/forms in pattern position (including escaped char literal form if supported).
- [ ] **Typecheck / bindPattern:** scrutinee `Int` with `0`; `Float` with `1.5`; `String` with `"a"`; `Char` with `'a'`; `Unit` with `()`. Reject cross-type literal mismatches (e.g. int-on-bool/string/char/float/unit, string-on-int, char-on-int/string, float-on-int/string/char/unit, unit-on-int/string/char/float).
- [ ] **Exhaustiveness:** `match (n: Int) { 0 => 1 }` fails and with catch-all passes; same for `Float`, `String`, and `Char`. `match (u: Unit) { () => 1 }` passes without catch-all.
- [ ] **Regression:** existing ADT/list/bool matches and [`compiler/test/unit/typecheck/exhaustiveness-async-throw.test.ts`](../../../compiler/test/unit/typecheck/exhaustiveness-async-throw.test.ts) scenarios still pass.

**Kestrel runtime** — [`tests/unit/match.test.ks`](../../../tests/unit/match.test.ks):

- [ ] Int: `match (n) { 0 => ...; 1 => ...; _ => ... }` — correct branch for several values.
- [ ] Float: `match (x) { 1.5 => ...; 2.0 => ...; _ => ... }`.
- [ ] String: `match (s) { "a" => ...; "b" => ...; _ => ... }`.
- [ ] Char: `match (c) { 'a' => ...; 'b' => ...; _ => ... }` (or `\u{...}` if used).
- [ ] Unit: `match (u) { () => ... }` (and optional fallback case variant).
- [ ] Catch-all binding: literal arms plus `x =>` uses scrutinee value correctly.

**Conformance (optional but recommended)** — under [`tests/conformance/typecheck/`](../../../tests/conformance/typecheck/):

- [ ] `invalid/`: non-exhaustive primitive literal match (`Int`/`Float`/`String`/`Char`); literal pattern wrong scrutinee type.
- [ ] `valid/`: minimal well-typed programs using Int / Float / String / Char literal matches with catch-all and Unit literal match on `()`.

**Repository checks** (per [AGENTS.md](../../../AGENTS.md)):

- [ ] [`./scripts/kestrel test`](../../../scripts/kestrel) (or targeted files), `cd compiler && npm test`, `cd vm && zig build test` pass after implementation.

## Spec References (starting point)

- 01-language §3.2 — `MatchExpr`, `Pattern` / `NonConsPattern` (INTEGER, FLOAT, STRING, CHAR_LITERAL, Unit)
- 06-typesystem §5 — Match exhaustiveness (extend for primitive domains)
- 06-typesystem §8 — Pattern typing (literal patterns vs scrutinee)
- 04-bytecode-isa — `MATCH`, `EQ`, `JUMP_IF_FALSE`, match lowering
- 03-bytecode-format — constant pool tags (Int, Float, String, Char, Unit, …) as used by literal loads
