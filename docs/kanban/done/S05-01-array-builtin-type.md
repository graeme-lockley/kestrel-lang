# Array<T> Built-in Type

## Sequence: S05-01
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: 24

## Epic

- Epic: [E05 Core Language Ergonomics](../epics/unplanned/E05-core-language-ergonomics.md)
- Companion stories: 64

## Summary

`Array<T>` is specified as a runtime built-in (spec 01 §3.6, 05 §2) -- a mutable, contiguous sequence of values. Lists (immutable linked list via ADT Cons/Nil) are the primary sequence type. Array would provide O(1) indexed access, which List cannot.

## Current State

- Type system: `Array<T>` is parsed as an `AppType` with name "Array".
- JVM runtime: May lack ARRAY heap object kind and dedicated instructions.
- No array creation, indexing, or mutation instructions (unless added elsewhere).
- The spec notes "creation/access impl-defined or stdlib" for ARRAY.

## Acceptance Criteria

- [x] Add `ARRAY` heap object support to the JVM runtime — contiguous element storage, length, capacity.
- [x] Define JVM runtime primitives or instructions for array operations:
  - `arrayNew(capacity)` or `arrayFrom(list)` — create an array.
  - `arrayGet(arr, index)` — O(1) index access; out-of-bounds throws.
  - `arraySet(arr, index, value)` — O(1) mutation.
  - `arrayLength(arr)` — return length.
  - `arrayPush(arr, value)` — append (may grow).
- [x] Compiler JVM codegen for `Array<T>` usage.
- [x] Kestrel test: create array, read, write, iterate.

## Spec References

- 01-language §3.6 (Array<T> built-in generic)
- 05-runtime-model §2 (ARRAY heap kind)
- 06-typesystem §1 (Array<T> type)

## Impact analysis

| Area | Change |
|------|--------|
| JVM runtime (`runtime/jvm/src/kestrel/runtime/`) | New `KArray.java` concrete class: `Object[] elements`, `int length`, `int capacity` fields. |
| JVM runtime `KRuntime.java` | Add 6 static array operation methods (`arrayNew`, `arrayFrom`, `arrayGet`, `arraySet`, `arrayLength`, `arrayPush`) and update `formatOne` to render `KArray` as `Array[e1, e2, ...]`. |
| JVM codegen (`compiler/src/jvm-codegen/codegen.ts`) | Add one line to `externReturnDescriptorForType` mapping `AppType("Array")` → `Lkestrel/runtime/KArray;`. |
| Stdlib (`stdlib/kestrel/array.ks`) | New file: `extern fun` bindings for all 6 runtime operations, each forwarding to the corresponding `KRuntime#array*` static method. |
| Tests | New conformance runtime tests: `array_basic.ks` (create, get, set, length, push) and `array_from_list.ks` (arrayFrom round-trip). |
| Docs | `docs/specs/06-typesystem.md` §1 — note that `Array<T>` is fully implemented; `docs/specs/02-stdlib.md` — add `kestrel:array` module table. Note: `docs/specs/05-runtime-model.md` does not exist; document Array heap object in `06-typesystem.md` §1 instead. |

Compatibility: purely additive — no existing code paths change. Rollback risk: low; `KArray` is a new class, `KRuntime` additions are isolated static methods.

## Tasks

- [x] Create `runtime/jvm/src/kestrel/runtime/KArray.java` — concrete class with `public Object[] elements`, `public int length`, `public int capacity` fields; constructor `KArray(int capacity)`.
- [x] Add 6 static methods to `KRuntime.java`: `arrayNew(Object)`, `arrayFrom(Object)`, `arrayGet(Object, Object)`, `arraySet(Object, Object, Object)`, `arrayLength(Object)`, `arrayPush(Object, Object)`. Add KArray formatting branch in `formatOne`.
- [x] Add `if (t.kind === 'AppType' && t.name === 'Array') return 'Lkestrel/runtime/KArray;';` in `externReturnDescriptorForType` in `compiler/src/jvm-codegen/codegen.ts`.
- [x] Register `kestrel:array` in `compiler/src/resolve.ts` `STDLIB_NAMES`.
- [x] Create `stdlib/kestrel/array.ks` with `export extern fun` declarations for all 6 operations.
- [x] Create `tests/conformance/runtime/valid/array_basic.ks` — create array (arrayNew), push elements, read back with arrayGet, check arrayLength, mutate with arraySet; verify stdout matches expected header comments.
- [x] Create `tests/conformance/runtime/valid/array_from_list.ks` — use `arrayFrom` to convert a list, verify length and elements via arrayGet.
- [x] Update `runtime/jvm/build.sh` to auto-detect Java 21 and add `KArray.java`.
- [x] Update `scripts/kestrel` to use Java 21 when available for running compiled programs.
- [x] Rebuild JVM runtime: `cd runtime/jvm && bash build.sh`.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.
- [x] Run `./scripts/run-e2e.sh`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Conformance runtime | `tests/conformance/runtime/valid/array_basic.ks` | `arrayNew` + `arrayPush` × 3, `arrayLength` == 3, `arrayGet` at 0/1/2, `arraySet` then re-get. |
| Conformance runtime | `tests/conformance/runtime/valid/array_from_list.ks` | `arrayFrom([10, 20, 30])`, length == 3, elements match. |

## Documentation and specs to update

- [x] `docs/specs/06-typesystem.md` §1 — add a sentence confirming `Array<T>` is fully implemented via `KArray` runtime class and accessible through `kestrel:array` stdlib; operations are `arrayNew`, `arrayFrom`, `arrayGet`, `arraySet`, `arrayLength`, `arrayPush`.
- [x] `docs/specs/02-stdlib.md` — add a `kestrel:array` section listing the 6 exported operations with signatures and semantics.

## Build notes

- 2026-04-04: Started implementation.
- 2026-04-04: `()` is not a valid return type in Kestrel extern fun declarations; used `Unit` instead.
- 2026-04-04: Added `kestrel:array` to `STDLIB_NAMES` in `compiler/src/resolve.ts` to enable module resolution.
- 2026-04-04: Updated `build.sh` and `scripts/kestrel` to auto-detect Java 21 since the system `JAVA_HOME` points to Java 17 but the runtime requires Java 21 (virtual threads). Both `./scripts/kestrel test` and `./scripts/run-e2e.sh` pass; `npm test` integration tests that hardcode `java -cp` (runtime-conformance, runtime-stdlib, jvm-async-runtime) remain environment-dependent and fail here due to Java 17 on PATH — these were already failing before this story.
- 2026-04-04: Note: spec 05-runtime-model.md does not exist; Array heap object documented in 06-typesystem.md §1 and 02-stdlib.md instead.
