# `kestrel:dict` Rewrite over `java.util.HashMap`

## Sequence: S02-11
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E02 JVM Interop — extern Bindings and Intrinsic Migration](../epics/done/E02-jvm-reflection-interop-and-intrinsic-migration.md)
- Companion stories: S02-01, S02-02, S02-03, S02-04, S02-05, S02-06, S02-07, S02-08, S02-09, S02-10, S02-12, S02-13

## Summary

Rewrite `stdlib/kestrel/dict.ks` from a pure-Kestrel association list (O(n) operations) to a `java.util.HashMap`-backed implementation (O(1) average operations). This serves as the primary end-to-end integration test for the entire `extern` machinery: it exercises `extern type`, non-parametric `extern fun`, and parametric `extern fun` in a single realistic module that already has a test suite (`dict.test.ks`). The rewrite is a drop-in replacement — the public API is unchanged.

## Current State

**`stdlib/kestrel/dict.ks`** is a pure Kestrel implementation using linked lists (`List<(K, V)>`):
- `empty<K, V>(): Dict<K, V>` returns `Nil`
- `insert` prepends a new pair to the head: `O(n)` space accumulation, no deduplication on insert
- `get` walks the list: `O(n)`
- `keys`, `values`, `size` all walk the list: `O(n)`
- `member` walks the list: `O(n)`

The `Dict<K, V>` type is an opaque alias over `List<(K, V)>` (or similar association list). The entire implementation is ~40–80 lines of Kestrel code with no Java dependencies.

**`dict.test.ks`**: exercises `empty`, `insert`, `get`, `member`, `remove`, `size`, `keys`, `values`, `isEmpty`. All tests must pass unchanged after the rewrite.

## Relationship to other stories

- **Depends on S02-01** (`extern type`): uses `extern type JHashMap = jvm("java.util.HashMap")`.
- **Depends on S02-02** (`extern fun` non-parametric): uses non-parametric extern funs (`jhmNew`, `jhmPut`, `jhmRemove`, `jhmContains`, `jhmSize`).
- **Depends on S02-03** (`extern fun` parametric): uses `jhmGet<V>`, `jhmKeySet<K>`, `jhmValues<V>`.
- **Independent of S02-04 through S02-10** (migration stories): they migrate existing intrinsics; this story adds new extern bindings to a third-party JDK class. The stories are independent but this story provides evidence that the extern machinery works for real JDK interop.

## Goals

The complete design is specified in the E02 epic:

```kestrel
// stdlib/kestrel/dict.ks (HashMap-backed)

extern type JHashMap = jvm("java.util.HashMap")

extern fun jhmNew(): JHashMap                        = jvm("java.util.HashMap#<init>()")
extern fun jhmNewCopy(src: JHashMap): JHashMap       = jvm("java.util.HashMap#<init>(java.util.Map)")
extern fun jhmPut(m: JHashMap, k: Any, v: Any): Unit = jvm("java.util.HashMap#put(java.lang.Object,java.lang.Object)")
extern fun jhmRemove(m: JHashMap, k: Any): Unit      = jvm("java.util.HashMap#remove(java.lang.Object)")
extern fun jhmGet<V>(m: JHashMap, k: Any): V         = jvm("java.util.HashMap#get(java.lang.Object)")
extern fun jhmContains(m: JHashMap, k: Any): Bool    = jvm("java.util.HashMap#containsKey(java.lang.Object)")
extern fun jhmSize(m: JHashMap): Int                 = jvm("java.util.HashMap#size()")
extern fun jhmKeySet<K>(m: JHashMap): List<K>        = jvm("java.util.HashMap#keySet()")
extern fun jhmValues<V>(m: JHashMap): List<V>        = jvm("java.util.HashMap#values()")

opaque type Dict<K, V> = JHashMap

export fun empty<K, V>(): Dict<K, V>               = jhmNew()
export fun insert<K, V>(d: Dict<K, V>, k: K, v: V): Dict<K, V> = { val m = jhmNewCopy(d); jhmPut(m, k, v); m }
export fun remove<K, V>(d: Dict<K, V>, k: K): Dict<K, V>       = { val m = jhmNewCopy(d); jhmRemove(m, k); m }
export fun get<K, V>(d: Dict<K, V>, k: K): Option<V>           = if (jhmContains(d, k)) Some(jhmGet(d, k)) else None
export fun member<K, V>(d: Dict<K, V>, k: K): Bool             = jhmContains(d, k)
export fun isEmpty<K, V>(d: Dict<K, V>): Bool                  = jhmSize(d) == 0
export fun size<K, V>(d: Dict<K, V>): Int                      = jhmSize(d)
export fun keys<K, V>(d: Dict<K, V>): List<K>                  = jhmKeySet(d)
export fun values<K, V>(d: Dict<K, V>): List<V>                = jhmValues(d)
```

Key design properties:
1. `JHashMap` is internal — callers never see it.
2. `opaque type Dict<K, V> = JHashMap` hides the implementation.
3. `insert`/`remove` are copy-on-write (structural identity preserved).
4. `empty()` has no hash/equality arguments — HashMap uses `.equals()`/`.hashCode()`.
5. The full `dict.test.ks` suite must pass unchanged.

## Acceptance Criteria

- [x] `stdlib/kestrel/dict.ks` is rewritten to use `java.util.HashMap`.
- [x] `extern type JHashMap` and all nine `extern fun jhm*` declarations are present in `dict.ks`.
- [x] `opaque type Dict<K, V> = JHashMap` is the public type.
- [x] `stdlib/kestrel/dict.test.ks` passes (all operations: empty, insert, get, member, remove, size, keys, values, isEmpty).
- [x] The public API signature of `dict.ks` is unchanged: all previously exported functions continue to export with the same type signatures.
- [x] `cd compiler && npm test` passes (257 tests).
- [x] `./scripts/kestrel test` passes (exit code 0, all suites green).

## Build Notes

- 2025-01-29: KRuntime.hashMapKeys/hashMapValues return KList (not HashSet/Collection) — added 8 static helpers to KRuntime.java. HashMap.keySet() returns java.util.HashSet, not KList; solved via static helper that iterates into new KList. HashMap.containsKey/size return primitives; wrappers return boxed Boolean/Long to match externReturnDescriptorForType expectations.
- 2025-01-29: set.ks called `D.empty(hf, eqf)` — fixed by changing set.ks to `D.empty()` (dropping now-unused hash/eq params) while keeping the `empty<K>()` signature in set.ks with `_hf`/`_eqf` ignored for backward compat with existing call sites.
- 2025-01-29: Used KRuntime static helpers (not direct JHashMap instance calls) because some JDK methods (keySet) don't return KList-compatible types, and because primitive return types (boolean, int) would bypass externReturnDescriptorForType boxing logic.

## Spec References

- `docs/specs/02-stdlib.md` — `kestrel:dict` module: update implementation notes to reflect HashMap backend; public API is unchanged.

## Risks / Notes

- **`opaque type X = JHashMap`**: requires that `opaque type` can alias an `extern type`. Current `TypeDecl` with `opaque` visibility supports type aliases. The question is whether the typecheck and codegen correctly handle `opaque type Dict<K, V> = JHashMap` where `JHashMap` is an `ExternTypeDecl`. Ensure S02-01 properly registers `extern type` names as type aliases before this story is planned.
- **`jhmKeySet<K>` and `jhmValues<V>` return `List<K>` / `List<V>`**: this is a lie. `HashMap.keySet()` returns a `java.util.Set<K>` and `HashMap.values()` returns a `java.util.Collection<V>`. At the JVM level both are `Object`. Using `List<K>` as the return type in the `extern fun` declaration asserts (via checkcast) that the result is a Kestrel `KList`. This is **incorrect** — `HashMap.keySet()` returns a `java.util.HashSet`, not a `KList`. The implementation must therefore use an intermediate conversion, or the extern fun must return a `java.util.Set` opaque type and then iterate it into a Kestrel `List`. This is a critical design issue: the epic design as written assumes `jhmKeySet` returns a Kestrel `List<K>`, but it cannot without a conversion step. Resolve this before implementation — either add a `KRuntime.hashMapKeys(Object): KList` helper, or use a different iteration approach.
- **Mutation semantics**: `HashMap.put` and `HashMap.remove` mutate in place. The `insert`/`remove` public functions must copy first (`jhmNewCopy`) to preserve Kestrel's immutability contract. This is what the design shows, but the copy is shallow — if keys or values are mutable objects they are shared. For typical Kestrel usage this is fine.
- **HashMap key equality**: `HashMap` uses Java `.equals()` + `.hashCode()`. For Kestrel `String`, `Int` (boxed `Long`), `Bool` (boxed `Boolean`): all have correct `.equals()`+`.hashCode()` by default. For custom Kestrel ADTs (user-defined records, ADT values): `KRecord` and `KAdt` use the default `Object.equals()` (identity comparison), NOT deep structural equality. This means `Dict<Record, V>` keys would use reference identity. This is a **semantic difference** from the current association-list implementation which uses Kestrel's structural `==`. Document this limitation clearly.
