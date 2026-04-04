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

- [ ] Add `ARRAY` heap object support to the JVM runtime — contiguous element storage, length, capacity.
- [ ] Define JVM runtime primitives or instructions for array operations:
  - `arrayNew(capacity)` or `arrayFrom(list)` — create an array.
  - `arrayGet(arr, index)` — O(1) index access; out-of-bounds throws.
  - `arraySet(arr, index, value)` — O(1) mutation.
  - `arrayLength(arr)` — return length.
  - `arrayPush(arr, value)` — append (may grow).
- [ ] Compiler JVM codegen for `Array<T>` usage.
- [ ] Kestrel test: create array, read, write, iterate.

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

- [ ] Create `runtime/jvm/src/kestrel/runtime/KArray.java` — concrete class with `public Object[] elements`, `public int length`, `public int capacity` fields; constructor `KArray(int capacity)`.
- [ ] Add 6 static methods to `KRuntime.java`: `arrayNew(Object)`, `arrayFrom(Object)`, `arrayGet(Object, Object)`, `arraySet(Object, Object, Object)`, `arrayLength(Object)`, `arrayPush(Object, Object)`. Add KArray formatting branch in `formatOne`.
- [ ] Add `if (t.kind === 'AppType' && t.name === 'Array') return 'Lkestrel/runtime/KArray;';` in `externReturnDescriptorForType` in `compiler/src/jvm-codegen/codegen.ts`.
- [ ] Create `stdlib/kestrel/array.ks` with `export extern fun` declarations for all 6 operations.
- [ ] Create `tests/conformance/runtime/valid/array_basic.ks` — create array (arrayNew), push elements, read back with arrayGet, check arrayLength, mutate with arraySet; verify stdout matches expected header comments.
- [ ] Create `tests/conformance/runtime/valid/array_from_list.ks` — use `arrayFrom` to convert a list, verify length and elements via arrayGet.
- [ ] Rebuild JVM runtime: `cd runtime/jvm && bash build.sh`.
- [ ] Run `cd compiler && npm run build && npm test`.
- [ ] Run `./scripts/kestrel test`.
- [ ] Run `./scripts/run-e2e.sh`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Conformance runtime | `tests/conformance/runtime/valid/array_basic.ks` | `arrayNew` + `arrayPush` × 3, `arrayLength` == 3, `arrayGet` at 0/1/2, `arraySet` then re-get. |
| Conformance runtime | `tests/conformance/runtime/valid/array_from_list.ks` | `arrayFrom([10, 20, 30])`, length == 3, elements match. |

## Documentation and specs to update

- [ ] `docs/specs/06-typesystem.md` §1 — add a sentence confirming `Array<T>` is fully implemented via `KArray` runtime class and accessible through `kestrel:array` stdlib; operations are `arrayNew`, `arrayFrom`, `arrayGet`, `arraySet`, `arrayLength`, `arrayPush`.
- [ ] `docs/specs/02-stdlib.md` — add a `kestrel:array` section listing the 6 exported operations with signatures and semantics.
