// Runtime conformance: h :: [] pattern must match only single-element lists.
// Runtime conformance: Regression test for JVM codegen bug where h :: [] matched any non-empty list.

fun classify(xs: List<Int>): String =
  match (xs) {
    []      => "empty"
    h :: [] => "single"
    h :: t  => "multi"
  }

println(classify([]))
// empty
println(classify([1]))
// single
println(classify([1, 2]))
// multi
println(classify([1, 2, 3]))
// multi
