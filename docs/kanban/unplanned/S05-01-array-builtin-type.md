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

- [ ] Add `KRuntime.java` static helpers: `arrayListNew`, `arrayListCopy`, `arrayListGet`, `arrayListSet`, `arrayListAdd`, `arrayListSize`, `arrayListFromList`, `arrayListToList`.
- [ ] Create `stdlib/kestrel/array.ks` with `extern type JArrayList`, all `jarrXxx` extern fun bindings, `opaque type Array<T> = JArrayList`, and exported functions: `new`, `get`, `set`, `push`, `length`, `fromList`, `toList`.
- [ ] `get` is O(1) indexed access; out-of-bounds throws `IndexOutOfBoundsException` at the JVM level.
- [ ] `set` and `push` mutate in place and return `Unit`.
- [ ] `length` returns `Int`.
- [ ] `fromList` converts a Kestrel `List<T>` to an `Array<T>` preserving order.
- [ ] `toList` converts an `Array<T>` back to a `List<T>` preserving order.
- [ ] Create `stdlib/kestrel/array.test.ks` with tests: create array, push elements, get/set by index, length, fromList/toList round-trip, iterate via toList.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.
- [ ] Update `docs/specs/01-language.md §3.6` to document `Array<T>` as an ArrayList-backed mutable type.
- [ ] Remove or update any references to a custom `ARRAY` heap kind in `docs/specs/`.

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
