import { Suite, group, eq, isTrue, isFalse } from "kestrel:test"

// Minimal nested fun to trigger VM path (desugared to block val + lambda)
fun outerWithNested(): Int = { fun inner(): Int = 1; inner() }

fun fact(n: Int): Int = if (n == 0) 1 else n * fact(n - 1)

fun fib(n: Int): Int = if (n <= 1) n else fib(n - 1) + fib(n - 2)

fun safeDivide(a: Int, b: Int): Int = if (b == 0) 0 else a / b

fun double(x: Int): Int = x + x
fun triple(x: Int): Int = x * 3
fun square(x: Int): Int = x * x

fun increment(x: Int): Int = x + 1

fun sumList(xs: List<Int>): Int = match (xs) { [] => 0, h :: t => h + sumList(t) }

fun applyTwice(f: (Int) -> Int, x: Int): Int = f(f(x))

// "Closure" helpers (implemented via module-level vars; nested fun reads them)
var closureOffset = 0
var closureScale = 1

fun makeAdder(n: Int): (Int) -> Int = {
  closureOffset := n
  fun add(x: Int): Int = x + closureOffset
  add
}

// Closure over param only (for chained-call test makeAdd(2)(3))
fun makeAdd(a: Int): (Int) -> Int = { fun add(b: Int): Int = a + b; add }

fun nestedAsHOF(x: Int): Int = {
  closureOffset := 2
  closureScale := 3
  fun addOffset(n: Int): Int = n + closureOffset
  fun scale(n: Int): Int = n * closureScale
  applyTwice(scale, addOffset(x))
}


// Triple nesting: outer block -> inner block -> innermost block, each with a nested fun
fun level1(): Int = { fun level2(): Int = { fun level3(): Int = 99; level3() }; level2() }

// Top-level mutual recursion (isEven calls isOdd, isOdd calls isEven)
fun isEven(n: Int): Bool = if (n == 0) True else isOdd(n - 1)
fun isOdd(n: Int): Bool = if (n == 0) False else isEven(n - 1)

// Top-level generic lambda
val genId = <T>(x: T) => x

export fun run(s: Suite): Unit =
  group(s, "functions", (s1: Suite) => {
    group(s1, "basic calls", (sg: Suite) => {
      eq(sg, "double(3)", double(3), 6)
      eq(sg, "triple(4)", triple(4), 12)
      eq(sg, "square(5)", square(5), 25)
      eq(sg, "double(0)", double(0), 0)
      eq(sg, "increment(10)", increment(10), 11)
    })

    group(s1, "recursion", (sg: Suite) => {
      eq(sg, "safeDivide(10,2)", safeDivide(10, 2), 5)
      eq(sg, "safeDivide(10,0)", safeDivide(10, 0), 0)
      eq(sg, "safeDivide(15,3)", safeDivide(15, 3), 5)
      eq(sg, "fact(0) == 1", fact(0), 1)
      eq(sg, "fact(5) == 120", fact(5), 120)
      eq(sg, "fact(10) == 3628800", fact(10), 3628800)
      eq(sg, "fact(3)", fact(3), 6)
      eq(sg, "fib(0) == 0", fib(0), 0)
      eq(sg, "fib(1) == 1", fib(1), 1)
      eq(sg, "fib(5) == 5", fib(5), 5)
      eq(sg, "fib(10) == 55", fib(10), 55)
      eq(sg, "sumList([1,2,3])", sumList([1, 2, 3]), 6)
      isTrue(sg, "mutual recursion isEven(4)", isEven(4))
      isFalse(sg, "mutual recursion isEven(5)", isEven(5))
      isTrue(sg, "mutual recursion isOdd(3)", isOdd(3))
      isFalse(sg, "mutual recursion isOdd(4)", isOdd(4))
    })

    group(s1, "composition", (sg: Suite) => {
      eq(sg, "double(double(2))", double(double(2)), 8)
      eq(sg, "triple(double(3))", triple(double(3)), 18)
      eq(sg, "double(double(5))", double(double(5)), 20)
      eq(sg, "increment(increment(10))", increment(increment(10)), 12)
    })
    
    group(s1, "higher-order", (sg: Suite) => {
      eq(sg, "applyTwice lambda increment", applyTwice((x: Int) => x + 1, 0), 2)
      eq(sg, "applyTwice lambda double", applyTwice((x: Int) => x + x, 1), 4)
    })

    // Nested fun: parser emits block-level `fun` as FunStmt. Closures and self-recursion supported.
    group(s1, "nested fun", (sg: Suite) => {
      // Basic: declare and call in same block (no params)
      eq(sg, "outerWithNested()", outerWithNested(), 1)

      // Return nested fun and call from outside (module var as "closure")
      eq(sg, "makeAdder(2) then call", { val add2 = makeAdder(2); add2(3) }, 5)

      // Chained call: function returns closure, call result immediately (still returns () in some setups; prefer val add2 = makeAdd(2); add2(3))
      eq(sg, "makeAdd(2)(3) chained call", makeAdd(2)(3), 5)

      // Multiple nested funs in one block, passed to HOF
      eq(sg, "nestedAsHOF(1)", nestedAsHOF(1), 27)

      // Triple nesting: three blocks, each with one nested fun
      eq(sg, "level1() triple nesting", level1(), 99)

      // Two-parameter nested fun
      eq(sg, "nested two-param", { fun add(a: Int, b: Int): Int = a + b; add(2, 3) }, 5)

      // Same nested fun called twice in same block
      eq(sg, "nested called twice", { fun one(): Int = 1; one() + one() }, 2)

      // Inline block in expression position (nested fun, identity)
      eq(sg, "inline block nested", { fun id(x: Int): Int = x; id(10) }, 10)

      // Block with nested fun in if branch (nested fun in non-block expression context)
      eq(sg, "nested in if branch", if (True) { fun f(): Int = 2; f() } else 0, 2)

      // Recursive nested fun: block-level fac(5) in nested group closure.
      eq(sg, "recursive nested fac(5)", { fun fac(n: Int): Int = if (n <= 1) 1 else n * fac(n - 1); fac(5) }, 120)

      // Nested fun return type checked and matches body
      eq(sg, "nested fun return type ok", { fun ok(): Int = 42; ok() }, 42)

      // Block-level mutual recursion: two nested funs calling each other (two separate blocks in same scope)
      isTrue(sg, "block-level mutual recursion even(10)", { fun even(n: Int): Bool = if (n == 0) True else odd(n - 1); fun odd(n: Int): Bool = if (n == 0) False else even(n - 1); even(10) })
      isTrue(sg, "block-level mutual recursion odd(5)", { fun even(n: Int): Bool = if (n == 0) True else odd(n - 1); fun odd(n: Int): Bool = if (n == 0) False else even(n - 1); odd(5) })
    })

    group(s1, "closures", (sg: Suite) => {
      // Closure over block-local val
      eq(sg, "closure over block val", { val x = 2; fun get(): Int = x; get() }, 2)

      // Closure over function param (nested fun captures outer param): tested indirectly via closure to HOF and block val
      // Nested fun returning Unit then result (discard Unit, use block result)
      eq(sg, "nested Unit then result", { fun noop(): Unit = (); noop(); 42 }, 42)

      // Closure over block val passed to HOF
      eq(sg, "closure to HOF", { val k = 10; fun addK(x: Int): Int = x + k; applyTwice(addK, 0) }, 20)

      // By-reference var: closure and block share same mutable cell
      eq(sg, "by-ref var inc() + inc()", { var n = 0; fun inc(): Int = { n := n + 1; n }; inc() + inc() }, 3)

      // Nested fun inside closure capturing val from outer scope
      eq(sg, "nested fun capture from closure val", { val base = 10; val f = (x: Int) => { fun add(): Int = base + x; add() }; f(5) }, 15)

      // Recursive nested fun inside closure capturing from outer scope
      eq(sg, "recursive nested fun capture from closure", { val base = 1; val f = (x: Int) => { fun fac(n: Int): Int = if (n <= 1) base else n * fac(n - 1); fac(x) }; f(5) }, 120)

      // Nested fun capturing var from outer closure (by-reference forwarding)
      eq(sg, "nested fun capture var from closure", { var counter = 0; val f = (x: Int) => { fun bump(): Int = { counter := counter + x; counter }; bump() }; f(5) + f(3) }, 13)

      // Double-nested closure: recursive nested fun inside closure inside closure
      eq(sg, "recursive nested fun double closure", { val f = (x: Int) => { val g = (y: Int) => { fun fac(n: Int): Int = if (n <= 1) 1 else n * fac(n - 1); fac(y) }; g(x) }; f(5) }, 120)
    })

    // Generic functions with type parameters
    fun identity<T>(x: T): T = x
    fun swap<T, U>(a: T, b: U): (U, T) = (b, a)
    fun first<T, U>(p: (T, U)): T = match (p) { (x, y) => x }
    fun second<T, U>(p: (T, U)): U = match (p) { (x, y) => y }

    // Generic function with Option (built-in ADT)
    fun getOrZero<T>(o: Option<T>): Int = match (o) { None => 0, Some(v) => 1 }

    group(s1, "generic functions", (sg: Suite) => {
      eq(sg, "identity Int", identity(42), 42)
      eq(sg, "swap types", swap(1, "a"), ("a", 1))
      eq(sg, "first of pair", first((10, "x")), 10)
      eq(sg, "second of pair", second((10, "x")), "x")
      eq(sg, "getOrZero Some", getOrZero(Some(5)), 1)
      eq(sg, "getOrZero None", getOrZero(None), 0)
    })

    group(s1, "generic lambdas", (sg: Suite) => {
      eq(sg, "generic lambda identity Int", genId(42), 42)
    })
  })
