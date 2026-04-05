// Quicksort — the classic divide-and-conquer sort made elegant
// with pattern matching on list structure.
//
// Each call partitions the tail around the head (pivot), recursively
// sorts each half, then concatenates.  No indices, no swaps, no mutation.

import * as Lst  from "kestrel:data/list"
import * as Str  from "kestrel:data/string"

fun qsort(xs: List<Int>): List<Int> = match (xs) {
  []     => []
  h :: t =>
    Lst.append(
      qsort(Lst.filter(t, (x) => x <= h)),
      h :: qsort(Lst.filter(t, (x) => x > h))
    )
}

val input  = [38, 27, 43, 3, 9, 82, 10, 64, 21, 55, 17, 8, 99, 1, 47]
val sorted = qsort(input)

println("Input:  ${Str.join(", ", Lst.map(input, Str.fromInt))}")
println("Sorted: ${Str.join(", ", Lst.map(sorted, Str.fromInt))}")
