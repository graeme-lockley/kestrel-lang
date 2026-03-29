# JSON in Kestrel: pure parse/stringify, Result + error ADT, retire Value builtins

## Sequence: 64
## Tier: 7 — Large cross-cutting (stdlib + compiler + VM + specs)
## Former ID: 31

## Summary

Reimplement `kestrel:json` entirely in Kestrel: `parse` returns `Result` with a dedicated parse-error ADT (plus `errorAsString` and `parseOrNull`). Remove `__json_parse`, `__json_stringify`, and the built-in `Value` type from the language/runtime; expose JSON value constructors and predicates from `kestrel:json` only. Delete `kestrel:value`. Add a thorough `json.test.ks` corpus (boundaries, invalid input, escapes, numbers, UTF-8, nesting).

## Current State

- `stdlib/kestrel/json.ks` wraps `__json_parse` / `__json_stringify`; failed parse is indistinguishable from JSON `null` (same `Null` tag).
- `stdlib/kestrel/value.ks` exports `isNull`, `isBool`, etc. on the built-in `Value` ADT (constructors are prelude/injected, not ordinary stdlib ADT exports).
- Compiler prelude (`check.ts`) registers `Value` constructors, `__json_parse`, `__json_stringify`; `compiler/src/types/from-ast.ts` maps the type name `Value` to the builtin app type without an import.
- VM bytecode uses `CALL` ids `0xFFFFFF05` / `0xFFFFFF06` (`exec.zig`); `primitives.zig` implements `jsonParse` / `jsonStringify` and builds the builtin `Value` ADT (including object stub: empty payload).
- JVM backend (`compiler/src/jvm-codegen/codegen.ts`) lowers `__json_*` to `KRuntime.jsonParse` / `jsonStringify`; JSON values use the `KValue` / `KV*` class hierarchy in `runtime/jvm/src/kestrel/runtime/` (separate from `KRuntime.isValueKind`, which is for **`e is T`** / `KIND_IS` discriminants, not the JSON ADT).
- `docs/specs/02-stdlib.md` documents current behaviour and the null/failure conflation; `docs/specs/08-tests.md` and `docs/guide.md` still describe the old `parse` / `stringify` shapes indirectly.

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
- [ ] **Specs and docs listed under “Documentation and specs to update”** are updated so they no longer describe builtin JSON `Value`, `kestrel:value`, `__json_*`, or “parse failure → `Null`”; **01-language** reviewed and updated only if it implies a builtin JSON `Value` (today it does not; integer “Value” prose is unrelated). (`docs/IMPLEMENTATION_PLAN.md` is a retired pointer only — no phased plan to maintain.)
- [ ] Full test pass: `./scripts/kestrel test`, `cd compiler && npm test`, `cd vm && zig build test`, and **`./scripts/run-e2e.sh`** after compiler/VM/stdlib surface changes.

## Spec References

- `docs/specs/02-stdlib.md` — kestrel:json, `Value` / `JsonParseError`, migration from `kestrel:value`
- `docs/specs/04-bytecode-isa.md`, `docs/specs/05-runtime-model.md`, `docs/specs/06-typesystem.md` — remove implication of a **fourth builtin** JSON `Value` ADT row where applicable
- `docs/specs/07-modules.md` — stdlib specifier list consistency with 02
- `docs/specs/08-tests.md` — stdlib test expectations for `kestrel:json`
- `docs/guide.md` — user-facing `kestrel:json` summary (signatures and error model)
- `docs/specs/01-language.md` — only if a builtin JSON `Value` is ever stated (unlikely today)

## Risks / Notes

- **VM value representation:** Today the host may tag JSON values specially. Moving to a pure Kestrel ADT requires the VM to represent that ADT like any other user ADT (constructors, pattern match). Verify GC and equality (`==`) on the new `Value` match expectations.
- **Performance:** Pure Kestrel parser will be slower than native primitives; acceptable for this story unless benchmarks dictate a later hybrid.
- **JVM:** Remove or replace `KRuntime.jsonParse` / `jsonStringify` and the `KValue` / `KV*` JSON tree classes if the backend no longer special-cases JSON; **do not** confuse this with `KRuntime.isValueKind` (used for `KIND_IS` / primitive shape probes — should remain unless the compiler changes that lowering).
- **Compiler / bytecode:** Built-in ADT slot **Value=3** (`ADT_VALUE` in `codegen.ts`, VM `primitives.zig` comments) is wired through prelude constructors, `getConstructor`, `getMatchConfig`, and exhaustive-match logic in `check.ts`. Dropping it means stdlib `Value` / `JsonParseError` use normal per-module ADT indices; confirm `.kbc` ADT tables, `CONSTRUCT` / `CONSTRUCT_IMPORT`, and `MATCH` for cross-module constructors. JVM must emit the same ADT representation as the Zig VM for `kestrel:json` types (no parallel `KV*` layout unless still required for something else).

## Impact analysis

| Area | What changes |
|------|----------------|
| **Stdlib** | Replace `stdlib/kestrel/json.ks` with full parse/stringify + `JsonParseError` + moved `Value` ADT and predicates (from `value.ks`). Delete `stdlib/kestrel/value.ks`. Update `compiler/src/resolve.ts` builtin module list (`kestrel:value` → remove). |
| **Compiler typecheck** | Remove prelude entries: `Null`, `Bool`, `Int`, `Float`, `String`, `Array`, `Object` as `Value` constructors, `__json_parse`, `__json_stringify`. Remove or generalize hard-coded `Value` branches (exhaustive match `requiredSets`, `bindPattern` for `Value`, any `applied.name === 'Value'` paths). Update `compiler/src/types/from-ast.ts` so bare `Value` in type position resolves only via import from `kestrel:json` (or alias), not a magic builtin. |
| **Compiler codegen** | Remove `__json_parse` / `__json_stringify` `emitCall(0xFFFFFF05/06)` branches. Remove built-in `Value` from `getConstructor`, `getMatchConfig`, and ADT init table (`ADT_VALUE`, fourth row in ADT table). Rely on normal ADT emission for stdlib-defined `Value` / `JsonParseError`. |
| **Compiler JVM + Java runtime** | Remove `__json_*` special cases in `jvm-codegen/codegen.ts`. Remove or replace `KRuntime.jsonParse` / `jsonStringify` and `KValue` / `KV*` JSON ADT classes in `runtime/jvm/` if nothing else references them; keep `isValueKind` unless `KIND_IS` lowering changes. Update `runtime/jvm/build.sh` sources list if classes are deleted. |
| **VM** | `exec.zig`: remove dispatch for `0xFFFFFF05` / `0xFFFFFF06`. `primitives.zig`: delete `jsonParse`, `jsonStringify`, `jsonToValue`, `valueToString`, and helpers used only by them (`allocValueAdt` stack). Reconcile comments/constants that assume built-in Value ADT index 3. |
| **Tests** | Rewrite `stdlib/kestrel/json.test.ks` (imports, expectations for errors vs `null`, object behaviour once real parsing lands). Add Vitest/compiler tests if ADT-table or prelude changes break existing suites. |
| **Docs** | Specs and `docs/guide.md` must describe the new API, error model, and absence of JSON host primitives. |
| **Compatibility** | All programs using unqualified `Null`/`Int`/… as JSON constructors today rely on prelude; they must import from `kestrel:json` (or explicit re-exports). Call out migration in spec/release notes if the project publishes them. |

## Tasks

- [ ] **Spec first:** In `docs/specs/02-stdlib.md`, define `JsonParseError` variants, `parse` / `parseOrNull` / `stringify` / `errorAsString` signatures, object key ordering, duplicate-key behaviour, UTF-8 / surrogate policy, and round-trip guarantees. Update `04-bytecode-isa.md`, `05-runtime-model.md`, `06-typesystem.md`, `08-tests.md`, and `docs/guide.md` per **Documentation and specs to update** (and `01-language.md` only if a builtin JSON `Value` appears).
- [ ] **Implement `kestrel:json`:** Add `Value` and `JsonParseError` ADTs, constructors, predicates (`isNull`, …), `parse`, `parseOrNull`, `errorAsString`, `stringify` in Kestrel; split into extra `.ks` only if import cycles require it.
- [ ] **Retire `kestrel:value`:** Delete `stdlib/kestrel/value.ks`; remove from `resolve.ts`; fix all imports (currently `json.test.ks`).
- [ ] **Compiler:** Remove JSON primitives and built-in `Value` from `check.ts` prelude and all `Value`-specific typecheck branches that exist only for the builtin; align `from-ast.ts` with stdlib-only `Value`.
- [ ] **Bytecode codegen:** Remove `__json_*` lowering and built-in `Value` constructor/match wiring (`codegen.ts`: `ADT_VALUE`, `getConstructor`/`getMatchConfig` Value cases, ADT table fourth row).
- [ ] **JVM codegen + runtime:** Remove `__json_*` emission; remove or simplify `KRuntime` / `KValue` JSON helpers and `isValueKind` if tied to removed layout.
- [ ] **VM:** Remove primitive call ids `0xFFFFFF05` / `0xFFFFFF06` and associated Zig JSON implementation; update tests/comments that reference JSON builtins.
- [ ] **Corpus:** Expand `stdlib/kestrel/json.test.ks` per story goals (invalid JSON, escapes, numbers, UTF-8, nesting, `Result`/`Option` behaviour); remove obsolete “parse failure == Null” assertions.
- [ ] **Docs:** Update `docs/guide.md` and every file under **Documentation and specs to update**. Grep repo for `__json_`, `kestrel:value`, `ADT_VALUE`, `FFFFFF05`, `jsonParse`, `jsonStringify`, `KValue`, `KVNull` until clean or intentionally documented as removed.
- [ ] **Verification:** `cd compiler && npm run build && npm test`; `./scripts/kestrel test`; `cd vm && zig build test`; `./scripts/run-e2e.sh` (required for this story’s compiler/VM/stdlib/JVM touch set).

## Tests to add

### `stdlib/kestrel/json.test.ks` (primary corpus)

- **`parse` / `Result`:** `Ok` for valid `null`, `true`, `false`, integers, floats, strings, arrays; **`Err` for invalid input** — never conflated with JSON `null`. Assert error variants match spec for: empty input, whitespace-only (define per spec), truncated (`{`, `[`, `"ab`), garbage after a complete value, bad tokens, wrong keyword spellings (`tru`, `nul`), trailing commas, missing `:` / `,` / `}` / `]`.
- **`parseOrNull`:** `Some` iff `Ok`; `None` iff `Err` for the same inputs as above (spot-check matrix).
- **`errorAsString`:** Non-empty, stable messages for tests; **at least one assertion per `JsonParseError` variant** (and a match that forces exhaustiveness if the language/test style allows).
- **`stringify`:** Required JSON escaping for `"`, `\`, control characters; Unicode as per spec; **key ordering** and **duplicate-key** behaviour exactly as documented in 02.
- **Round-trip:** `stringify` then `parse` → `Ok` and structurally equal `Value` for: scalars, nested arrays, strings containing escapes and UTF-8 multibyte code points; **objects** with non-empty entries once object parse/stringify is real (replace current stub expectations).
- **Numbers:** Per 02 / spec decisions: integer vs float boundaries, `-0`, scientific notation, rejection of `NaN` / `Infinity`, leading zeros, overflow / huge literals if policy is defined.
- **Strings / Unicode:** `\n`, `\t`, `\"`, `\\`, `\uXXXX`, incomplete `\u`, lone surrogates / non-BMP policy as specified.
- **Scale / limits:** If implementation caps nesting depth or string length, tests for at/beyond limit; if no caps, a sanity test for moderately deep nesting and long string (keep CI-friendly).

### Compiler (Vitest)

- Grep `compiler/test` for assumptions about prelude `Value` constructors or `__json_*`; update or replace.
- **Regression:** Compiling `stdlib/kestrel/json.ks` (and `json.test.ks`) through the normal pipeline succeeds; optional focused test that **`Value` in type position without import is rejected** (or resolves only via `kestrel:json`), matching the new rules.
- **Integration:** If bytecode or `.kti` tests assert a fixed builtin ADT row count, update for removal of builtin `Value=3`.

### VM (`zig build test`)

- Green after removing `0xFFFFFF05` / `0xFFFFFF06` dispatch and JSON helpers in `primitives.zig`; adjust any VM tests or comments that mention JSON builtins or “Value=3” host layout.

### JVM backend / runtime

- No dedicated Vitest coverage for `__json_*` today; after removal, run **`./scripts/run-e2e.sh`** and any JVM smoke path the project uses. Add a minimal compiler/JVM integration test **only if** a new JSON-specific code path remains.

### E2E

- **`./scripts/run-e2e.sh`** required when promoting to **done** (see Acceptance criteria), not conditional on fixtures importing `kestrel:json`.

## Documentation and specs to update

Every item below should be **edited or explicitly reviewed** so the tree matches the post-change implementation (no stale builtin JSON / `kestrel:value` / `__json_*` narrative).

| Doc | What to change |
|-----|----------------|
| `docs/specs/02-stdlib.md` | `kestrel:json` exports (`parse`, `parseOrNull`, `stringify`, `errorAsString`, `Value`, `JsonParseError`, predicates); remove `kestrel:value`; remove “parse failure → `Null`”; object semantics; migration note for prelude `Null`/`Int`/… as JSON constructors. |
| `docs/specs/04-bytecode-isa.md` | §1.7 and similar prose that lists **Value** next to Option/Result/List as if a **builtin** ADT; clarify stdlib-defined JSON `Value` uses normal `CONSTRUCT` / `CONSTRUCT_IMPORT`. (JSON-specific `CALL` ids **`0xFFFFFF05` / `06` are not currently in this spec** — if documented elsewhere, remove; otherwise no ISA table row to delete.) |
| `docs/specs/05-runtime-model.md` | ADT bullet that groups **Value** with List/Option/Result as a fixed builtin row; point JSON values at ordinary ADT heap objects from `kestrel:json`. |
| `docs/specs/06-typesystem.md` | Prelude / constraint bullets that treat **Value** like a fourth builtin alongside Option/Result/List; state JSON `Value` is imported from `kestrel:json`. |
| `docs/specs/07-modules.md` | Stdlib specifier list / contract bullets: align with 02 (`kestrel:json` only; no `kestrel:value`). |
| `docs/specs/08-tests.md` | §2.7 and any bullets that describe `parse`/`stringify` signatures or parse-failure behaviour; ensure `json.test.ks` expectations match the new API. |
| `docs/guide.md` | User-facing `kestrel:json` summary (signatures and error model). |

## Notes

- **Object support:** Today the VM JSON path stubs empty objects; pure Kestrel implementation should define real object parse/stringify and update tests that currently expect `{}` for `{"a":1}`.
- **Constructor names:** Global prelude currently exposes `Null`, `Bool`, … as `Value` constructors; moving them into `kestrel:json` avoids shadowing but requires explicit imports — document in spec.
- **Optional follow-up:** Performance benchmarking or a hybrid native accelerator is out of scope unless acceptance criteria expand.

## Build notes

- 2026-03-29: Moved from **planned** to **doing** after planned-phase review: expanded **Current state**, **Impact analysis**, **Risks**, **Acceptance criteria**, **Spec references**, **Tests to add**, and **Documentation and specs to update** to match repo reality (`from-ast.ts`, JVM `KValue`/`KRuntime`, spec locations, exhaustive test/doc matrices). Planned exit criteria in `docs/kanban/README.md` satisfied for this story.
