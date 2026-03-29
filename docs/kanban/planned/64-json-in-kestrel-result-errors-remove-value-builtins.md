# JSON in Kestrel: pure parse/stringify, Result + error ADT, retire Value builtins

## Sequence: 64
## Tier: 7 — Large cross-cutting (stdlib + compiler + VM + specs)
## Former ID: 31

## Summary

Reimplement `kestrel:json` entirely in Kestrel: `parse` returns `Result` with a dedicated parse-error ADT (plus `errorAsString` and `parseOrNull`). Remove `__json_parse`, `__json_stringify`, and the built-in `Value` type from the language/runtime; expose JSON value constructors and predicates from `kestrel:json` only. Delete `kestrel:value`. Add a thorough `json.test.ks` corpus (boundaries, invalid input, escapes, numbers, UTF-8, nesting).

## Current State

- `stdlib/kestrel/json.ks` wraps `__json_parse` / `__json_stringify`; failed parse is indistinguishable from JSON `null` (same `Null` tag).
- `stdlib/kestrel/value.ks` exports `isNull`, `isBool`, etc. on the built-in `Value` ADT.
- Compiler prelude (`check.ts`) types `__json_parse` / `__json_stringify`; VM and JVM codegen have dedicated paths for these calls.
- VM implements JSON parse/stringify against the built-in `Value` representation (`primitives.zig` and related).
- `docs/specs/02-stdlib.md` documents current behaviour and the null/failure conflation.

## Relationship to other stories

- None identified beyond normal stdlib/compiler/VM sequencing; if URL/import or lockfile work lands first, ensure `kestrel:json` public surface stays stable for importers.

## Goals

1. **Pure Kestrel implementation** of JSON parsing and stringification (no `__json_*` primitives).
2. **`parse(s: String): Result<Value, JsonParseError>`** where `JsonParseError` is an **exported ADT** (fine-grained variants: e.g. unexpected token, unclosed string/array/object, invalid escape, invalid number, trailing garbage, expected EOF — exact set to be designed in spec).
3. **`errorAsString(e: JsonParseError): String`** for messages / logging / tests.
4. **`parseOrNull(s: String): Option<Value>`** — `Some` on success, `None` on any parse failure (convenience over `Result`).
5. **`stringify(v: Value): String`** implemented in Kestrel (correct escaping, stable key ordering policy documented if objects are ordered maps/lists).
6. **Remove** `__json_parse`, `__json_stringify` from compiler prelude and codegen (VM + JVM).
7. **Remove built-in `Value`** from the language: `Value` becomes a normal library ADT **defined and exported from `kestrel:json`** (or a submodule re-exported there), with constructors and helpers currently living under `kestrel:value` moved here.
8. **Remove `kestrel:value`**: delete `stdlib/kestrel/value.ks`, drop from stdlib resolution list, update every importer to `kestrel:json` (or split file if needed for cycle avoidance — story should resolve in implementation).
9. **Tests:** expand `stdlib/kestrel/json.test.ks` (and any compiler/VM tests if bytecode shapes change) with emphasis on:
   - invalid / truncated JSON, lone surrogates policy (document), empty input, whitespace, trailing commas (reject), duplicate keys (define behaviour), `\u` escapes, control characters, very long strings / deep nesting (stack or explicit limits if added), number boundaries (int vs float policy per language spec), `null` / `true` / `false` spelling mistakes, UTF-8 multibyte in strings.

## Acceptance Criteria

- [ ] `parse` returns `Result<Value, JsonParseError>`; valid `null` is never conflated with a syntax error.
- [ ] `JsonParseError` is an ADT with `errorAsString` covering all variants.
- [ ] `parseOrNull` provided and tested.
- [ ] `stringify` round-trips with `parse` for a documented class of values (or documented intentional non-round-trip cases).
- [ ] No `__json_parse` / `__json_stringify` in compiler, VM, or JVM backend.
- [ ] No built-in `Value` type in the typechecker prelude; JSON `Value` is the stdlib ADT exported from `kestrel:json` (constructors/predicates live there, not in a separate `kestrel:value` module).
- [ ] `kestrel:value` removed; repo has no remaining imports of it.
- [ ] `docs/specs/02-stdlib.md` (and `01-language` if `Value` is mentioned as builtin) updated to match.
- [ ] `docs/IMPLEMENTATION_PLAN.md` or related VM notes updated if they still describe `__json_*` / builtin `Value`.
- [ ] Full test pass: `./scripts/kestrel test`, `compiler npm test`, `zig build test` in `vm/` as applicable after VM cleanup.

## Spec References

- `docs/specs/02-stdlib.md` — kestrel:json, Value / JSON model
- `docs/specs/01-language.md` — if `Value` or JSON literals are referenced as language/builtin

## Risks / Notes

- **VM value representation:** Today the host may tag JSON values specially. Moving to a pure Kestrel ADT requires the VM to represent that ADT like any other user ADT (constructors, pattern match). Verify GC and equality (`==`) on the new `Value` match expectations.
- **Performance:** Pure Kestrel parser will be slower than native primitives; acceptable for this story unless benchmarks dictate a later hybrid.
- **JVM:** Ensure `stringify` / `parse` paths do not rely on removed intrinsics; `KRuntime` JSON helpers may need removal or replacement.
- **Compiler / bytecode:** Built-in ADT slot **Value=3** (`ADT_VALUE` in `codegen.ts`, VM `primitives.zig` comments) is wired through prelude constructors, `getConstructor`, `getMatchConfig`, and exhaustive-match logic in `check.ts`. Dropping it means `Value` / `JsonParseError` use normal module ADT indices; confirm `.kbc` ADT tables, `CONSTRUCT`/`MATCH`, and JVM `isValueKind` / `KValue` stay consistent.

## Impact analysis

| Area | What changes |
|------|----------------|
| **Stdlib** | Replace `stdlib/kestrel/json.ks` with full parse/stringify + `JsonParseError` + moved `Value` ADT and predicates (from `value.ks`). Delete `stdlib/kestrel/value.ks`. Update `compiler/src/resolve.ts` builtin module list (`kestrel:value` → remove). |
| **Compiler typecheck** | Remove prelude entries: `Null`, `Bool`, `Int`, `Float`, `String`, `Array`, `Object` as `Value` constructors, `__json_parse`, `__json_stringify`. Remove or generalize hard-coded `Value` branches (exhaustive match `requiredSets`, `bindPattern` for `Value`, any `applied.name === 'Value'` paths). |
| **Compiler codegen** | Remove `__json_parse` / `__json_stringify` `emitCall(0xFFFFFF05/06)` branches. Remove built-in `Value` from `getConstructor`, `getMatchConfig`, and ADT init table (`ADT_VALUE`, fourth row in ADT table). Rely on normal ADT emission for stdlib-defined `Value` / `JsonParseError`. |
| **Compiler JVM** | Remove `__json_*` special cases in `jvm-codegen/codegen.ts`; remove or dead-code `KRuntime.jsonParse` / `jsonStringify` and any `isValueKind` paths that assume a single global JSON `Value` shape if no longer valid. |
| **VM** | `exec.zig`: remove dispatch for `0xFFFFFF05` / `0xFFFFFF06`. `primitives.zig`: delete `jsonParse`, `jsonStringify`, `jsonToValue`, `valueToString`, and helpers used only by them (`allocValueAdt` stack). Reconcile comments/constants that assume built-in Value ADT index 3. |
| **Tests** | Rewrite `stdlib/kestrel/json.test.ks` (imports, expectations for errors vs `null`, object behaviour once real parsing lands). Add Vitest/compiler tests if ADT-table or prelude changes break existing suites. |
| **Docs** | Specs and `IMPLEMENTATION_PLAN.md` must describe the new API, error model, and absence of JSON host primitives. |
| **Compatibility** | All programs using unqualified `Null`/`Int`/… as JSON constructors today rely on prelude; they must import from `kestrel:json` (or explicit re-exports). Call out migration in spec/release notes if the project publishes them. |

## Tasks

- [ ] **Spec first:** In `docs/specs/02-stdlib.md`, define `JsonParseError` variants, `parse` / `parseOrNull` / `stringify` / `errorAsString` signatures, object key ordering, duplicate-key behaviour, UTF-8 / surrogate policy, and round-trip guarantees. Adjust `01-language.md`, `04-bytecode-isa.md`, `05-runtime-model.md`, `06-typesystem.md` only where they still imply a **built-in** `Value` or JSON primitives (keep generic ADT/MATCH wording accurate).
- [ ] **Implement `kestrel:json`:** Add `Value` and `JsonParseError` ADTs, constructors, predicates (`isNull`, …), `parse`, `parseOrNull`, `errorAsString`, `stringify` in Kestrel; split into extra `.ks` only if import cycles require it.
- [ ] **Retire `kestrel:value`:** Delete `stdlib/kestrel/value.ks`; remove from `resolve.ts`; fix all imports (currently `json.test.ks`).
- [ ] **Compiler:** Remove JSON primitives and built-in `Value` from `check.ts` prelude and all `Value`-specific typecheck branches that exist only for the builtin.
- [ ] **Bytecode codegen:** Remove `__json_*` lowering and built-in `Value` constructor/match wiring (`codegen.ts`: `ADT_VALUE`, `getConstructor`/`getMatchConfig` Value cases, ADT table fourth row).
- [ ] **JVM codegen + runtime:** Remove `__json_*` emission; remove or simplify `KRuntime` / `KValue` JSON helpers and `isValueKind` if tied to removed layout.
- [ ] **VM:** Remove primitive call ids `0xFFFFFF05` / `0xFFFFFF06` and associated Zig JSON implementation; update tests/comments that reference JSON builtins.
- [ ] **Corpus:** Expand `stdlib/kestrel/json.test.ks` per story goals (invalid JSON, escapes, numbers, UTF-8, nesting, `Result`/`Option` behaviour); remove obsolete “parse failure == Null” assertions.
- [ ] **Docs:** Update `docs/IMPLEMENTATION_PLAN.md` (JSON / Value sections). Grep repo for `__json_`, `kestrel:value`, `ADT_VALUE`, `FFFFFF05`.
- [ ] **Verification:** `cd compiler && npm run build && npm test`; `./scripts/kestrel test`; `cd vm && zig build test`; `./scripts/run-e2e.sh` if integration surface changes.

## Tests to add

| Layer | Intent |
|-------|--------|
| **`stdlib/kestrel/json.test.ks`** | `parse` returns `Ok` vs `Err` (never `Err` for valid `null`). `parseOrNull` / `errorAsString` on representative variants. `stringify` + `parse` round-trip for scalars, arrays, strings with escapes; invalid inputs (truncated, bad escape, trailing comma, garbage after value); whitespace; number edge cases per spec; UTF-8 in strings; nesting depth / long string if limits are defined. Object tests updated when object parsing is real (entries preserved, duplicate keys). |
| **`compiler` Vitest** | If any tests assert prelude `Value` constructors or `__json_*`, update or replace. Add regression tests for stdlib `kestrel:json` compiling and exporting expected types if useful. |
| **`vm` `zig build test`** | Green after removing JSON primitive dispatch; add/adjust VM tests if any asserted JSON host behaviour. |
| **E2E** | Run `./scripts/run-e2e.sh` if e2e fixtures import `kestrel:json` or `kestrel:value`. |

## Documentation and specs to update

- `docs/specs/02-stdlib.md` — `kestrel:json` API, `JsonParseError`, remove `kestrel:value`; drop “parse failure returns `Null`” behaviour.
- `docs/specs/04-bytecode-isa.md` — If JSON `CALL` ids are documented anywhere, remove or mark reserved; ensure built-in `CALL` table matches implementation after removal.
- `docs/specs/05-runtime-model.md` — Wording that lists **Value** alongside List/Option/Result as a special builtin ADT row if applicable.
- `docs/specs/06-typesystem.md` — Prelude / constructor bullets that name built-in `Value`.
- `docs/specs/07-modules.md` — Only if `kestrel:value` or module list is enumerated.
- `docs/IMPLEMENTATION_PLAN.md` — JSON primitives and builtin `Value` narrative.

## Notes

- **Object support:** Today the VM JSON path stubs empty objects; pure Kestrel implementation should define real object parse/stringify and update tests that currently expect `{}` for `{"a":1}`.
- **Constructor names:** Global prelude currently exposes `Null`, `Bool`, … as `Value` constructors; moving them into `kestrel:json` avoids shadowing but requires explicit imports — document in spec.
- **Optional follow-up:** Performance benchmarking or a hybrid native accelerator is out of scope unless acceptance criteria expand.
