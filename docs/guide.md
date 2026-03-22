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
print(result)
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
// Integers (61-bit signed)
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

---

## Types

### Type inference

Kestrel uses Hindley–Milner type inference. You rarely need to write types, but you always can:

```kestrel
fun length(xs: List[Int]): Int = match (xs) {
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
fun sum(xs: List[Int]): Int = match (xs) {
  [] => 0
  head :: tail => head + sum(tail)
}
```

The `kestrel:list` module provides the usual toolkit — `map`, `filter`, `foldl`, `reverse`, `sort`, and more. See the [Standard Library](#standard-library) section.

### Records

Records are structural — they are defined by their fields, not by a name:

```kestrel
val alice = { name: "Alice", age: 30 }
val n = alice.name   // "Alice"
```

Records support spread syntax for creating modified copies:

```kestrel
val bob = { ...alice, name: "Bob" }
```

Fields can be declared `mut` for local mutation:

```kestrel
val counter = { mut value: 0 }
counter.value := 42
```

Kestrel has row polymorphism: a function that reads `.x` will accept any record that has an `x` field, regardless of what other fields are present:

```kestrel
fun getX(r) = r.x

val a = getX({ x: 1, y: 2 })          // 1
val b = getX({ x: 10, y: 20, z: 30 }) // 10
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

The `kestrel:tuple` module provides `first`, `second`, `mapFirst`, `mapSecond`, and `mapBoth` for pairs.

---

## Error Handling

Kestrel provides three mechanisms for dealing with failure, each suited to different situations.

### Option

`Option<T>` represents a value that might be absent:

```kestrel
import { map, getOrElse } from "kestrel:option"

fun safeDivide(a: Int, b: Int): Option<Int> =
  if (b == 0) None else Some(a / b)

val result = safeDivide(10, 0) |> getOrElse(0)
// result is 0
```

Pattern matching works naturally:

```kestrel
fun describe(opt: Option<Int>): String = match (opt) {
  Some { value = n } => "Got ${n}"
  None => "Nothing"
}
```

### Result

`Result<T, E>` represents an operation that might fail with an error value:

```kestrel
import { map, andThen } from "kestrel:result"

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
  Ok { value = n } => "Success: ${n}"
  Err { value = e } => "Error: ${e}"
}
```

### Exceptions

For truly exceptional situations, Kestrel has `throw` and `try`/`catch`:

```kestrel
exception DivByZero {}

fun divide(a: Int, b: Int): Int =
  if (b == 0) throw DivByZero {} else a / b

val safe = try { divide(10, 0) } catch {
  DivByZero {} => 0
}
// safe is 0
```

Exceptions are declared with the `exception` keyword and can carry fields. Prefer `Option` and `Result` for expected failure paths; reserve exceptions for situations where recovery is the caller's responsibility.

---

## Modules

### Importing

Kestrel files are modules. Import specific bindings or an entire namespace:

```kestrel
// Named imports
import { length, map, filter } from "kestrel:list"

// Namespace import
import * as Str from "kestrel:string"

val n = Str.length("hello")  // 5
```

Relative imports use file paths:

```kestrel
import { helper } from "./utils.ks"
```

### Exporting

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
| `kestrel:string` | String manipulation — `length`, `slice`, `split`, `join`, `trim`, `replace`, and more |
| `kestrel:list` | List operations — `map`, `filter`, `foldl`, `sort`, `reverse`, `zip`, and more |
| `kestrel:option` | Option helpers — `map`, `andThen`, `getOrElse`, `withDefault` |
| `kestrel:result` | Result helpers — `map`, `mapError`, `andThen`, `toOption` |
| `kestrel:dict` | Dictionary (key-value map) — `insert`, `get`, `remove`, `union`, `fold` |
| `kestrel:set` | Set — `insert`, `member`, `union`, `intersect`, `diff` |
| `kestrel:char` | Character classification — `isDigit`, `isAlpha`, `toUpper`, `toLower` |
| `kestrel:tuple` | Pair helpers — `first`, `second`, `mapFirst`, `mapSecond` |
| `kestrel:basics` | Numeric utilities — `clamp`, `negate`, `toFloat`, `floor`, `sqrt`, `identity` |
| `kestrel:json` | JSON parsing — `parse`, `stringify` |
| `kestrel:fs` | File system — `readText`, `writeText`, `listDir` |

---

## Pipelines

The pipeline operators thread values through functions, letting you write chains that read left-to-right:

```kestrel
import { map, filter, sum } from "kestrel:list"

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
import * as Str from "kestrel:string"

val cleaned = "  Hello, World!  "
  |> Str.trim
  |> Str.toLowerCase
  |> Str.replace("world", "kestrel")
// cleaned is "hello, kestrel!"
```

---

## A larger example

Here is a string calculator that supports custom delimiters, combining several features from this guide — modules, pattern matching, pipelines, and error handling:

```kestrel
import { split, left, dropLeft, length, indexOf } from "kestrel:string"
import { map, filter, foldl } from "kestrel:list"
import { andThen, getOrElse } from "kestrel:result"

fun parseDelimiter(input: String): (String, String) =
  if (left(2, input) == "//") {
    val rest = dropLeft(2, input)
    val nlIdx = indexOf("\n", rest) |> getOrElse(length(rest))
    val delim = left(nlIdx, rest)
    val body = dropLeft(nlIdx + 1, rest)
    (delim, body)
  } else {
    (",", input)
  }

fun calculate(input: String): Int = {
  val (delim, body) = parseDelimiter(input)

  body
  |> split(delim)
  |> filter((s) => s != "")
  |> map((s) => s |> parseInt |> getOrElse(0))
  |> foldl((acc, n) => acc + n, 0)
}
```

```bash
# "//;\n1;2;3" -> uses ";" as delimiter -> 6
```

---

## Testing

Kestrel has a built-in test framework. Test files end in `.test.ks` and use the `kestrel:test` module:

```kestrel
import { Suite, group, eq } from "kestrel:test"

export fun suite(s: Suite): Suite =
  s
  |> group("arithmetic", (s) =>
    s
    |> eq("1 + 1", 1 + 1, 2)
    |> eq("2 * 3", 2 * 3, 6)
  )
  |> group("strings", (s) =>
    s
    |> eq("greeting", "Hello, ${"world"}!", "Hello, world!")
  )
```

Run tests from the repository root:

```bash
./kestrel test                          # all tests
./kestrel test tests/unit/match.test.ks # one file
```

Tests can be nested with `group` for structure, and `eq` performs deep structural equality.

---

## Installation

You need **Node.js 18+** and **Zig** (current stable). Optionally, **JDK 11+** for the JVM backend.

```bash
# Clone and build
git clone https://github.com/graemelockley/kestrel.git
cd kestrel
cd compiler && npm install && npm run build && cd ..
cd vm && zig build && cd ..

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
- **Planned work** — [docs/kanban/backlog/](kanban/backlog/) lists features and improvements in the pipeline.

Kestrel is under active development. Contributions are welcome — see [CONTRIBUTING.md](../CONTRIBUTING.md).
