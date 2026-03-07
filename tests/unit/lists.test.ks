import { Suite, group, eq } from "kestrel:test"

fun sum(xs: List<Int>): Int = match (xs) {
  [] => 0,
  head :: tail => head + sum(tail)
}

fun head(xs: List<Int>): Int = match (xs) {
  [] => 0,
  h :: _ => h
}

fun length<T>(xs: List<T>): Int = match (xs) {
  [] => 0,
  _ :: tl => 1 + length(tl)
}

fun isEmpty<T>(xs: List<T>): Int = match (xs) { [] => 1, h :: t => 0 }

fun first(xs: List<Int>): Int = match (xs) { [] => 0, h :: t => h }

fun classifyFirst(xs: List<Int>): Int = match (xs) { [] => 0, h :: t => if (h > 10) 100 else 50 }

fun makeList(n: Int): List<Int> = if (n <= 0) [] else n :: makeList(n - 1)

fun sumList(xs: List<Int>): Int = match (xs) { [] => 0, h :: t => h + sumList(t) }

export fun run(s: Suite): Unit =
  group(s, "lists", (s1: Suite) => {
    group(s1, "construction", (con: Suite) => {
      eq(con, "empty list length", length([]), 0)
      eq(con, "cons builds list", head(1 :: []), 1)
      eq(con, "literal [1,2,3] length", length([1, 2, 3]), 3)
      eq(con, "cons chain 1::2::3::[]", length(1 :: 2 :: 3 :: []), 3)
      eq(con, "cons chain head", head(1 :: 2 :: 3 :: []), 1)
      eq(con, "single-element list", length([99]), 1)
      eq(con, "list equality", __equals([1, 2], [1, 2]), True)
      eq(con, "list inequality", __equals([1, 2], [1, 3]), False)
    })

    group(s1, "sum", (sm: Suite) => {
      eq(sm, "sum([]) == 0", sum([]), 0)
      eq(sm, "sum([1,2,3,4,5]) == 15", sum([1, 2, 3, 4, 5]), 15)
      eq(sm, "sum([10,20,30]) == 60", sum([10, 20, 30]), 60)
    })

    group(s1, "head", (hd: Suite) => {
      eq(hd, "head([]) == 0", head([]), 0)
      eq(hd, "head([10,20,30]) == 10", head([10, 20, 30]), 10)
    })

    group(s1, "nested match", (nm: Suite) => {
      eq(nm, "isEmpty([])", isEmpty([]), 1)
      eq(nm, "isEmpty([1,2,3])", isEmpty([1, 2, 3]), 0)
      eq(nm, "first([])", first([]), 0)
      eq(nm, "first([1,2,3])", first([1, 2, 3]), 1)
      eq(nm, "first([20,30,40])", first([20, 30, 40]), 20)
      eq(nm, "classifyFirst([])", classifyFirst([]), 0)
      eq(nm, "classifyFirst([20,30,40])", classifyFirst([20, 30, 40]), 100)
      eq(nm, "classifyFirst([5,15,25])", classifyFirst([5, 15, 25]), 50)
    })

    group(s1, "gc_stress", (gc: Suite) => {
      eq(gc, "makeList(20) sum", sumList(makeList(20)), 210)
      eq(gc, "makeList(15) sum", sumList(makeList(15)), 120)
      eq(gc, "makeList(10) sum", sumList(makeList(10)), 55)
      eq(gc, "four makeList(5) sum", sumList(makeList(5)) + sumList(makeList(5)) + sumList(makeList(5)) + sumList(makeList(5)), 60)
    })
  })
