# 02 – Standard Library Contract

Version: 1.0

---

This document defines the standard library modules that a Kestrel implementation must provide. Implementations may add additional functions or modules beyond this contract; they must not remove or change the signatures listed here.

---

## kestrel:data/string

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

## kestrel:data/char

Operations on `Char` / `Rune` (one Unicode code point; same type per language spec).

| Function | Signature | Description |
|----------|-----------|-------------|
| `codePoint` | `(Char) -> Int` | Scalar value as a non-negative integer |
| `toCode` | `(Char) -> Int` | Alias for `codePoint` |
| `fromCode` | `(Int) -> Char` | Valid Unicode scalar → `Char`; invalid code point or surrogate → `U+0000` |
| `isDigit` | `(Char) -> Bool` | True for ASCII digits `0`–`9` (U+0030–U+0039) |
| `isUpper` / `isLower` | `(Char) -> Bool` | ASCII A–Z / a–z |
| `isAlpha` | `(Char) -> Bool` | `isUpper` ∨ `isLower` |
| `isAlphaNum` | `(Char) -> Bool` | `isAlpha` ∨ `isDigit` |
| `isOctDigit` | `(Char) -> Bool` | `0`–`7` |
| `isHexDigit` | `(Char) -> Bool` | Decimal digit or A–F / a–f |
| `toUpper` / `toLower` | `(Char) -> Char` | ASCII case fold only; other code points unchanged |

---

## kestrel:data/tuple

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

## kestrel:data/basics

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
| `toFloat` | `(Int) -> Float` | `KRuntime#intToFloat` |
| `truncate` | `(Float) -> Int` | Toward zero (`KRuntime#floatToInt`) |
| `floor` / `ceiling` / `round` | `(Float) -> Int` | `KRuntime#floatFloor` / `KRuntime#floatCeil` / `KRuntime#floatRound` |
| `abs` | `(Float) -> Float` | `KRuntime#floatAbs` |
| `sqrt` | `(Float) -> Float` | `KRuntime#floatSqrt` (NaN for negative input) |
| `isNaN` / `isInfinite` | `(Float) -> Bool` | `KRuntime#floatIsNan` / `KRuntime#floatIsInfinite` |
| `nowMs` | `() -> Int` | Wall-clock milliseconds (`KRuntime#nowMs`); also used by `kestrel:http` `nowMs` |
| `isTtyStdout` | `() -> Bool` | Returns `True` when stdout is connected to an interactive terminal (`System.console() != null`). |

---

## kestrel:sys/runtime

Canonical **exception ADTs** used by the VM for arithmetic traps (see language spec §Int operations). User code should import these names to `catch` or to annotate types; implementations must not rely on a duplicate `export exception` in the entry module.

| Name | Role |
|------|------|
| `ArithmeticOverflow` | Thrown when a 64-bit signed `Int` operation overflows (exceeds Long.MIN_VALUE or Long.MAX_VALUE). |
| `DivideByZero` | Thrown for `Int` division or remainder when the divisor is zero. |

---

## kestrel:data/option

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

## kestrel:data/list

| `map` | `(List<A>, (A) -> B) -> List<B>` | Element-wise map |
| `filter` | `(List<A>, (A) -> Bool) -> List<A>` | Keep elements satisfying predicate |
| `foldl` | `(List<A>, B, (B, A) -> B) -> B` | Left fold |
| `sum` | `(List<Int>) -> Int` | Sum of elements; `[]` yields `0` |
| `reverse` | `(List<T>) -> List<T>` | Reverse element order |
| `append` | `(List<T>, List<T>) -> List<T>` | Concatenate (immutable) |
| `concat` | `(List<List<T>>) -> List<T>` | Flatten one level |
| `foldr` | `(List<A>, B, (A, B) -> B) -> B` | Right fold |
| `intersperse` | `(List<A>, A) -> List<A>` | Insert separator between elements; list first for piping |
| `repeat` | `(Int, A) -> List<A>` | `n` copies of `x` |
| `range` | `(Int, Int) -> List<Int>` | Inclusive `lo`..`hi` |
| `take` | `(List<A>, Int) -> List<A>` | First `n` elements; list first for piping |
| `takeWhile` / `dropWhile` | … | Standard list prefixes / scanning |
| `zip` | `(List<A>, List<B>) -> List<(A, B)>` | Pair elements while both lists non-empty |
| `map2`–`map5` | … | Zipping maps (pairwise / triple / …) |
| `filterMap` | `(List<A>, (A) -> Option<B>) -> List<B>` | Map and drop `None` |
| `concatMap` | `(List<A>, (A) -> List<B>) -> List<B>` | `concat` of `map` |
| `indexedMap` | `(List<A>, (Int, A) -> B) -> List<B>` | Map with index |
| `member` | `(List<A>, A) -> Bool` | True if any element is `==` to the value; list first for piping |
| `any` / `all` | … | Short-circuit predicates |
| `product` | `(List<Int>) -> Int` | Product; `[]` → `1` |
| `maximum` / `minimum` | `(List<Int>) -> Option<Int>` | |
| `partition` | `(List<A>, (A) -> Bool) -> (List<A>, List<A>)` | |
| `unzip` | `(List<(A, B)>) -> (List<A>, List<B>)` | |
| `sort` | `(List<Int>) -> List<Int>` | Insertion sort |
| `head` / `tail` | `List<A> -> Option<…>` | |

---

## kestrel:io/fs

File system. File operations are async and return `Task<Result<T, FsError>>` so callers use `await` and pattern matching instead of exception control flow.

| Type | Definition |
|------|------------|
| `FsError` | `NotFound | PermissionDenied | IoError(String)` |
| `DirEntry` | `File(String) | Dir(String)` — typed directory entry where the `String` payload is the full path |

| Function | Signature | Description |
|----------|-----------|-------------|
| `readText` | `(String) -> Task<Result<String, FsError>>` | Read file contents as UTF-8 text. Returns `Ok(contents)` on success. |
| `writeText` | `(String, String) -> Task<Result<Unit, FsError>>` | Write UTF-8 text to a path (creates or truncates the file per host semantics). Returns `Ok(())` on success. |
| `listDir` | `(String) -> Task<Result<List<DirEntry>, FsError>>` | Non-recursive directory listing. `Ok(entries)` on success where each entry is `File(fullPath)` or `Dir(fullPath)`; missing paths return `Err(NotFound)` and permission failures return `Err(PermissionDenied)`. Symlinks are resolved: if the target is a directory, `Dir` is returned, otherwise `File`. |

---

## kestrel:sys/process

Process information and subprocess execution.

| Type | Definition |
|------|------------|
| `ProcessError` | `ProcessSpawnError(String)` |
| `ProcessResult` | `{ exitCode: Int, stdout: String }` |

| Function | Signature | Description |
|----------|-----------|-------------|
| `getProcess` | `() -> { os: String, args: List<String>, env: List<(String, String)>, cwd: String }` | Returns process metadata for the current invocation. |
| `runProcess` | `(String, List<String>) -> Task<Result<ProcessResult, ProcessError>>` | Spawn a subprocess, capture combined stdout+stderr, and return `Ok(ProcessResult)` on completion where `exitCode` is the process exit code and `stdout` contains the captured output. Returns `Err(ProcessSpawnError(message))` when process start/execution fails. |

### Implementation notes

`getOs`, `getArgs`, `getCwd`, and `runProcessAsync` are `extern fun` declarations backed by `KRuntime.getOs()`, `KRuntime.getArgs()`, `KRuntime.getCwd()`, and `KRuntime.runProcessAsync(Object, Object)` static methods in the JVM runtime. `getProcess` and `runProcess` are thin wrappers over these extern funs.

---

## kestrel:sys/task

Task combinator utilities for composing `Task<T>` values.

### Exceptions

| Exception | Description |
|-----------|-------------|
| `Cancelled` | Thrown when `await` is applied to a cancelled task. |

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `map` | `(Task<A>, A -> B) -> Task<B>` | Transform the result of a task without blocking. Cancelling the returned task also cancels the source task. |
| `all` | `(List<Task<T>>) -> Task<List<T>>` | Wait for all tasks to complete and collect results; fails fast if any task fails. When one fails, the combined task completes exceptionally but remaining tasks continue running (they are not cancelled). |
| `race` | `(List<Task<T>>) -> Task<T>` | Return the result of the first task to complete (success or failure). After the first task settles, all still-running tasks are cancelled. If all tasks fail, the first failure propagates. An empty list raises a catchable Kestrel exception with payload `"no tasks provided"`. |
| `cancel` | `(Task<T>) -> Unit` | Request cancellation of a task. Calls `CompletableFuture.cancel(true)` — best-effort I/O interruption. Cancelling an already-completed task is a no-op. Any callers `await`-ing the task receive `Cancelled`. |

### Implementation notes

`map`, `all`, `race`, and `cancel` are `extern fun` declarations backed by `KTask.taskMap`, `KTask.taskAll`, `KTask.taskRace`, and `KTask.cancel` static methods. All four are parametric; `cancel` returns `Unit` (JVM `void` → `KUnit.INSTANCE`).

**Quiescence timeout:** When `kestrel run` (the default `--exit-wait` mode) waits for async tasks to finish on process exit, it applies a timeout controlled by the `kestrel.exitWaitTimeoutMs` JVM system property (default `30000` ms; `0` = no timeout). If the deadline passes with tasks still in flight, a warning is printed to stderr and the process exits with code 1.

---

## kestrel:data/result

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

## kestrel:data/dict

Finite maps exposed as the **opaque** type `Dict<K, V>`: clients use the functions below only and must not rely on a visible record shape. The implementation is backed by `java.util.HashMap` via `KRuntime` static helpers. **Pipe-friendly:** the dict is the first argument on `insert`, `get`, `map`, etc.

Keys use Java `.equals()` / `.hashCode()` semantics. For `String`, `Int` (boxed `Long`), and `Bool` (boxed `Boolean`) this is structural equality (correct). For ADT values and records, this is reference-identity equality.

`insert` and `remove` are copy-on-write: each call returns a new `Dict` with the modification applied, leaving the original unchanged.

Convenience: `hashString` / `eqString`, `hashInt` / `eqInt`, `emptyStringDict` / `emptyIntDict`, `singletonStringDict` / `singletonIntDict`, and `fromStringList` / `fromIntList` for common key types. The legacy `empty(hf, eqf)` / `singleton(hf, eqf, k, v)` / `fromList(hf, eqf, entries)` signatures still accept (and silently ignore) the hash/eq arguments for backward compatibility.

| Function | Signature | Description |
|----------|-----------|-------------|
| `empty` | `() -> Dict<K,V>` | |
| `singleton` | `((K) -> Int, (K, K) -> Bool, K, V) -> Dict<K,V>` | hash/eq ignored; for backward compat |
| `singletonIntDict` / `singletonStringDict` | `(Int, V) -> Dict<Int,V>` / `(String, V) -> Dict<String,V>` | |
| `insert` / `remove` / `update` | … | `update` uses `Option<V>` → `Option<V>`; `None` removes |
| `isEmpty` / `member` / `get` / `size` | … | `get` returns `Option<V>` |
| `keys` / `values` / `toList` / `fromList` | … | `fromList`: later entries win on duplicate keys |
| `fromIntList` / `fromStringList` | `(List<(Int,V)>) -> Dict<Int,V>` / `(List<(String,V)>) -> Dict<String,V>` | |
| `map` / `filter` / `partition` | … | |
| `foldl` / `foldr` | `(Dict<K,V>, B, (K, V, B) -> B) -> B` | |
| `union` / `intersect` / `diff` | … | `union`: left-biased on key clash; `intersect`: value from second dict |

---

## kestrel:data/set

Sets as the **opaque** type `Set<E>` (defined in the module as an alias of `Dict<E, Unit>`; keys only, values are `()`). Same pipe-friendly convention as `kestrel:dict`. Helpers `emptyStringSet` / `emptyIntSet`, `singletonStringSet` / `singletonIntSet`, and `fromStringList` / `fromIntList` for common key types. `map` requires new `hash` / `eq` for the mapped key type.

---

## kestrel:array

Mutable, O(1)-indexed sequences exposed as the **opaque** type `Array<T>`. Backed by `java.util.ArrayList<Object>` via `KRuntime` static helpers. `Array<T>` is **mutable in place**: `set` and `push` mutate the same array object; there is no copy-on-write. Use `fromList` / `toList` to bridge between `Array<T>` and the immutable `List<T>`.

Index bounds are enforced by the Java runtime (`IndexOutOfBoundsException` on out-of-range access).

| Function | Signature | Description |
|----------|-----------|-------------|
| `new` | `() -> Array<T>` | Create an empty array |
| `get` | `(Array<T>, Int) -> T` | O(1) index access; throws on out-of-bounds |
| `set` | `(Array<T>, Int, T) -> Unit` | O(1) in-place mutation; throws on out-of-bounds |
| `push` | `(Array<T>, T) -> Unit` | Append element; grows internally |
| `length` | `(Array<T>) -> Int` | Current number of elements |
| `fromList` | `(List<T>) -> Array<T>` | Convert immutable list to array (preserving order) |
| `toList` | `(Array<T>) -> List<T>` | Convert array to immutable list (preserving order) |

---

**Built-in primitives (language):** The language provides built-in `print` and `println` (variadic, space-separated output; see language spec). These are distinct from the stdlib module below.

## kestrel:dev/cli

Declarative CLI argument parser for Kestrel tools. Provides types and functions for parsing command-line arguments, rendering help text, and dispatching to a handler function.

**Types:**

| Type | Definition |
|------|------------|
| `CliOptionKind` | ADT: `Flag \| Value(String)`. `Flag` — boolean presence (no value token). `Value(metavar)` — consumes the next token; `String` is the metavar for help display (e.g. `"FILE"`). |
| `CliOption` | Record `{ short: Option<String>, long: String, kind: CliOptionKind, description: String }`. `long` includes the `--` prefix (e.g. `"--output"`). `short` includes the `-` prefix (e.g. `Some("-o")`). |
| `CliArg` | Record `{ name: String, description: String, variadic: Bool }`. Describes a positional argument. |
| `CliSpec` | Record `{ name: String, version: String, description: String, usage: String, options: List<CliOption>, args: List<CliArg> }`. Complete description of a tool. |
| `ParsedArgs` | Record `{ options: Dict<String, String>, positional: List<String> }`. Keys in `options` are bare long names without `--` (e.g. `"output"`); `Flag` values are `"true"`. |
| `CliError` | ADT: `UnknownOption(String) \| MissingValue(String) \| MissingArg(String) \| UnexpectedArg(String)`. |

**Functions:**

| Function | Signature | Description |
|----------|-----------|-------------|
| `parse` | `(CliSpec, List<String>) -> Result<ParsedArgs, CliError>` | Parse argv against the spec. `--help` and `--version` are NOT intercepted; use `run` for that. |
| `help` | `(CliSpec) -> String` | Render formatted help text. Includes built-in `--help` / `--version` options. |
| `version` | `(CliSpec) -> String` | Render `"name vX.Y.Z"`. |
| `run` | `(CliSpec, (ParsedArgs) -> Task<Int>, List<String>) -> Task<Int>` | Intercept `--help` / `--version`, then parse and dispatch to the handler. Returns exit code. |

**Parsing rules:**
- `--flag` sets `options["flag"] = "true"`.
- `--key value` and `--key=value` set `options["key"] = "value"`.
- `-s` (short) is an alias for its long name; stores under the long name's bare key.
- `-sVALUE` (short with inline value) is accepted for Value options.
- `--` terminates option parsing; remaining tokens are positional.
- `--help` / `-h` and `--version` / `-V` are always available via `run`; tools must not re-declare them.

---

## kestrel:dev/text/prettyprinter

Wadler–Lindig combinatorial pretty-printer. Builds abstract `Doc` values from combinators and renders them to a `String` at a given column width. Used by `kestrel:tools/format` to produce canonical Kestrel source text.

**Type:**

| Type | Definition |
|------|------------|
| `Doc` | ADT: `Empty \| Text(String) \| Concat(Doc, Doc) \| Nest(Int, Doc) \| Line \| LineBreak \| Group(Doc) \| FlatAlt(Doc, Doc)`. |

**Rendering:**

| Function | Signature | Description |
|----------|-----------|-------------|
| `pretty` | `(Int, Doc) -> String` | Render `doc` to a `String` fitting within `width` columns. Uses the Lindig bounded algorithm. |

**Primitive combinators:**

| Name | Type | Description |
|------|------|-------------|
| `empty` | `Doc` | The empty document. |
| `text` | `(String) -> Doc` | A literal string (must not contain newlines). |
| `concat` | `(Doc, Doc) -> Doc` | Horizontal concatenation of two documents. |
| `append` | `(Doc, Doc) -> Doc` | Alias for `concat`. |
| `nest` | `(Int, Doc) -> Doc` | Increase indentation by `n` for all newlines inside `d`. |
| `line` | `Doc` | A newline in broken mode; a single space in flat mode. |
| `lineBreak` | `Doc` | A newline in broken mode; empty in flat mode. |
| `softBreak` | `Doc` | A space in flat mode; empty in broken mode. |
| `group` | `(Doc) -> Doc` | Try to render `d` flat; fall back to broken if it does not fit. |
| `flatAlt` | `(Doc, Doc) -> Doc` | `flatAlt(broken, flat)`: use `broken` in broken mode, `flat` in flat mode. |

**Derived combinators:**

| Name | Signature | Description |
|------|-----------|-------------|
| `beside` | `(Doc, Doc) -> Doc` | Two documents separated by a single space. |
| `softLine` | `(Doc, Doc) -> Doc` | Two documents separated by `line`. |
| `hcat` | `(List<Doc>) -> Doc` | Concatenate a list with no separator. |
| `hsep` | `(List<Doc>) -> Doc` | Concatenate a list separated by spaces. |
| `vsep` | `(List<Doc>) -> Doc` | Concatenate a list separated by `line`. |
| `vcat` | `(List<Doc>) -> Doc` | Concatenate a list separated by `lineBreak`. |
| `sep` | `(List<Doc>) -> Doc` | `group(vsep(docs))`: tries horizontal; falls back to vertical. |
| `indent` | `(Int, Doc) -> Doc` | Indent `d` by `n` spaces from the current column. |
| `hang` | `(Int, Doc) -> Doc` | Hanging indent: first item at current column; rest indented by `n`. |
| `align` | `(Doc) -> Doc` | Align continuation to current column (identity in this implementation). |
| `punctuate` | `(Doc, List<Doc>) -> List<Doc>` | Append separator after every element except the last. |
| `enclose` | `(Doc, Doc, Doc) -> Doc` | Surround `d` with `open` and `close` delimiters. |
| `encloseSep` | `(Doc, Doc, Doc, List<Doc>) -> Doc` | Like `enclose` but with a separator between items. |
| `space` | `Doc` | A single space (`Text(" ")`). |
| `comma` | `Doc` | A comma (`Text(",")`). |

**Layout rules:**
- `nest(n, d)` increases the indentation level used when a newline is rendered inside `d`. Nest the `concat(line, ...)` call inside `nest(n, ...)` for correct indentation: `nest(2, concat(line, body))`.
- `Group(d)` first attempts flat rendering via `fitsQ`; if the flat version does not fit in the remaining columns it falls back to broken rendering.
- In flat mode, `Line` → `" "`, `LineBreak` → `""`. In broken mode both → `"\n"` followed by the current indentation.

---

## kestrel:dev/stack

Stack traces and basic I/O formatting. This module is for stack-trace and formatting utilities; the **built-in** `print`/`println` are language primitives (variadic, space-separated).

| Function | Signature | Description |
|----------|-----------|-------------|
| `trace` | `(T) -> StackTrace<T>` | Captures the **current** call stack at the call site, paired with the given value (typically the caught exception). Implemented via `KRuntime#captureTrace`. |
| `print` | `(T) -> Unit` | Print value (e.g. to stdout); polymorphic in argument type (declared as `extern fun`; distinct from built-in `print`) |
| `format` | `(T) -> String` | Format value as string (used implicitly in template interpolation); polymorphic in argument type |

**Types (exported from this module):**

| Type | Definition (contract) |
|------|------------------------|
| `StackFrame` | Record `{ file: String, line: Int, function: String }`. **`file`** / **`line`** come from the debug section (03 §8) when available; otherwise **`file`** may be `"?"` and **`line`** `0`. **`function`** is a placeholder (`"<unknown>"` in the reference VM) until symbol information exists. |
| `StackTrace<T>` | Record `{ value: T, frames: List<StackFrame> }`. **`frames`** order is **innermost-first** (same order as uncaught-exception stderr lines in 05 §5). |

**Formatting `StackTrace<T>`:** `format` (via `KRuntime#formatOne`) produces a multi-line string: one line for `format(value)`, then one line per frame, each `  at file:line\n` (two leading spaces, same shape as stderr traces). Other values use the usual polymorphic formatting rules.

---

## kestrel:io/http

HTTP server and client. Provides an HTTP GET client and an HTTP server that dispatches incoming requests to a Kestrel handler function.

### Opaque types

| Type | JDK backing class | Role |
|------|-------------------|------|
| `Server` | `com.sun.net.httpserver.HttpServer` | An HTTP server instance (not yet listening). Produced by `createServer`; passed to `listen`. |
| `Request` | `com.sun.net.httpserver.HttpExchange` | An incoming server request. Wraps the `HttpExchange` for the duration of the handler call. Provides read access to the request (method, path, query string, body) and is the channel through which the handler response is written. |
| `Response` | `com.sun.net.httpserver.HttpExchange` **or** a synthetic record `{ status: Int, body: String }` (implementation-defined) | Represents either a completed client `get` response (status + body) or a value to be sent back by the server handler. Use `makeResponse(status, body)` to create a `Response` for server handlers. |

**Implementation note:** `Response` is a single unified opaque type. The client (`get`) wraps the JDK `HttpResponse<String>`; the server handler returns a `Response` created via `makeResponse`. The implementation is free to use separate backing JVM objects as long as `statusCode` and `bodyText` work on both.

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `createServer` | `((Request) -> Task<Response>) -> Task<Server>` | Create an HTTP server with the given request handler. The handler is called once per incoming request on a fresh virtual thread. Returns a `Task<Server>` (the server is created asynchronously). |
| `listen` | `(Server, { host: String, port: Int }) -> Task<Unit>` | Bind the server to the given host and port and start accepting connections. The task completes as soon as the server is listening; it does **not** await shutdown. Use port `0` to let the OS assign a free port; retrieve the bound port with `serverPort`. |
| `serverPort` | `(Server) -> Int` | Return the actual port the server is bound to. Useful when the server was started on port `0`. |
| `serverStop` | `(Server) -> Task<Unit>` | Stop the server and release its port. Waits briefly for in-flight requests to complete before forcibly closing connections. |
| `get` | `(String) -> Task<Response>` | Issue an HTTP GET request to the given URL. Supports `http://` and `https://` schemes. The task resolves with the server's response (including non-2xx responses). The task fails for network/TLS errors (e.g. unreachable host, certificate validation failure, unsupported scheme). |
| `request` | `({ method: String, url: String, headers: List<(String, String)>, body: Option<String> }) -> Task<Response>` | Issue an HTTP request with an arbitrary method, optional request headers, and an optional body. `method` is case-insensitive (normalised to uppercase internally). `headers` is a list of `(name, value)` pairs added to the request; an empty list `[]` sends no extra headers. `body` is `Some(text)` to send a UTF-8 text body, or `None` for no body. Same error semantics as `get`. |
| `responseHeaders` | `(Response) -> List<(String, String)>` | Return all response headers as a list of `(name, value)` pairs. Header names are lowercased. The list may contain multiple entries for the same name if the server sent the header multiple times. Only meaningful for responses produced by `get` or `request`; behaviour is unspecified for `makeResponse` results. |
| `responseHeader` | `(Response, String) -> Option<String>` | Return the first value for the given response header name (case-insensitive lookup, name normalised to lowercase). Returns `None` if the header is absent. Only meaningful for responses from `get` or `request`. |
| `bodyText` | `(Response) -> String` | Extract the body of a `Response` (from `get` or `request`) as a UTF-8 string. The body is buffered in memory; there is no streaming. |
| `requestBodyText` | `(Request) -> Task<String>` | Read the full body of an incoming server `Request` as a UTF-8 string. Returns a `Task` because the body read is I/O. |
| `statusCode` | `(Response) -> Int` | Return the HTTP status code of a `Response` produced by `get` or `request`. |
| `makeResponse` | `(Int, String) -> Response` | Construct a `Response` for use as the return value of a server handler. The first argument is the HTTP status code (e.g. `200`); the second is the response body text. |
| `queryParam` | `(Request, String) -> Option<String>` | Extract a query parameter by name from an incoming `Request`. If the parameter appears multiple times, the **last** occurrence wins. Returns `None` if the parameter is absent. Percent-encoded values are decoded automatically. |
| `requestId` | `(Request) -> String` | Return a stable unique identifier string for the request (UUID format; unique per accepted connection). |
| `nowMs` | `() -> Int` | Current time in milliseconds (forwards to `kestrel:basics` `nowMs`). |

### Error semantics

- **`get` task failure:** The task returned by `get` fails (becomes a failed `Task`) in the following cases: network connection failure, DNS resolution failure, TLS certificate validation failure, connection timeout, unsupported URL scheme (anything other than `http://` or `https://`).
- **Non-2xx responses:** A response with a 4xx or 5xx status code is **not** a task failure. The task resolves successfully with the `Response`; the caller inspects `statusCode` to determine success or failure.
- **`createServer` and `listen` failures:** Binding to an already-in-use port, or invalid host/port, surfaces as a task failure.
- **Handler exceptions:** If the handler function throws an exception, the server sends a 500 response and logs the error; the handler exception does not propagate to the `listen` task.

### TLS defaults for `get`

- System trust store (JDK default `SSLContext`).
- SNI enabled.
- Minimum TLS version: TLS 1.2 (JDK default for Java 21).
- No client certificate authentication.
- No additional JVM system properties need to be set for standard public HTTPS.

### Server concurrency model

The HTTP server (`createServer` / `listen`) dispatches each incoming request to the handler on a **new virtual thread** (Java 21 virtual-thread executor). Specifically:

- `com.sun.net.httpserver.HttpServer` is configured with `Executors.newVirtualThreadPerTaskExecutor()`.
- Each call to the handler receives its own `Request` (backed by the `HttpExchange` for that request).
- The handler runs for the lifetime of the exchange; the `HttpExchange` is closed when the handler's `Task<Response>` resolves.
- Handlers are **not** re-entrant by the server; each request gets an independent handler invocation.
- There is no built-in request rate limiting or connection limit beyond the JDK defaults.

### `queryParam` duplicate-key rule

If a URL query string contains the same key multiple times (e.g. `?a=1&a=2`), `queryParam` returns the **last** occurrence's value (`"2"` in the example). This matches the behaviour of most web frameworks. If the key is absent, `None` is returned.

---

## kestrel:data/json

JSON parsing and serialisation implemented **in Kestrel** (no host JSON primitives). Import `Value`, `JsonParseError`, constructors, and helpers from this module; there is **no** separate `kestrel:value` module and no language prelude injection for JSON `Value` constructors.

| Function / type | Signature / role | Description |
|-----------------|------------------|-------------|
| `Value` | ADT | JSON value: `Null`, `Bool(Bool)`, `Int(Int)`, `Float(Float)`, `StrVal(String)`, `Array(List<Value>)`, `Object(List<(String, Value)>)`. Constructor **`StrVal`** holds JSON strings (the name avoids clashing with the `String` type in type arguments). |
| `JsonParseError` | ADT | Parse failure: `EmptyInput`, `UnclosedString(Int)`, `InvalidEscape(Int)`, `InvalidUnicodeEscape(Int)`, `InvalidNumber(Int)`, `UnclosedArray(Int)`, `UnclosedObject(Int)`, `ExpectedColon(Int)`, `ExpectedCommaOrBracket(Int)`, `TrailingGarbage(Int)`, `UnexpectedToken(Int)` — each `Int` is a **code-point index** into the input (`kestrel:string` length and indexing are by Unicode scalar). |
| `parse` | `(String) -> Result<Value, JsonParseError>` | Parse a single JSON value; **Err** on invalid or truncated input. Valid JSON **`null`** is **`Ok(Null)`**, never conflated with syntax errors. |
| `parseOrNull` | `(String) -> Option<Value>` | `Some(v)` iff `parse` is `Ok(v)`; otherwise `None`. |
| `errorAsString` | `(JsonParseError) -> String` | Human-readable message for logging and tests. |
| `stringify` | `(Value) -> String` | Serialise to JSON text with required escaping. |
| `describeParse` | `(String) -> String` | `"ok"` if `parse` succeeds, else `errorAsString` of the error. |

**Objects:** Keys are strings; **duplicate keys** in one object: the **last** occurrence in source order wins (implementation keeps a list and replaces). **`stringify`** emits object entries in **list order** (not sorted by key).

**Surrogates / non-BMP:** `\uXXXX` denotes a UTF-16 code unit; a pair `\uD800`–`\uDFFF` + `\uDC00`–`\uDFFF` may form one supplementary code point. Lone surrogates and invalid scalar values are rejected where the implementation checks them.

**Trailing content:** After a complete top-level value, **no** further non-whitespace is allowed; otherwise **`TrailingGarbage`**. (Leading/trailing **ASCII** whitespace around the whole document is trimmed before parsing; **internal** whitespace between tokens follows JSON rules.)

**Numbers:** Integers and IEEE-754 floats as in JSON; leading-zero and `NaN`/`Infinity` rules follow strict JSON rejection in the reference implementation.

**Migration:** Code that relied on an unqualified prelude `Null` / `Int` / … as JSON `Value` constructors must **import** from `kestrel:json` (or re-export locally).

---

## kestrel:test

Assertions and reporting for the Kestrel unit-test harness (`kestrel test`, `scripts/run_tests.ks`). Imports `kestrel:basics` (`nowMs`), `kestrel:console`, `kestrel:list`, `kestrel:stack` (`format`), and `kestrel:string` (`concat`, `repeat`) for implementation (namespace imports); styled output uses console ANSI constants (✓/✗, colours, default-weight group names, dim for secondary text such as timing and verbose footers).

The CLI (`./scripts/kestrel test`) passes flags **`--verbose`** and **`--summary`** through to the runner. Default output mode is **compact**.

### Output mode constants

`Suite.output` is an `Int` discriminator. The module exports:

| Name | Value | Role |
|------|-------|------|
| `outputVerbose` | `0` | Full detail: group title printed **before** children; one ✓ line per passing assertion; dim footer with pass/fail count and elapsed ms after each group. |
| `outputCompact` | `1` | Default: for the top-level (depth-0) group, prints the name first, then runs children silently, then prints a dim count-only footer (`N passed (Tms)`). Nested sub-groups each print a compact `name (N✓ Tms)` summary line after their children. Passing assertions do not print. After the first failure in a group, further passing assertions in that group print immediately (for context). |
| `outputSummary` | `2` | One compact `name (N✓ Tms)` line per top-level (depth-0) group after its children. No title printed before children; nested sub-groups silent; passing assertions silent. |

Other `Int` values are reserved; treat them as **compact** for forward compatibility.

### Suite

`Suite` is a record:

| Field | Type | Role |
|-------|------|------|
| `depth` | `Int` | Nesting depth for indentation of group labels and assertion lines |
| `output` | `Int` | Output mode; use `outputVerbose`, `outputCompact`, or `outputSummary`. |
| `counts` | See below | Shared mutable tallies and harness timing |

**`counts`** shape (internal; not accessed directly by test suite modules):

| Field | Type | Role |
|-------|------|------|
| `passed` | `mut Int` | Total passing assertions |
| `failed` | `mut Int` | Total failing assertions |
| `startTime` | `mut Int` | `nowMs()` at harness start |
| `compactExpanded` | `mut Bool` | Internal: after a compact-mode failure, further passes in the same group print immediately |

The harness constructs a root `Suite` via `makeRoot(outputMode)` (depth `0`); `printSummary(root)` is called after all `run(s)` calls.

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `group` | `(Suite, String, (Suite) -> Unit) -> Unit` | Runs `body` with a child suite (depth + 1, same `output` and `counts`). **Verbose:** prints default-weight title before children; ✓ pass lines during body; dim `N passed (Tms)` footer after. **Compact depth-0:** prints title before body; after body prints dim count-only footer (no name repeated). **Compact depth>0:** no title before body; after body prints `name (N✓ Tms)` compact summary. **Summary depth-0:** no title before body; after body prints `name (N✓ Tms)` compact summary. **Summary depth>0:** silent. |
| `eq` | `(Suite, String, X, X) -> Unit` | Success when `actual == expected` (semantic / deep equality; language §3.2.1). On failure: increments `failed`, prints ✗ and three indented lines — `expected (right):`, `actual (left):` (values via `kestrel:stack` `format`), then `(deep equality / same value shape)`. |
| `neq` | `(Suite, String, X, X) -> Unit` | Success when `actual != notExpected`. On failure: prints ✗, `expected: values must differ (deep inequality)`, `both sides: …` (`format`). |
| `isTrue` | `(Suite, String, Bool) -> Unit` | Success when `value` is `True`. On failure: `expected (Bool): true`, `actual (Bool): …` (`format`). |
| `isFalse` | `(Suite, String, Bool) -> Unit` | Success when `value` is `False`. On failure: `expected (Bool): false`, `actual (Bool): …` (`format`). |
| `gt` / `lt` | `(Suite, String, Int, Int) -> Unit` | Strict order on `Int` (`left > right` / `left < right`). On failure: requirement line (`need: left > right` or `left < right`, “strict total order on Int”), then `left (Int):` / `right (Int):` with `format`. **Float is not in scope** for these helpers. |
| `gte` / `lte` | `(Suite, String, Int, Int) -> Unit` | Non-strict order (`>=` / `<=`). On failure: `need: left >= right` or `left <= right` (“total order on Int”), then labelled `Int` lines (`format`). |
| `throws` | `(Suite, String, (Unit) -> Unit) -> Unit` | Invokes `thunk(())`. Success if the call throws any exception (catch-all `_`); failure if it returns normally. On failure: `expected: callee throws an exception`, `actual: completed normally (no exception)`. **Note:** The surface type is `(Unit) -> Unit` because the language does not accept `() -> T` in type position for a zero-parameter function type; callers use e.g. `(_: Unit) => { … }`. |
| `makeRoot` | `(Int) -> Suite` | Create a root `Suite` for the given output mode (`outputCompact`, `outputVerbose`, or `outputSummary`). Sets `depth = 0` and zeroes all counts. Use this instead of constructing `Suite` directly. |
| `printSummary` | `(Suite) -> Unit` | Prints a blank line, then a total: green `N passed (…ms)` when all pass; red `M failed, N passed (…ms)` and **`exit(1)`** when any fail. |

Passing assertions increment `passed`. In **verbose** and expanded compact, they print a green ✓ line with the description. In **compact** (before expansion) and **summary**, passing assertions do not print.

---

## kestrel:socket

TCP and TLS socket library. Provides plain TCP and TLS (HTTPS-style) client/server sockets backed by `java.net.Socket` and `javax.net.ssl.SSLSocket` via `extern type`/`extern fun` bindings. Implemented without JVM-specific transport stacks — all socket classes are part of the standard JDK (Java 21+). All I/O operations are `Task`-shaped and run on virtual threads.

### Types

| Type | JVM backing | Description |
|------|-------------|-------------|
| `Socket` | `java.net.Socket` | A connected TCP or TLS socket. Produced by `tcpConnect`, `tlsConnect`, or `accept`. Used for `sendText`, `readAll`, `readLine`, and `close`. |
| `ServerSocket` | `java.net.ServerSocket` | A bound TCP server socket. Produced by `listen`. Used for `accept`, `serverPort`, and `serverClose`. |

Both types are opaque: not constructible by user code; produced exclusively by the module functions listed below.

### Client functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `tcpConnect` | `(String, Int) -> Task<Socket>` | Connect a plain TCP socket to `host:port`. Task fails with `java.io.IOException` on connection error (refused, unreachable, DNS failure). |
| `tlsConnect` | `(String, Int) -> Task<Socket>` | Connect a TLS socket to `host:port`. Uses the JDK default `SSLContext` (system trust store, hostname verification enabled). Performs a full TLS handshake before the task resolves. Task fails on TLS or connection error. |

### I/O functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `sendText` | `(Socket, String) -> Task<Unit>` | Write the UTF-8 text to the socket output stream and flush. Task fails on socket error. |
| `readAll` | `(Socket) -> Task<String>` | Read all bytes until EOF (remote closes its write side). Returns UTF-8-decoded text. Use for HTTP/1.0 or other close-on-response protocols. **Blocks until EOF.** |
| `readLine` | `(Socket) -> Task<String>` | Read one line terminated by `\n` or `\r\n`. Returns the line without the trailing newline. Returns `""` at EOF. Useful for line-oriented protocols (SMTP, FTP, etc.). |
| `close` | `(Socket) -> Task<Unit>` | Close the socket. Further I/O will fail. |

### Server functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `listen` | `(String, Int) -> Task<ServerSocket>` | Bind a TCP server socket on `host:port`. Pass `0` as port for an OS-assigned ephemeral port. Enables `SO_REUSEADDR`. Task fails if the port is already in use. |
| `accept` | `(ServerSocket) -> Task<Socket>` | Accept one incoming connection. Blocks until a client connects. Returns a connected `Socket`. |
| `serverPort` | `(ServerSocket) -> Int` | Return the actual local port the server is bound to. Useful when started with port `0`. |
| `serverClose` | `(ServerSocket) -> Task<Unit>` | Close the server socket. Pending `accept` calls will fail. |

### Security notes

- `tlsConnect` uses the system trust store and enables **hostname verification** by default. There is no API to disable these checks.
- Raw socket access (server and client) is intentionally low-level. Servers must not run with elevated OS trust without host hardening.

### Typical usage

**TCP client (HTTP/1.0 GET):**
```kestrel
import * as Socket from "kestrel:socket"

async fun run(): Task<Unit> = {
  val sock = await Socket.tcpConnect("example.com", 80);
  await Socket.sendText(sock, "GET / HTTP/1.0\r\nHost: example.com\r\n\r\n");
  val resp = await Socket.readAll(sock);
  await Socket.close(sock);
  println(resp)
}
```

**TLS client (HTTPS):**
```kestrel
import * as Socket from "kestrel:socket"

async fun run(): Task<Unit> = {
  val sock = await Socket.tlsConnect("example.com", 443);
  await Socket.sendText(sock, "GET / HTTP/1.0\r\nHost: example.com\r\n\r\n");
  val resp = await Socket.readAll(sock);
  await Socket.close(sock);
  println(resp)
}
```

**TCP server (one connection):**
```kestrel
import * as Socket from "kestrel:socket"

async fun handleConn(ss: Socket.ServerSocket): Task<String> = {
  val conn = await Socket.accept(ss);
  val msg = await Socket.readAll(conn);
  await Socket.close(conn);
  msg
}

async fun run(): Task<Unit> = {
  val ss = await Socket.listen("127.0.0.1", 0);
  val serverTask = handleConn(ss);
  val client = await Socket.tcpConnect("127.0.0.1", Socket.serverPort(ss));
  await Socket.sendText(client, "hello");
  await Socket.close(client);
  val received = await serverTask;
  await Socket.serverClose(ss);
  println(received)
}
```

---

## kestrel:web

Lightweight routing framework built on top of `kestrel:http`. Provides Sinatra-style route registration (pattern matching, path parameters, wildcard segments) and automatic 404/405 responses. Implemented entirely in Kestrel — no additional JVM primitives.

### Overview

A `Router` holds an ordered list of registered routes. `serve(router)` produces a `(Http.Request) -> Task<Http.Response>` suitable for `Http.createServer`. Requests are dispatched to the **first matching route** (first-match-wins). Unmatched paths return `404 Not Found`; a path that exists but with a different HTTP method returns `405 Method Not Allowed`.

### Types

| Type | Description |
|------|-------------|
| `Router` | Record `{ routes: List<Route> }`. Opaque in practice; created with `newRouter()` and updated by `route`/`get`/etc. through function calls or the pipeline operator. |
| `PathSegment` | ADT used internally for compiled route patterns: `Literal(String)` (exact segment), `Param(String)` (named capture, e.g. `:id`), `Wildcard` (matches any suffix). Not exported; used by internal helpers. |

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `newRouter` | `() -> Router` | Create an empty router with no routes. |
| `route` | `(Router, String, String, (Http.Request, Dict<String, String>) -> Task<Http.Response>) -> Router` | Register a route for the given HTTP method (case-insensitive) and URL pattern. Returns a **new** `Router` with the route appended (immutable update; original is unchanged). Routes match in registration order. |
| `get` | `(Router, String, (Http.Request, Dict<String, String>) -> Task<Http.Response>) -> Router` | Shorthand for `route(router, "GET", pattern, handler)`. |
| `post` | `(Router, String, (Http.Request, Dict<String, String>) -> Task<Http.Response>) -> Router` | Shorthand for `route(router, "POST", pattern, handler)`. |
| `put` | `(Router, String, (Http.Request, Dict<String, String>) -> Task<Http.Response>) -> Router` | Shorthand for `route(router, "PUT", pattern, handler)`. |
| `delete` | `(Router, String, (Http.Request, Dict<String, String>) -> Task<Http.Response>) -> Router` | Shorthand for `route(router, "DELETE", pattern, handler)`. |
| `patch` | `(Router, String, (Http.Request, Dict<String, String>) -> Task<Http.Response>) -> Router` | Shorthand for `route(router, "PATCH", pattern, handler)`. |
| `serve` | `(Router) -> (Http.Request) -> Task<Http.Response>` | Return a request handler closure suitable for `Http.createServer`. The closure dispatches each request against the router's routes. |

### Route patterns

Patterns are URL paths with optional dynamic segments:

| Syntax | Meaning |
|--------|---------|
| `/literal` | Matches the exact segment `literal`. |
| `/:name` | Matches any single segment; captured as `name` in the params dictionary. |
| `/*` | Wildcard: matches the current segment and all remaining segments (tail-match). |

Pattern matching is case-sensitive. The leading `/` is optional in patterns. Segments are split on `/`. The wildcard `*` short-circuits: once encountered as a pattern segment, the rest of the path is consumed without further matching.

**Example:**
```kestrel
val router =
  Web.newRouter()
  |> Web.get("/hello", helloHandler)
  |> Web.get("/greet/:name", greetHandler)
  |> Web.get("/files/*", fileHandler)
```

### Handler signature

Handlers receive the raw `Http.Request` and a `Dict<String, String>` of captured path parameters:

```kestrel
async fun greetHandler(req: Http.Request, params: Dict<String, String>): Task<Http.Response> = {
  val name = match (Dict.get(params, "name")) {
    Some(n) => n,
    None => "stranger"
  };
  Http.makeResponse(200, "Hello ${name}")
}
```

### Default responses

- **404 Not Found** — no route pattern (for any method) matches the request path.
- **405 Method Not Allowed** — at least one route matches the path, but none matches the method.
- Body text is plain text (`"Not Found"` / `"Method Not Allowed"`).

### Typical usage

```kestrel
import * as Http from "kestrel:http"
import * as Web from "kestrel:web"

async fun run(): Task<Unit> = {
  val router =
    Web.newRouter()
    |> Web.get("/hello", (req, _p) => Http.makeResponse(200, "Hello!"))
    |> Web.post("/echo", (req, _p) => Http.makeResponse(200, Http.bodyText(req)));

  val server = await Http.createServer(Web.serve(router));
  await Http.listen(server, { host = "0.0.0.0", port = 8080 });
  ()
}

run()
```

---

## Standard Types

Types referenced in the above signatures are part of the standard contract:

- `Option<T>` – Optional value (e.g. from `queryParam`)
- `Task<T>` – Async computation
- `Value` – JSON value ADT exported from `kestrel:json` (see below)
- `Server`, `Request`, `Response` – HTTP opaque types from `kestrel:http`; backed by JDK classes (`com.sun.net.httpserver.HttpServer`, `com.sun.net.httpserver.HttpExchange`, and an implementation-defined response type respectively). See §`kestrel:http`.
- `StackTrace<T>` – Stack trace for a thrown value of type `T` (see **kestrel:stack** above; reference stdlib uses the record shape `{ value, frames }`).

Their concrete definitions are implementation-defined as long as the function signatures are satisfied; **`StackTrace<T>`** in the reference stdlib matches the record layout described under **kestrel:stack**.

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

`Value` is an **algebraic data type** representing a JSON value, **defined and exported** from **`kestrel:json`**. It is a normal per-module ADT in bytecode (not a reserved built-in ADT row). The ADT has one constructor per JSON kind:

| Constructor | Payload | JSON equivalent |
|-------------|---------|------------------|
| `Null` | — | `null` |
| `Bool` | `Bool` | `true` / `false` |
| `Int` | `Int` | integer number |
| `Float` | `Float` | floating-point number |
| `StrVal` | `String` | JSON string (name avoids clashing with the `String` type) |
| `Array` | `List<Value>` | array `[ ... ]` |
| `Object` | `List<(String, Value)>` | object `{ ... }` |

Pattern matching on `Value` allows programs to inspect and build JSON values in a typed way.
