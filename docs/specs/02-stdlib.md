# 02 – Standard Library Contract

Version: 1.0

---

This document defines the standard library modules that a Kestrel implementation must provide. Implementations may add additional functions or modules beyond this contract; they must not remove or change the signatures listed here.

---

## kestrel:string

String operations. All functions take the string as an explicit argument (no member-call syntax). Strings are UTF-8. **Character** means Unicode code point: `length` returns the number of code points; `slice` and `indexOf` use code-point indices (not byte offsets).

| Function | Signature | Description |
|----------|-----------|-------------|
| `length` | `(String) -> Int` | Character length of string (code-point count) |
| `slice` | `(String, Int, Int) -> String` | Substring from start (inclusive) to end (exclusive); indices are code-point positions |
| `left` | `(String, Int) -> String` | First `n` code points (or whole string if `n` ≥ length); empty if `n` ≤ 0 |
| `right` | `(String, Int) -> String` | Last `n` code points (or whole string if `n` ≥ length); empty if `n` ≤ 0 |
| `dropLeft` | `(String, Int) -> String` | Remove first `n` code points; unchanged if `n` ≤ 0; `""` if `n` ≥ length |
| `dropRight` | `(String, Int) -> String` | Remove last `n` code points; unchanged if `n` ≤ 0; `""` if `n` ≥ length |
| `indexOf` | `(String, String) -> Int` | Code-point index of first occurrence of substring, or -1 |
| `equals` | `(String, String) -> Bool` | Value equality (same UTF-8 / code-point sequence as the `==` operator on two `String` values) |
| `toUpperCase` | `(String) -> String` | Uppercase copy (Basic Latin and Latin extended; other scripts unchanged) |
| `toLowerCase` / `toLower` | `(String) -> String` | Lowercase copy (VM: Basic Latin A–Z; JVM: `Locale.ROOT`) |
| `trim` | `(String) -> String` | Remove leading and trailing ASCII whitespace (space, tab, LF, CR, VT, FF) at code-point boundaries |
| `isEmpty` | `(String) -> Bool` | True when `length(s) == 0` |
| `codePointAt` | `(String, Int) -> Int` | Unicode code point at code-point index `i`, or `-1` if out of range |
| `parseInt` | `(String) -> Int` | Parse signed decimal integer after `trim`; optional leading `-`; malformed or non-digit content yields `0` |
| `split` | `(String, String) -> List<String>` | Split on delimiter string; empty delimiter yields `[s]` |
| `splitWithDelimiters` | `(String, List<String>) -> List<String>` | Split using the first matching delimiter at each step (candidates tried in list order) |
| `join` | `(String, List<String>) -> String` | Concatenate strings with separator between elements |

---

## kestrel:char

Operations on `Char` / `Rune` (one Unicode code point; same type per language spec).

| Function | Signature | Description |
|----------|-----------|-------------|
| `codePoint` | `(Char) -> Int` | Scalar value as a non-negative integer (VM primitive `__char_code_point`) |
| `toCode` | `(Char) -> Int` | Alias for `codePoint` |
| `fromCode` | `(Int) -> Char` | Valid Unicode scalar → `Char`; invalid code point or surrogate → `U+0000` (primitive `__char_from_code`) |
| `isDigit` | `(Char) -> Bool` | True for ASCII digits `0`–`9` (U+0030–U+0039) |
| `isUpper` / `isLower` | `(Char) -> Bool` | ASCII A–Z / a–z |
| `isAlpha` | `(Char) -> Bool` | `isUpper` ∨ `isLower` |
| `isAlphaNum` | `(Char) -> Bool` | `isAlpha` ∨ `isDigit` |
| `isOctDigit` | `(Char) -> Bool` | `0`–`7` |
| `isHexDigit` | `(Char) -> Bool` | Decimal digit or A–F / a–f |
| `toUpper` / `toLower` | `(Char) -> Char` | ASCII case fold only; other code points unchanged |

---

## kestrel:tuple

Helpers for pairs `(A, B)`. **Pipe-friendly:** the tuple is the first argument on `mapFirst` / `mapSecond` / `mapBoth` (so `t \|> mapFirst(f)` desugars to `mapFirst(t, f)`).

| Function | Signature | Description |
|----------|-----------|-------------|
| `pair` | `(A, B) -> (A, B)` | `(a, b)` |
| `first` | `((A, B)) -> A` | `t.0` |
| `second` | `((A, B)) -> B` | `t.1` |
| `mapFirst` | `((A, B), (A) -> X) -> (X, B)` | |
| `mapSecond` | `((A, B), (B) -> Y) -> (A, Y)` | |
| `mapBoth` | `((A, B), (A) -> X, (B) -> Y) -> (X, Y)` | |

---

## kestrel:basics

Numeric, boolean, and general utilities. **Int remainder note:** `%` on `Int` follows floored division semantics in the VM; `remainderBy` and `modBy` use truncated and floored division respectively (see implementation).

| Function | Signature | Description |
|----------|-----------|-------------|
| `identity` | `(A) -> A` | |
| `always` | `(A, B) -> A` | Ignores second argument |
| `clamp` | `(Int, Int, Int) -> Int` | Clamp `n` to `[lo, hi]` |
| `negate` | `(Int) -> Int` | `0 - n` |
| `modBy` | `(Int, Int) -> Int` | Floored modulo: result has sign of divisor |
| `remainderBy` | `(Int, Int) -> Int` | Truncated remainder (sign of dividend) |
| `xor` | `(Bool, Bool) -> Bool` | Exclusive or |
| `not` | `(Bool) -> Bool` | Boolean negation |
| `toFloat` | `(Int) -> Float` | Primitive `__int_to_float` |
| `truncate` | `(Float) -> Int` | Toward zero (`__float_to_int`) |
| `floor` / `ceiling` / `round` | `(Float) -> Int` | `__float_floor` / `__float_ceil` / `__float_round` |
| `abs` | `(Float) -> Float` | `__float_abs` |
| `sqrt` | `(Float) -> Float` | `__float_sqrt` (NaN for negative input) |
| `isNaN` / `isInfinite` | `(Float) -> Bool` | `__float_is_nan` / `__float_is_infinite` |

---

## kestrel:runtime

Canonical **exception ADTs** used by the VM for arithmetic traps (see language spec §Int operations). User code should import these names to `catch` or to annotate types; implementations must not rely on a duplicate `export exception` in the entry module.

| Name | Role |
|------|------|
| `ArithmeticOverflow` | Thrown when a fixed-width `Int` operation overflows (VM-defined width). |
| `DivideByZero` | Thrown for `Int` division or remainder when the divisor is zero. |

---

## kestrel:option

Helpers for `Option<T>`. **Pipe-friendly:** the option is the first argument on `map`, `andThen`, `withDefault`, etc.

| Function | Signature | Description |
|----------|-----------|-------------|
| `getOrElse` | `(Option<A>, A) -> A` | |
| `withDefault` | `(Option<A>, A) -> A` | Alias for `getOrElse` |
| `isNone` / `isSome` | `(Option<A>) -> Bool` | |
| `map` | `(Option<A>, (A) -> B) -> Option<B>` | |
| `andThen` | `(Option<A>, (A) -> Option<B>) -> Option<B>` | |
| `map2`–`map5` | … | Short-circuit on first `None` |

---

## kestrel:list

Immutable list utilities (in addition to list syntax and `List<T>` in §Library types).

| Function | Signature | Description |
|----------|-----------|-------------|
| `length` | `(List<X>) -> Int` | Number of elements |
| `isEmpty` | `(List<X>) -> Bool` | True for `[]` |
| `drop` | `(Int, List<T>) -> List<T>` | Drop first `n` elements (`n <= 0` leaves list unchanged) |
| `map` | `(List<A>, (A) -> B) -> List<B>` | Element-wise map |
| `filter` | `(List<A>, (A) -> Bool) -> List<A>` | Keep elements satisfying predicate |
| `foldl` | `(List<A>, B, (B, A) -> B) -> B` | Left fold |
| `sum` | `(List<Int>) -> Int` | Sum of elements; `[]` yields `0` |
| `reverse` | `(List<T>) -> List<T>` | Reverse element order |
| `append` | `(List<T>, List<T>) -> List<T>` | Concatenate (immutable) |
| `concat` | `(List<List<T>>) -> List<T>` | Flatten one level |
| `foldr` | `(List<A>, B, (A, B) -> B) -> B` | Right fold |
| `intersperse` | `(A, List<A>) -> List<A>` | Insert separator between elements |
| `repeat` | `(Int, A) -> List<A>` | `n` copies of `x` |
| `range` | `(Int, Int) -> List<Int>` | Inclusive `lo`..`hi` |
| `take` / `takeWhile` / `dropWhile` | … | Standard list prefixes / scanning |
| `zip` | `(List<A>, List<B>) -> List<(A, B)>` | Pair elements while both lists non-empty |
| `map2`–`map5` | … | Zipping maps (pairwise / triple / …) |
| `filterMap` | `(List<A>, (A) -> Option<B>) -> List<B>` | Map and drop `None` |
| `concatMap` | `(List<A>, (A) -> List<B>) -> List<B>` | `concat` of `map` |
| `indexedMap` | `(List<A>, (Int, A) -> B) -> List<B>` | Map with index |
| `member` | `(A, List<A>) -> Bool` | True if any element is `==` to the value |
| `any` / `all` | … | Short-circuit predicates |
| `product` | `(List<Int>) -> Int` | Product; `[]` → `1` |
| `maximum` / `minimum` | `(List<Int>) -> Option<Int>` | |
| `partition` | `(List<A>, (A) -> Bool) -> (List<A>, List<A>)` | |
| `unzip` | `(List<(A, B)>) -> (List<A>, List<B>)` | |
| `sort` | `(List<Int>) -> List<Int>` | Insertion sort |
| `head` / `tail` | `List<A> -> Option<…>` | |

---

## kestrel:result

Helpers for `Result<T, E>` (see §Library types). Functions are polymorphic in both type parameters. **Pipe-friendly:** the result is the first argument on transforming functions.

| Function | Signature | Description |
|----------|-----------|-------------|
| `getOrElse` | `(Result<T, E>, T) -> T` | `Ok` payload, or `default` when `Err` |
| `withDefault` | `(Result<T, E>, T) -> T` | Alias for `getOrElse` |
| `isOk` | `(Result<T, E>) -> Bool` | True for `Ok` |
| `isErr` | `(Result<T, E>) -> Bool` | True for `Err` |
| `map` | `(Result<T, E>, (T) -> U) -> Result<U, E>` | |
| `mapError` | `(Result<T, E>, (E) -> F) -> Result<T, F>` | |
| `andThen` | `(Result<T, E>, (T) -> Result<U, E>) -> Result<U, E>` | |
| `map2`–`map5` | … | Same error type `E`; first `Err` wins |
| `toOption` | `(Result<T, E>) -> Option<T>` | `Ok` → `Some`, `Err` → `None` |
| `fromOption` | `(Option<T>, E) -> Result<T, E>` | `None` → `Err(err)` |

---

## kestrel:dict

Finite maps exposed as the **opaque** type `Dict<K, V>`: clients use the functions below only and must not rely on a visible record shape. The implementation still stores a hash function, an equality function, and an association list of `(key, value)` pairs (see [05-runtime-model.md](05-runtime-model.md) for the runtime RECORD layout). **Pipe-friendly:** the dict is the first argument on `insert`, `get`, `map`, etc.

Keys are compared only via the embedded `eq`; `hash` is used for potential future bucketed implementations (v1 may still scan linearly).

Convenience: `hashString` / `eqString`, `hashInt` / `eqInt`, `emptyStringDict` / `emptyIntDict`, `singletonStringDict` / `singletonIntDict`, and `fromStringList` / `fromIntList` (same as `singleton` / `fromList` with the matching hash/eq) for common key types.

| Function | Signature | Description |
|----------|-----------|-------------|
| `empty` | `((K) -> Int, (K, K) -> Bool) -> Dict<K,V>` | |
| `singleton` | `((K) -> Int, (K, K) -> Bool, K, V) -> Dict<K,V>` | |
| `singletonIntDict` / `singletonStringDict` | `(Int, V) -> Dict<Int,V>` / `(String, V) -> Dict<String,V>` | Same as `singleton` with `hashInt`/`eqInt` or `hashString`/`eqString` |
| `insert` / `remove` / `update` | … | `update` uses `Option<V>` → `Option<V>`; `None` removes |
| `isEmpty` / `member` / `get` / `size` | … | `get` returns `Option<V>` |
| `keys` / `values` / `toList` / `fromList` | … | `fromList`: later entries win on duplicate keys |
| `fromIntList` / `fromStringList` | `(List<(Int,V)>) -> Dict<Int,V>` / `(List<(String,V)>) -> Dict<String,V>` | Same as `fromList` with `hashInt`/`eqInt` or `hashString`/`eqString` |
| `map` / `filter` / `partition` | … | |
| `foldl` / `foldr` | `(Dict<K,V>, B, (K, V, B) -> B) -> B` | |
| `union` / `intersect` / `diff` | … | `union`: left-biased on key clash; `intersect`: value from second dict |

---

## kestrel:set

Sets as the **opaque** type `Set<E>` (defined in the module as an alias of `Dict<E, Unit>`; keys only, values are `()`). Same pipe-friendly convention as `kestrel:dict`. Helpers `emptyStringSet` / `emptyIntSet`, `singletonStringSet` / `singletonIntSet`, and `fromStringList` / `fromIntList` for common key types. `map` requires new `hash` / `eq` for the mapped key type.

---

**Built-in primitives (language):** The language provides built-in `print` and `println` (variadic, space-separated output; see language spec). These are distinct from the stdlib module below.

## kestrel:stack

Stack traces and basic I/O formatting. This module is for stack-trace and formatting utilities; the **built-in** `print`/`println` are language primitives (variadic, space-separated).

| Function | Signature | Description |
|----------|-----------|-------------|
| `trace` | `(T) -> StackTrace<T>` | Stack trace for the thrown value of type `T` |
| `print` | `(T) -> Unit` | Print value (e.g. to stdout); polymorphic in argument type (stdlib wrapper; distinct from built-in `print`) |
| `format` | `(T) -> String` | Format value as string (used implicitly in template interpolation); polymorphic in argument type |

---

## kestrel:http

HTTP server and client. Server-oriented API.

| Function | Signature | Description |
|----------|-----------|-------------|
| `createServer` | `((Request) -> Task<Response>) -> Server` | Create server with request handler |
| `listen` | `(Server, { host: String, port: Int }) -> Task<Unit>` | Start listening |
| `get` | `(String) -> Task<Response>` | HTTP GET request |
| `bodyText` | `(Request) -> Task<String>` | Request body as text |
| `queryParam` | `(Request, String) -> Option<String>` | Query parameter by name |
| `requestId` | `(Request) -> String` | Request ID |
| `nowMs` | `() -> Int` | Current time in milliseconds |

---

## kestrel:json

JSON parsing and serialisation.

| Function | Signature | Description |
|----------|-----------|-------------|
| `parse` | `(String) -> Value` | Parse JSON string to `Value` |
| `stringify` | `(Value) -> String` | Serialise `Value` to JSON string |

**Observable behaviour (reference VM):** On parse failure (invalid JSON, truncated input, etc.), `parse` returns the `Value` constructor **`Null`** — the same tag as the JSON literal `null`. Callers cannot distinguish a failed parse from valid JSON `null` until a dedicated error channel exists. Object values: the reference VM may yield an `Object` with an **empty** key–value payload when object entries are not yet preserved end-to-end; `stringify` of such values may produce `{}` regardless of the original input shape.

---

## kestrel:fs

File system. `readText` is **async-shaped** (`Task<String>`) so callers use `await` inside `async` functions; the reference VM may complete the task synchronously.

| Function | Signature | Description |
|----------|-----------|-------------|
| `readText` | `(String) -> Task<String>` | Read file contents as UTF-8 text. On missing path, unreadable path, or read failure, the completed task carries an **empty string** (no distinct error type in the surface API). |
| `writeText` | `(String, String) -> Unit` | Write UTF-8 text to a path (creates or truncates the file per host semantics). |
| `listDir` | `(String) -> List<String>` | Non-recursive directory listing. Each element is `"<fullPath>\\tfile"` or `"<fullPath>\\tdir"` for a regular file or directory entry. If the path cannot be opened, returns an **empty** list. |

---

## kestrel:test

Assertions and reporting for the Kestrel unit-test harness (`kestrel test`, `scripts/run_tests.ks`). Imports `kestrel:console` for styled output (✓/✗, colours, dim group labels).

### Suite

`Suite` is a record:

| Field | Type | Role |
|-------|------|------|
| `depth` | `Int` | Nesting depth for indentation of group labels and assertion lines |
| `summaryOnly` | `Bool` | When `True`, passing assertions and `group` headers/footers do not print; **failed** assertions still print. Counters always update. |
| `counts` | `{ passed: mut Int, failed: mut Int, startTime: mut Int }` | Shared mutable tallies and harness start time (`__now_ms()` at suite creation) |

The harness constructs one root `Suite` (typically `depth = 1` or as in `run_tests.ks`) whose `counts` is passed to `printSummary` after all `run(s)` calls.

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `group` | `(Suite, String, (Suite) -> Unit) -> Unit` | Runs `body` with a child suite (depth + 1, same `summaryOnly` and `counts`). Unless `summaryOnly`, prints a dim group title and a footer with pass/fail delta for the group and elapsed ms. |
| `eq` | `(Suite, String, X, X) -> Unit` | Success when `__equals(actual, expected)`. On failure: increments `failed`, prints ✗ and three indented lines — `expected (right):`, `actual (left):` (values via `__format_one`), then `(deep equality / same value shape)`. |
| `neq` | `(Suite, String, X, X) -> Unit` | Success when values are **not** deeply equal. On failure: prints ✗, `expected: values must differ (deep inequality)`, `both sides: …` (`__format_one`). |
| `isTrue` | `(Suite, String, Bool) -> Unit` | Success when `value` is `True`. On failure: `expected (Bool): true`, `actual (Bool): …`. |
| `isFalse` | `(Suite, String, Bool) -> Unit` | Success when `value` is `False`. On failure: `expected (Bool): false`, `actual (Bool): …`. |
| `gt` / `lt` | `(Suite, String, Int, Int) -> Unit` | Strict order on `Int` (`left > right` / `left < right`). On failure: requirement line (`need: left > right` or `left < right`, “strict total order on Int”), then `left (Int):` / `right (Int):` with `__format_one`. **Float is not in scope** for these helpers. |
| `gte` / `lte` | `(Suite, String, Int, Int) -> Unit` | Non-strict order (`>=` / `<=`). On failure: `need: left >= right` or `left <= right` (“total order on Int”), then labelled `Int` lines. |
| `throws` | `(Suite, String, (Unit) -> Unit) -> Unit` | Invokes `thunk(())`. Success if the call throws any exception (catch-all `_`); failure if it returns normally. On failure: `expected: callee throws an exception`, `actual: completed normally (no exception)`. **Note:** The surface type is `(Unit) -> Unit` because the language does not accept `() -> T` in type position for a zero-parameter function type; callers use e.g. `(_: Unit) => { … }`. |
| `printSummary` | `({ passed: mut Int, failed: mut Int, startTime: mut Int }) -> Unit` | Prints a blank line, then total elapsed ms. If `failed > 0`: red `M failed, N passed (…ms)` and **`exit(1)`**. If `failed == 0`: green `N passed (…ms)`. |

Passing assertions increment `passed` and, unless `summaryOnly`, print a green ✓ line with the description.

---

## Standard Types

Types referenced in the above signatures are part of the standard contract:

- `Option<T>` – Optional value (e.g. from `queryParam`)
- `Task<T>` – Async computation
- `Value` – JSON value type (ADT; see below)
- `Server`, `Request`, `Response` – HTTP types
- `StackTrace<T>` – Stack trace for a thrown value of type `T`

Their concrete definitions (ADT vs built-in) are implementation-defined as long as the function signatures are satisfied.

---

## Library types (Option, Result, List, Value)

The following types are provided by the standard library (not runtime built-ins) and are available for use in signatures and type annotations.

### Option\<T\>

Optional value: either a value of type `T` (constructor typically `Some`) or no value (`None`). Used for optional results (e.g. `queryParam`), safe indexing, and similar.

### Result\<T, E\>

Result of a computation that may fail: either a value of type `T` (success, e.g. `Ok`) or an error of type `E` (e.g. `Err`). Used for fallible operations instead of or in addition to exceptions.

### List\<T\>

Immutable linked list of values of type `T`. **List has special syntax** in the language:

- **List literal:** `[ a, b, ...c, d, ...e ]` — elements are expressions; `...expr` spreads the elements of a list into that position. Order: `a`, `b`, then elements of `c`, then `d`, then elements of `e`. Empty list: `[]`.
- **Cons (literal expression):** `e1 :: e2` — constructs a list with head `e1` and tail `e2` (which must be of type `List<T>`). Right-associative: `1 :: 2 :: 3 :: []` = `1 :: (2 :: (3 :: []))`.
- **Pattern matching:** The same notation is used in patterns:
  - List pattern: `[ p1, p2, ...rest ]` — matches a list with at least two elements (binding to `p1`, `p2`) and binds the rest to `rest`. The rest-binding `...rest` may appear only once and only as the **last** component (e.g. `[a, b, ...rest]` or `[...rest]`).
  - Cons pattern: `p :: ps` — matches a non-empty list; head matches `p`, tail matches `ps`.

Constructors and functions for Option, Result, and List (e.g. `map`, `flatMap`, `getOrElse`) are defined in the library; their modules and signatures are implementation-defined beyond the type names above.

### Value (JSON value)

`Value` is an **algebraic data type** representing a JSON value. It is provided by the standard library (e.g. from `kestrel:json`) and is the argument/result type of `parse` and `stringify`. The ADT has one constructor per JSON kind:

| Constructor | Payload | JSON equivalent |
|-------------|---------|------------------|
| `Null` | — | `null` |
| `Bool` | `Bool` | `true` / `false` |
| `Int` | `Int` | integer number |
| `Float` | `Float` | floating-point number |
| `String` | `String` | string |
| `Array` | `List<Value>` | array `[ ... ]` |
| `Object` | key–value pairs (e.g. `List<(String, Value)>` or library-defined record) | object `{ ... }` |

Exact constructor names and payload types are implementation-defined as long as they correspond to the JSON model above. Pattern matching on `Value` allows programs to inspect and build JSON values in a typed way.
