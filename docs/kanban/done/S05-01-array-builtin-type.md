# Array<T> Built-in Type

## Sequence: S05-01
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: 24

## Epic

- Epic: [E05 Core Language Ergonomics](../epics/unplanned/E05-core-language-ergonomics.md)
- Companion stories: S05-02

## Summary

`Array<T>` is a mutable, O(1)-indexed sequence type backed by `java.util.ArrayList`. It is implemented entirely through `extern type`/`extern fun` bindings and `KRuntime` static helpers — the same pattern established by `kestrel:dict` over `java.util.HashMap` in E02. No new JVM instructions or runtime heap-object kinds are required.

## Current State

- Type system: `Array<T>` is parsed as an `AppType` with name `"Array"` but has no typecheck or codegen backing.
- JVM runtime: no `arrayList*` static helpers exist in `KRuntime.java`.
- No `stdlib/kestrel/array.ks` module exists.
- `docs/specs/01-language.md §3.6` and `docs/specs/05-runtime-model §2` still describe an unimplemented custom `ARRAY` heap kind; these references must be updated to reflect the ArrayList strategy.

## Design

`Array<T>` is backed by `java.util.ArrayList<Object>` at runtime, exposed through `KRuntime` static helpers. The public Kestrel module hides all JVM details behind an `opaque type`:

```kestrel
// stdlib/kestrel/array.ks

import * as List from "kestrel:list"

extern type JArrayList = jvm("java.util.ArrayList")

extern fun jarrNew(): JArrayList =
  jvm("kestrel.runtime.KRuntime#arrayListNew()")

extern fun jarrCopy(arr: JArrayList): JArrayList =
  jvm("kestrel.runtime.KRuntime#arrayListCopy(java.lang.Object)")

extern fun jarrGet<T>(arr: JArrayList, index: Int): T =
  jvm("kestrel.runtime.KRuntime#arrayListGet(java.lang.Object,java.lang.Object)")

extern fun jarrSet<T>(arr: JArrayList, index: Int, value: T): Unit =
  jvm("kestrel.runtime.KRuntime#arrayListSet(java.lang.Object,java.lang.Object,java.lang.Object)")

extern fun jarrPush<T>(arr: JArrayList, value: T): Unit =
  jvm("kestrel.runtime.KRuntime#arrayListAdd(java.lang.Object,java.lang.Object)")

extern fun jarrLength(arr: JArrayList): Int =
  jvm("kestrel.runtime.KRuntime#arrayListSize(java.lang.Object)")

extern fun jarrFromList<T>(list: List<T>): JArrayList =
  jvm("kestrel.runtime.KRuntime#arrayListFromList(java.lang.Object)")

extern fun jarrToList<T>(arr: JArrayList): List<T> =
  jvm("kestrel.runtime.KRuntime#arrayListToList(java.lang.Object)")

opaque type Array<T> = JArrayList

export fun new<T>(): Array<T> = jarrNew()
export fun get<T>(arr: Array<T>, index: Int): T = jarrGet(arr, index)
export fun set<T>(arr: Array<T>, index: Int, value: T): Unit = jarrSet(arr, index, value)
export fun push<T>(arr: Array<T>, value: T): Unit = jarrPush(arr, value)
export fun length<T>(arr: Array<T>): Int = jarrLength(arr)
export fun fromList<T>(list: List<T>): Array<T> = jarrFromList(list)
export fun toList<T>(arr: Array<T>): List<T> = jarrToList(arr)
```

**`Array<T>` is mutable**: `set` and `push` mutate in place. The public API does not copy on write (unlike `Dict`). This matches the expected semantics of a mutable array and avoids the O(n) copy overhead that would be unacceptable for an O(1) mutation type.

**`KRuntime` static helpers** (to add to `KRuntime.java`):

```java
// ── ArrayList helpers for kestrel:array ──────────────────────────────────────

public static ArrayList<Object> arrayListNew() {
    return new ArrayList<>();
}

public static ArrayList<Object> arrayListCopy(Object arrObj) {
    return new ArrayList<>((ArrayList<Object>) arrObj);
}

public static Object arrayListGet(Object arrObj, Object indexObj) {
    return ((ArrayList<Object>) arrObj).get(((Long) indexObj).intValue());
}

public static void arrayListSet(Object arrObj, Object indexObj, Object value) {
    ((ArrayList<Object>) arrObj).set(((Long) indexObj).intValue(), value);
}

public static void arrayListAdd(Object arrObj, Object value) {
    ((ArrayList<Object>) arrObj).add(value);
}

public static Long arrayListSize(Object arrObj) {
    return (long) ((ArrayList<Object>) arrObj).size();
}

public static ArrayList<Object> arrayListFromList(Object listObj) {
    ArrayList<Object> result = new ArrayList<>();
    Object node = listObj;
    while (node instanceof KList) {
        result.add(((KList) node).head);
        node = ((KList) node).tail;
    }
    return result;
}

public static KList arrayListToList(Object arrObj) {
    ArrayList<Object> arr = (ArrayList<Object>) arrObj;
    Object result = KNil.INSTANCE;
    for (int i = arr.size() - 1; i >= 0; i--) {
        result = new KList(arr.get(i), result);
    }
    return (KList) result;
}
```

Note: `arrayListSet` and `arrayListAdd` return `void` (not their natural Java return types). `ArrayList.set()` returns the displaced element (discarded); `ArrayList.add()` returns `boolean` (discarded). Both helpers return `void` to match the Kestrel `Unit` return.

## Acceptance Criteria

- [x] Add `KRuntime.java` static helpers: `arrayListNew`, `arrayListCopy`, `arrayListGet`, `arrayListSet`, `arrayListAdd`, `arrayListSize`, `arrayListFromList`, `arrayListToList`.
- [x] Create `stdlib/kestrel/array.ks` with `extern type JArrayList`, all `jarrXxx` extern fun bindings, `opaque type Array<T> = JArrayList`, and exported functions: `new`, `get`, `set`, `push`, `length`, `fromList`, `toList`.
- [x] `get` is O(1) indexed access; out-of-bounds throws `IndexOutOfBoundsException` at the JVM level.
- [x] `set` and `push` mutate in place and return `Unit`.
- [x] `length` returns `Int`.
- [x] `fromList` converts a Kestrel `List<T>` to an `Array<T>` preserving order.
- [x] `toList` converts an `Array<T>` back to a `List<T>` preserving order.
- [x] Create `stdlib/kestrel/array.test.ks` with tests: create array, push elements, get/set by index, length, fromList/toList round-trip, iterate via toList.
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.
- [x] Update `docs/specs/01-language.md §3.6` to document `Array<T>` as an ArrayList-backed mutable type.
- [x] Remove or update any references to a custom `ARRAY` heap kind in `docs/specs/`.

## Dependencies

- Depends on S02-01 (`extern type`), S02-02 (non-parametric `extern fun`), S02-03 (parametric `extern fun`) — all in `done/`.

## Spec References

- `docs/specs/01-language.md §3.6` (Array<T> built-in generic)
- `docs/specs/02-stdlib.md` (new `kestrel:array` module)
- `docs/specs/06-typesystem.md §1` (Array<T> type)

## Risks / Notes

- **`JArrayList` is internal**: callers never see it; `opaque type Array<T> = JArrayList` fully hides the implementation.
- **Index type**: Kestrel `Int` is boxed as `Long` on the JVM. The helper casts `((Long) indexObj).intValue()` before passing to `ArrayList.get/set`. Passing a `Long` directly to `ArrayList.get(int)` would throw `ClassCastException`.
- **Mutation semantics**: unlike `Dict`, `Array` is intentionally mutable in place. `push` and `set` operate on the same array object passed in. Callers requiring snapshot semantics must call `fromList(toList(arr))` or a future `copy()` helper.
- **Spec cleanup**: the spec currently describes an unimplemented ARRAY heap kind. Update it to reflect the ArrayList strategy rather than inventing a custom runtime type.

## Impact analysis

| Area | Change |
|------|--------|
| `runtime/jvm/src/kestrel/runtime/KRuntime.java` | Add `import java.util.ArrayList;` and 8 static helpers: `arrayListNew`, `arrayListCopy`, `arrayListGet`, `arrayListSet`, `arrayListAdd`, `arrayListSize`, `arrayListFromList`, `arrayListToList`. No changes to existing methods. |
| `stdlib/kestrel/array.ks` | New file. `extern type JArrayList`, 8 `jarrXxx` extern fun bindings, `opaque type Array<T> = JArrayList`, 7 exported functions. |
| `stdlib/kestrel/array.test.ks` | New test file. Exercises all 7 public functions. |
| `docs/specs/01-language.md §3.6` | Update Array<T> note: remove reference to custom ARRAY heap kind; document as ArrayList-backed stdlib type. |
| `docs/specs/02-stdlib.md` | Add `## kestrel:array` section after `## kestrel:dict`. |

## Tasks

- [x] `runtime/jvm/src/kestrel/runtime/KRuntime.java`: add `import java.util.ArrayList;` at the top (with other imports)
- [x] `runtime/jvm/src/kestrel/runtime/KRuntime.java`: add 8 static helpers at the end of the class (after hashMap helpers): `arrayListNew`, `arrayListCopy`, `arrayListGet`, `arrayListSet` (void return), `arrayListAdd` (void return), `arrayListSize` (returns `Long`), `arrayListFromList`, `arrayListToList`
- [x] `cd runtime/jvm && bash build.sh` — verify helpers compile
- [x] Create `stdlib/kestrel/array.ks` with `import * as List from "kestrel:list"`, `extern type JArrayList = jvm("java.util.ArrayList")`, 8 `extern fun jarr*` bindings pointing at `kestrel.runtime.KRuntime#arrayList*(...)`, `opaque type Array<T> = JArrayList`, and exported funs: `new`, `get`, `set`, `push`, `length`, `fromList`, `toList`
- [x] Create `stdlib/kestrel/array.test.ks` with test suite covering: empty new array has length 0, push increments length, get returns pushed value, set mutates in place, fromList/toList round-trip, multiple pushes
- [x] `docs/specs/01-language.md §3.6`: replace the "Array<T> and Task<T> are runtime built-ins" note with text documenting ArrayList backing and reference to stdlib module
- [x] `docs/specs/02-stdlib.md`: add `## kestrel:array` section after `## kestrel:dict`
- [x] `cd compiler && npm run build && npm test`
- [x] `./scripts/kestrel test`
- [x] `./scripts/run-e2e.sh`

## Build notes

- 2026-04-04: Started implementation.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/array.test.ks` | All public API: `new`, `push`, `get`, `set`, `length`, `fromList`, `toList`; empty array length; round-trip |
| Conformance typecheck valid | `tests/conformance/typecheck/valid/array_type.ks` | `Array<Int>` as a type annotation typechecks without error |
| Conformance runtime valid | `tests/conformance/runtime/valid/array_basic.ks` | Create array, push 3 ints, length = 3, get each, set one, verify new value |

## Documentation and specs to update

- [x] `docs/specs/01-language.md §3.6` — reword Array<T> description: `Array<T>` is a mutable, O(1)-indexed sequence backed by `java.util.ArrayList` and exposed as the opaque type `Array<T>` in `kestrel:array`. Remove reference to custom ARRAY heap kind.
- [x] `docs/specs/02-stdlib.md` — add `## kestrel:array` section documenting the opaque `Array<T>` type, mutation semantics, and the 7 exported functions (`new`, `get`, `set`, `push`, `length`, `fromList`, `toList`)

## Build notes

- 2026-04-04: Started implementation.
- 2026-04-04: KRuntime ArrayList helpers initially used `KList` (abstract) as type for `arrayListFromList` iteration; fixed to use `KCons` for instanceof check and `KCons` constructor. `arrayListToList` similarly uses concrete `KCons`/`KNil`.
- 2026-04-04: Added `kestrel:array` to `STDLIB_NAMES` in `compiler/src/resolve.ts` — without this the module resolver returned "Module not found".
- 2026-04-04: Typecheck conformance test `array_type.ks` is self-contained (inline extern type/fun) because the typecheck conformance runner does not resolve module imports.
- 2026-04-04: `array_basic.ks` runtime conformance leading comment uses "Runtime conformance:" prefix to match `isDocOnlyCommentBody` exclusion pattern in `runtime-stdout-goldens.ts`.
- 2026-04-04: All 341 compiler tests and 1070 Kestrel tests pass. E2E: 12 negative + 23 positive scenarios pass.
