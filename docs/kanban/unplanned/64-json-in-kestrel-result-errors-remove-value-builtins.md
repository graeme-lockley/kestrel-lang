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
- [ ] No built-in `Value` type in the typechecker prelude; JSON `Value` is the stdlib ADT from `kestrel:value`’s replacement surface (`kestrel:json`).
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
- When promoting to **`planned/`**, add **Tasks**, **Tests to add**, and **Documentation and specs to update** per `docs/kanban/README.md` (no **Tasks** grid remains in unplanned).
