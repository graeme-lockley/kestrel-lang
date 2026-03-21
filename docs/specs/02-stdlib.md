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
| `indexOf` | `(String, String) -> Int` | Code-point index of first occurrence of substring, or -1 |
| `equals` | `(String, String) -> Bool` | Value equality (same UTF-8 / code-point sequence as the `==` operator on two `String` values) |
| `toUpperCase` | `(String) -> String` | Uppercase copy (Basic Latin and Latin extended; other scripts unchanged) |

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

---

## kestrel:fs

File system (async).

| Function | Signature | Description |
|----------|-----------|-------------|
| `readText` | `(String) -> Task<String>` | Read file contents as UTF-8 text |

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
