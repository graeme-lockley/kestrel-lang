# An Introduction to Kestrel

**Kestrel is a statically typed language that compiles to bytecode.** It has Hindley–Milner type inference, algebraic data types, pattern matching, and a pipeline operator. You write programs that feel like scripts; the compiler checks them carefully.

This guide will:

- Teach you the fundamentals of programming in Kestrel.
- Show you how types, pattern matching, and pipelines work together.
- Walk through the standard library and module system.

By the end you should be comfortable reading and writing Kestrel programs. Let's start with a small example.

## A quick sample

Here is a program that computes the tenth Fibonacci number:

```kestrel
fun fibonacci(n: Int): Int =
  if (n <= 1) n else fibonacci(n - 1) + fibonacci(n - 2)

val result = fibonacci(10)
println(result)
```

Save it as `hello.ks` and run it:

```bash
./kestrel run hello.ks
# prints 55
```

The compiler infers types wherever it can, but the annotation `(n: Int): Int` makes the signature clear to readers. The rest of this guide explains each feature step by step.

---

## Core Language

### Values

Kestrel has a small set of built-in value types:

```kestrel
// Integers (64-bit signed)
val age = 30
val hex = 0xFF
val binary = 0b1010

// Floats (64-bit)
val pi = 3.14159
val sci = 1.5e3

// Booleans
val yes = True
val no = False

// Strings (with template interpolation)
val name = "Kestrel"
val greeting = "Hello, ${name}!"

// Characters (Unicode code points)
val letter = 'A'
val emoji = '😀'

// Unit (the type with one value)
val nothing = ()
```

String interpolation uses `${expr}` inside double quotes. You can put any expression between the braces.

### Functions

Functions are defined with the `fun` keyword. The body is a single expression after `=`:

```kestrel
fun double(x: Int): Int = x * 2

fun greet(name: String): String = "Hello, ${name}!"
```

When the compiler can figure out the types, annotations are optional:

```kestrel
fun add(a, b) = a + b
```

Functions are first-class values. You can pass them around and return them:

```kestrel
fun applyTwice(f: (Int) -> Int, x: Int): Int = f(f(x))

val result = applyTwice(double, 3)
// result is 12
```

### Lambdas

Anonymous functions use the `=>` arrow:

```kestrel
val increment = (x: Int) => x + 1

val result = increment(5)
// result is 6
```

They close over their environment:

```kestrel
val base = 100
val addBase = (x: Int) => x + base
// addBase(5) is 105
```

### If expressions

`if` is an expression — both branches produce a value:

```kestrel
val message = if (age >= 18) "adult" else "minor"
```

You can chain them:

```kestrel
fun classify(n: Int): String =
  if (n < 0) "negative"
  else if (n == 0) "zero"
  else "positive"
```

### Blocks

A block is a sequence of declarations followed by an expression. The block evaluates to its final expression:

```kestrel
val result = {
  val x = 10
  val y = 20
  x + y
}
// result is 30
```

Blocks can contain `var` bindings, which are mutable within the block:

```kestrel
val count = {
  var n = 0
  n := n + 1
  n := n + 1
  n
}
// count is 2
```

The `:=` operator assigns to a `var`. Normal `val` bindings are immutable.

### Operators

Arithmetic: `+`, `-`, `*`, `/`, `%`, `**` (exponentiation, right-associative).

Comparison: `==`, `!=`, `<`, `<=`, `>`, `>=`. These work on integers, floats, strings, booleans, lists, records, tuples, and ADTs — they compare structurally.

Logical: `&` (and), `|` (or), `!` (not). Short-circuit evaluation applies to `&` and `|`.

```kestrel
val a = 2 + 3 * 4    // 14 (standard precedence)
val b = 2 ** 3 ** 2   // 512 (right-associative: 2^(3^2))
val c = True & !False  // True
```

**Integer bounds and errors:** `Int` is a fixed-width signed type (64-bit). If an `+`, `-`, or `*` result does not fit, the runtime throws **`ArithmeticOverflow`**. **`/`** and **`%`** throw **`DivideByZero`** when the divisor is zero. Both are standard-library exception ADTs from **`kestrel:sys/runtime`** — import them so your `catch` patterns match what the runtime throws (see [Exceptions](#exceptions) below).

---

## Types

### Type inference

Kestrel uses Hindley–Milner type inference. You rarely need to write types, but you always can:

```kestrel
fun length(xs: List<Int>): Int = match (xs) {
  [] => 0
  _ :: tail => 1 + length(tail)
}
```

The compiler will catch type errors at compile time:

```kestrel
// This won't compile — can't add a String to an Int
val bad = 1 + "hello"
```

### Polymorphism

Functions can be generic. The compiler infers type variables automatically:

```kestrel
fun identity(x) = x

val a = identity(42)       // Int
val b = identity("hello")  // String
```

You can also write the type variables explicitly:

```kestrel
fun first<A, B>(a: A, b: B): A = a
```

### Custom types (ADTs)

Algebraic data types are declared with the `type` keyword. Each variant is a constructor:

```kestrel
type Color = Red | Green | Blue
```

Constructors can carry data:

```kestrel
type Shape =
    Circle(Float)
  | Rectangle(Float, Float)
```

Types can be generic:

```kestrel
type Tree<T> = Leaf(T) | Node(Tree<T>, Tree<T>)
```

And mutually recursive:

```kestrel
type Expr = Lit(Int) | Add(Expr, Expr) | IfExpr(Cond, Expr, Expr)
type Cond = IsZero(Expr) | And(Cond, Cond)
```

### Pattern matching

`match` expressions destructure values. The compiler checks that patterns are exhaustive — every case is covered:

```kestrel
fun describe(c: Color): String = match (c) {
  Red => "red"
  Green => "green"
  Blue => "blue"
}
```

Patterns can bind variables and nest:

```kestrel
fun area(s: Shape): Float = match (s) {
  Circle(r) => 3.14159 * r * r
  Rectangle(w, h) => w * h
}
```

```kestrel
fun treeSum(t: Tree<Int>): Int = match (t) {
  Leaf(v) => v
  Node(left, right) => treeSum(left) + treeSum(right)
}
```

The wildcard `_` matches anything without binding:

```kestrel
fun isRed(c: Color): Bool = match (c) {
  Red => True
  _ => False
}
```

### Opaque types

A module can export a type without exposing its constructors. Consumers can refer to the type in their signatures but cannot construct or destructure it:

```kestrel
// token.ks
opaque type Token = Num(Int) | Op(String) | Eof

export fun makeNum(n: Int): Token = Num(n)

export fun tokenToInt(t: Token): Int = match (t) {
  Num(n) => n
  Op(_) => 0
  Eof => -1
}
```

This is how the standard library hides internal data structures like `Dict` and `Set`.

---

## Data Structures

### Lists

Lists are immutable, singly linked, and homogeneous:

```kestrel
val empty = []
val numbers = [1, 2, 3, 4, 5]
val withZero = 0 :: numbers   // cons: prepend an element
```

Pattern matching on lists is the primary way to work with them:

```kestrel
fun sum(xs: List<Int>): Int = match (xs) {
  [] => 0
  head :: tail => head + sum(tail)
}
```

The `kestrel:data/list` module provides the usual toolkit — `map`, `filter`, `foldl`, `reverse`, `sort`, and more. See the [Standard Library](#standard-library) section.

### Records

Records are structural — they are defined by their fields, not by a name:

```kestrel
val alice = { name = "Alice", age = 30 }
val n = alice.name   // "Alice"
```

Records support spread syntax for creating modified copies:

```kestrel
val bob = { ...alice, name = "Bob" }
```

Fields can be declared `mut` for local mutation:

```kestrel
val counter = { mut value = 0 }
counter.value := 42
```

Kestrel has row polymorphism: a function that reads `.x` will accept any record that has an `x` field, regardless of what other fields are present:

```kestrel
fun getX(r) = r.x

val a = getX({ x = 1, y = 2 })          // 1
val b = getX({ x = 10, y = 20, z = 30 }) // 10
```

### Tuples

Tuples are fixed-size, heterogeneous collections. Access elements by position:

```kestrel
val pair = (10, "hello")
val x = pair.0    // 10
val y = pair.1    // "hello"

val triple = (1, True, "abc")
val flag = triple.1  // True
```

The `kestrel:data/tuple` module provides `first`, `second`, `mapFirst`, `mapSecond`, and `mapBoth` for pairs.

---

## Error Handling

Kestrel provides three mechanisms for dealing with failure, each suited to different situations.

### Option

`Option<T>` represents a value that might be absent:

```kestrel
import { map, getOrElse } from "kestrel:data/option"

fun safeDivide(a: Int, b: Int): Option<Int> =
  if (b == 0) None else Some(a / b)

val result = safeDivide(10, 0) |> getOrElse(0)
// result is 0
```

Pattern matching works naturally:

```kestrel
fun describe(opt: Option<Int>): String = match (opt) {
  Some(n) => "Got ${n}"
  None => "Nothing"
}
```

### Result

`Result<T, E>` represents an operation that might fail with an error value:

```kestrel
import { map, andThen } from "kestrel:data/result"

fun parseInt(s: String): Result<Int, String> =
  // ... parsing logic ...

fun double(n: Int): Int = n * 2

// Chain operations that might fail
val answer = parseInt("42") |> map(double)
// answer is Ok(84)
```

The pattern matching syntax mirrors Option:

```kestrel
match (result) {
  Ok(n) => "Success: ${n}"
  Err(e) => "Error: ${e}"
}
```

### Exceptions

For truly exceptional situations, Kestrel has `throw` and `try`/`catch`.

**Built-in integer traps:** Overflow and divide-by-zero from the built-in operators use the canonical types exported by **`kestrel:sys/runtime`**. Import **`ArithmeticOverflow`** and **`DivideByZero`** so handlers can match the values the runtime constructs:

```kestrel
import { ArithmeticOverflow, DivideByZero } from "kestrel:sys/runtime"

val ok = try { 1 / 0 } catch {
  DivideByZero => 0
}
```

**User-defined exceptions:** You can still declare your own exception ADTs and `throw` them — useful when failure is a deliberate API choice, not only a hardware-style trap:

```kestrel
exception DivByZero {}

fun divide(a: Int, b: Int): Int =
  if (b == 0) throw DivByZero {} else a / b

val safe = try { divide(10, 0) } catch {
  DivByZero {} => 0
}
// safe is 0
```

Note that **`a / b`** and **`a % b`** already throw **`kestrel:sys/runtime`'s `DivideByZero`** when `b == 0`; the example above is for wrapping logic that chooses to signal failure with a *custom* exception type.

Exceptions are declared with the `exception` keyword and can carry fields. Prefer `Option` and `Result` for expected failure paths; reserve exceptions for situations where recovery is the caller's responsibility.

---

## Modules

### Importing

Kestrel files are modules. Import specific bindings or an entire namespace:

```kestrel
// Named imports
import { length, map, filter } from "kestrel:data/list"

// Namespace import
import * as Str from "kestrel:data/string"

val n = Str.length("hello")  // 5
```

If a module exports an ADT (not `opaque`), you can use its constructors through the namespace: nullary constructors are values (`Lib.Eof`), and n-ary ones use call syntax (`Lib.Pair(1, 2)`), same rules as unqualified constructors (see [Language spec — ADTs](specs/06-typesystem.md)).

Relative imports use file paths:

```kestrel
import { helper } from "./utils.ks"
```

### URL imports

Kestrel can import modules directly from the web using `https://` (or `http://` with `--allow-http`):

```kestrel
import * as Lib from "https://example.com/lib.ks"

fun main(): Unit = println(Lib.greet("world"))
```

On first use the compiler fetches the source and caches it under `~/.kestrel/cache/<sha256-of-url>/source.ks`. Subsequent builds use the cached copy with no network request. If the remote module contains relative imports (e.g. `"./dir/utils.ks"`), those are resolved against the **base URL** of the remote file and fetched transitively — the entire dependency tree is cached in a single pass.

Useful flags:

| Flag | Command | Effect |
|------|---------|--------|
| `--refresh` | `run`, `build` | Re-download all URL dependencies even when cached |
| `--allow-http` | `run`, `build` | Accept `http://` imports (HTTPS only by default) |
| `--status` | `build` only | Print cache state for every URL dependency; do not compile |

```bash
# Show cache status without building
kestrel build --status main.ks

# Force re-download of all URL dependencies
kestrel run --refresh main.ks
```

Cache location defaults to `~/.kestrel/cache/`; override with `KESTREL_CACHE`. Staleness threshold defaults to 7 days; override with `KESTREL_CACHE_TTL` (seconds).



Mark declarations with `export` to make them available to other modules:

```kestrel
export fun add(a: Int, b: Int): Int = a + b

export val pi = 3.14159

export type Direction = North | South | East | West
```

Use `opaque` to export a type name without its constructors:

```kestrel
export opaque type Token = Num(Int) | Op(String) | Eof
```

### Standard library modules

The standard library ships as `kestrel:*` modules:

| Module | Purpose |
|--------|---------|
| `kestrel:sys/runtime` | Canonical **`ArithmeticOverflow`** and **`DivideByZero`** exception ADTs (VM throws these for integer overflow and div/mod by zero) |
| `kestrel:data/string` | String manipulation — `length`, `slice`, `split`, `join`, `trim`, `replace`, `indexOf`, `toLowerCase`, and more |
| `kestrel:data/list` | List operations — `map`, `filter`, `foldl`, `sort`, `reverse`, `zip`, `sum`, `range`, and more |
| `kestrel:data/option` | Option helpers — `map`, `andThen`, `getOrElse`, `withDefault` |
| `kestrel:data/result` | Result helpers — `map`, `mapError`, `andThen`, `toOption` |
| `kestrel:data/dict` | Dictionary (key-value map) — `insert`, `get`, `remove`, `union`, `fold` |
| `kestrel:data/set` | Set — `insert`, `member`, `union`, `intersect`, `diff` |
| `kestrel:data/char` | Character classification — `isDigit`, `isAlpha`, `toUpper`, `toLower` |
| `kestrel:data/tuple` | Pair helpers — `first`, `second`, `mapFirst`, `mapSecond` |
| `kestrel:data/basics` | Numeric utilities — `clamp`, `negate`, `toFloat`, `floor`, `sqrt`, `identity` |
| `kestrel:data/json` | JSON — `parse` (`Result<Value, JsonParseError>`), `parseOrNull`, `stringify`, `errorAsString`; `Value` and `JsonParseError` ADTs |
| `kestrel:data/array` | Mutable arrays — `new`, `get`, `set`, `push`, `length`, `fromList`, `toList` |
| `kestrel:data/bytearray` | Mutable byte sequences — `new`, `length`, `get`, `set`, `fromList`, `toList`, `concat`, `slice` |
| `kestrel:data/int` | Integer utilities — `random`, `randomRange` |
| `kestrel:io/fs` | File system — `readText`, `writeText`, `listDir` |
| `kestrel:io/console` | Terminal utilities — ANSI colour constants, `terminalInfo`, `eprintln` |
| `kestrel:io/http` | HTTP client and server — `get`, `request`, `createServer`, `listen` |
| `kestrel:sys/process` | Process execution and environment — `getEnv`, `exit`, `runProcess` |
| `kestrel:sys/task` | Task combinators — `map`, `all`, `race`, `cancel` |
| `kestrel:dev/test` | Test framework — `Suite`, `group`, `eq`, `neq`, `isTrue`, `isFalse`, `throws` |

---

## Java interop

Kestrel programs run on the JVM and can call any Java class directly.

### extern fun

`extern fun` binds a Kestrel function name to a JVM static method, instance method, or constructor without writing a Java wrapper:

```kestrel
// Static method: String.valueOf(Object) -> String
extern fun intToString(n: Int): String = jvm("java.lang.String#valueOf(java.lang.Object)")

// Instance method: first param is the receiver, rest are arguments
extern fun concatStrings(a: String, b: String): String = jvm("java.lang.String#concat(java.lang.String)")
extern fun strToUpper(s: String): String = jvm("java.lang.String#toUpperCase()")
```

The JVM specifier format is `"ClassName#methodName(ArgType,…)"`. For constructors use `<init>` as the method name. When an `extern fun` is declared as an instance method, the **first parameter** is the receiver object; all remaining parameters are the Java arguments.

> **Boxing note:** Kestrel `Int` maps to JVM `java.lang.Long`, `Float` to `java.lang.Double`, and `Bool` to `java.lang.Boolean`. JVM methods that return a primitive type (e.g. `int`, `double`) cannot be bound directly because the generated descriptor expects the boxed return type. Use methods that return reference types (`String`, or any `extern type`) or KRuntime wrapper methods that already return boxed values.

### extern type

`extern type` introduces a nominal Kestrel type that corresponds to a JVM class. This lets you write `extern fun` declarations that mention the class as a parameter or return type, and the compiler will generate the correct JVM descriptor:

```kestrel
extern type StringBuilder = jvm("java.lang.StringBuilder")

extern fun newStringBuilder(): StringBuilder =
  jvm("java.lang.StringBuilder#<init>()")

extern fun sbAppend(sb: StringBuilder, s: String): StringBuilder =
  jvm("java.lang.StringBuilder#append(java.lang.String)")

extern fun sbToString(sb: StringBuilder): String =
  jvm("java.lang.StringBuilder#toString()")

val greeting =
  newStringBuilder()
  |> sbAppend("Hello")
  |> sbAppend(", World")
  |> sbToString
// greeting is "Hello, World"
```

### extern import

`extern import` reads a JVM class's public API via `javap` at compile time and auto-generates an `extern type` plus `extern fun` declarations for every public constructor and method:

```kestrel
extern import "java:java.lang.StringBuilder" as SB { }
```

After this declaration `newSB`, `append`, `toString`, etc. are all available in scope, generated automatically. The optional override block `{ fun … }` lets you correct specific method signatures — useful when the auto-generated return type is wrong:

```kestrel
extern import "java:java.lang.StringBuilder" as SB {
  // Override the return type of append to SB so the JVM descriptor matches
  fun append(instance: SB, p0: String): SB
}

val msg = newSB() |> append("Kestrel") |> append(" rocks") |> toString
// msg is "Kestrel rocks"
```

Supported import schemes:

| Scheme | Example | Description |
|--------|---------|-------------|
| `java:` | `"java:java.util.ArrayList"` | JDK or classpath class |
| `maven:g:a:v#Class` | `"maven:com.google.guava:guava:33.3.1-jre#com.google.common.collect.ImmutableList"` | Class inside a Maven artifact |

### Maven dependencies

Pull in a Maven artifact as a compile-time and runtime classpath entry with the side-effect import form:

```kestrel
import "maven:com.google.guava:guava:33.3.1-jre"

extern import "java:com.google.common.collect.ImmutableList" as ImmutableList { }
```

The compiler downloads the JAR to `~/.kestrel/maven/` on first use and records it in a `.kdeps` sidecar. `kestrel run` picks up `.kdeps` transitively so you never need to pass classpath flags manually.

---

## Pipelines

The pipeline operators thread values through functions, letting you write chains that read left-to-right:

```kestrel
import { map, filter, sum } from "kestrel:data/list"

val result =
  [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  |> filter((n) => n % 2 == 0)
  |> map((n) => n * n)
  |> sum
// result is 220 (4 + 16 + 36 + 64 + 100)
```

`|>` passes the left-hand side as the **first** argument to the right-hand function. `<|` passes the right-hand side as the **last** argument to the left-hand function:

```kestrel
fun add(a: Int, b: Int): Int = a + b

val x = 3 |> add(10)   // add(3, 10) = 13
val y = add(10) <| 3    // add(10, 3) = 13
```

Pipelines compose well with the standard library, which consistently takes the "data" argument first:

```kestrel
import * as Str from "kestrel:data/string"

val cleaned = "  Hello, World!  "
  |> Str.trim
  |> Str.toLowerCase
  |> (s) => Str.replace("world", "kestrel", s)
// cleaned is "hello, kestrel!"
```

---

## A larger example

Here is a string calculator that supports custom delimiters, combining several features from this guide — modules, pattern matching, pipelines, and error handling:

```kestrel
import { split, left, dropLeft, indexOf, parseInt } from "kestrel:data/string"
import { map, filter, sum } from "kestrel:data/list"

fun parseDelimiter(input: String): (String, String) =
  if (left(input, 2) == "//") {
    val rest = dropLeft(input, 2)
    val nlIdx = indexOf(rest, "\n")
    val delim = if (nlIdx < 0) rest else left(rest, nlIdx)
    val body = if (nlIdx < 0) "" else dropLeft(rest, nlIdx + 1)
    (delim, body)
  } else {
    (",", input)
  }

fun calculate(input: String): Int = {
  val (delim, body) = parseDelimiter(input)

  body
  |> split(delim)
  |> filter((s) => s != "")
  |> map((s) => parseInt(s))
  |> sum
}
```

```bash
# "//;\n1;2;3" -> uses ";" as delimiter -> 6
```

---

## Testing

Kestrel has a built-in test framework. Test files end in `.test.ks` and export `run(s: Suite): Task<Unit>`. Use `kestrel:dev/test` for assertions and grouping:

```kestrel
import { Suite, group, eq, neq, isTrue, isFalse, gt, gte, throws } from "kestrel:dev/test"

export async fun run(s: Suite): Task<Unit> = {
  group(s, "arithmetic", (s1: Suite) => {
    eq(s1, "add", 1 + 1, 2);
    neq(s1, "not three", 1 + 1, 3);
    gt(s1, "order", 3, 2);
    gte(s1, "tie ok", 2, 2)
  });
  group(s, "booleans", (s1: Suite) => {
    isTrue(s1, "t", True);
    isFalse(s1, "f", False)
  });
  group(s, "exceptions", (s1: Suite) => {
    throws(s1, "div by zero", (_: Unit) => {
      1 / 0
    })
  })
}
```

`throws` takes a **`(Unit) -> Unit`** thunk and calls it with `()` — the language does not write `() -> Unit` as a type, so use `(_: Unit) => …`.

On failure, `eq` prints labelled lines (`expected (right)` / `actual (left)`) plus a short note that comparison is deep structural equality; ordering helpers label operands as `Int`; `isTrue`/`isFalse` label `Bool`.

Run tests from the repository root:

```bash
./kestrel test                           # all tests (tests/unit + stdlib/kestrel)
./kestrel test tests/unit/match.test.ks  # one file
./kestrel test --verbose                 # per-assertion output
./kestrel test --summary                 # one line per suite
```

The runner ends with `printSummary(counts)` (see `scripts/run_tests.ks`): if any assertion failed, the process exits with code **1**.

---

## Installation

You need **Node.js 18+** and **JDK 11+**.

```bash
# Clone and build
git clone https://github.com/graemelockley/kestrel.git
cd kestrel
cd compiler && npm install && npm run build && cd ..

# Run a program
./kestrel run hello.ks
```

To use `kestrel` from anywhere, symlink the wrapper script. It resolves its install location automatically:

```bash
ln -s /path/to/kestrel/kestrel ~/.local/bin/kestrel
```

See the [CLI reference](specs/09-tools.md) for all commands.

---

## Next steps

This guide covered the core language. There is more to explore:

- **Specifications** — the [docs/specs/](specs/) directory contains normative specs for the language, type system, bytecode format, and standard library.
- **Standard library source** — read the implementations in [stdlib/kestrel/](../stdlib/kestrel/) to see idiomatic Kestrel.
- **Test suite** — the [tests/unit/](../tests/unit/) directory has runnable examples of every language feature.
- **Kanban** — [docs/kanban/future/](kanban/future/) holds pre-roadmap investigations (`slug.md`, no numeric prefix). [docs/kanban/unplanned/](kanban/unplanned/) lists the prioritized roadmap (lower sequence = higher priority); completed stories live under [docs/kanban/done/](kanban/done/). Stories progress through **planned**, **doing**, and **done** as described in [docs/kanban/README.md](kanban/README.md).

If you are hacking on the self-hosted compiler, start with [stdlib/kestrel/compiler/diagnostics.ks](../stdlib/kestrel/compiler/diagnostics.ks), [stdlib/kestrel/compiler/reporter.ks](../stdlib/kestrel/compiler/reporter.ks), [stdlib/kestrel/compiler/types.ks](../stdlib/kestrel/compiler/types.ks), and [stdlib/kestrel/compiler/opcodes.ks](../stdlib/kestrel/compiler/opcodes.ks), which mirror the bootstrap compiler's diagnostic, internal-type, and JVM opcode foundations.

Kestrel is under active development. Contributions are welcome — see [CONTRIBUTING.md](../CONTRIBUTING.md).
