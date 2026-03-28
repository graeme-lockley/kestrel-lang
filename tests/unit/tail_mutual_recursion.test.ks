import { Suite, group, eq } from "kestrel:test"

// Mutual tail-call optimization: direct calls between top-level functions in tail position.
fun isEven(n: Int): Bool = if (n == 0) True else isOdd(n - 1)
fun isOdd(n: Int): Bool = if (n == 0) False else isEven(n - 1)

// Three-way cycle (state-machine style)
fun state0(n: Int, acc: Int): Int =
  if (n <= 0) acc else state1(n - 1, acc + 1)
fun state1(n: Int, acc: Int): Int =
  if (n <= 0) acc else state2(n - 1, acc + 2)
fun state2(n: Int, acc: Int): Int =
  if (n <= 0) acc else state0(n - 1, acc + 3)

// Not optimized: tail call goes through a first-class closure (CALL_INDIRECT).
val oddViaClosure = (m: Int) => isOddClosure(m)
fun isEvenClosure(n: Int): Bool = if (n == 0) True else oddViaClosure(n - 1)
fun isOddClosure(n: Int): Bool = if (n == 0) False else isEvenClosure(n - 1)

export fun run(s: Suite): Unit =
  group(s, "tail_mutual_recursion", (s1: Suite) => {
    group(s1, "mutual_tail_optimized", (sg: Suite) => {
      eq(sg, "isEven deep", isEven(300000), True)
      eq(sg, "isOdd deep", isOdd(300001), True)
      eq(sg, "three-state machine", state0(90000, 0), 180000)
    })
    group(s1, "indirect_fallback_shallow", (sg: Suite) => {
      eq(sg, "closure bridge small", isEvenClosure(42), True)
      eq(sg, "closure bridge odd small", isOddClosure(7), True)
    })
  })
