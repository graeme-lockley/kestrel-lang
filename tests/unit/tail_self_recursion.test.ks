import { Suite, group, eq } from "kestrel:test"

// Self tail-call optimization: deep tail recursion must not exhaust the VM call stack.
fun sumTail(n: Int, acc: Int): Int =
  if (n <= 0) acc else sumTail(n - 1, acc + n)

fun countBranch(n: Int, acc: Int): Int =
  if (n <= 0) acc
  else if (n % 2 == 0) countBranch(n - 1, acc + 1)
  else countBranch(n - 1, acc + 2)

// Non-tail self recursion still uses the stack (must not be lowered to a loop).
fun sumNonTail(n: Int): Int =
  if (n <= 0) 0 else n + sumNonTail(n - 1)

export async fun run(s: Suite): Task<Unit> =
  group(s, "tail_self_recursion", (s1: Suite) => {
    group(s1, "tail_optimized", (sg: Suite) => {
      eq(sg, "sumTail deep", sumTail(200000, 0), 20000100000)
      eq(sg, "branch tails", countBranch(150000, 0), 225000)
    })
    group(s1, "non_tail_still_correct", (sg: Suite) => {
      eq(sg, "sumNonTail shallow", sumNonTail(500), 125250)
    })
  })
