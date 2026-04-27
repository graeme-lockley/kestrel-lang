// Runtime conformance: nested cons-chain patterns must bind all variables.
// Runtime conformance: Regression test for JVM codegen bug where variables in 3+
// Runtime conformance: element cons chains (a :: b :: c :: t) were silently unbound.

fun classify3(xs: List<Int>): String =
  match (xs) {
    []           => "empty"
    a :: []      => "one:${a}"
    a :: b :: [] => "two:${a}:${b}"
    a :: b :: c :: [] => "three:${a}:${b}:${c}"
    a :: b :: c :: t  => "many:${a}:${b}:${c}"
  }

fun classify4(xs: List<Int>): String =
  match (xs) {
    []                     => "empty"
    a :: []                => "one:${a}"
    a :: b :: []           => "two:${a}:${b}"
    a :: b :: c :: []      => "three:${a}:${b}:${c}"
    a :: b :: c :: d :: [] => "four:${a}:${b}:${c}:${d}"
    a :: b :: c :: d :: t  => "many:${a}:${b}:${c}:${d}"
  }

println(classify3([]))
// empty
println(classify3([1]))
// one:1
println(classify3([1, 2]))
// two:1:2
println(classify3([1, 2, 3]))
// three:1:2:3
println(classify3([1, 2, 3, 4]))
// many:1:2:3

println(classify4([]))
// empty
println(classify4([1]))
// one:1
println(classify4([1, 2]))
// two:1:2
println(classify4([1, 2, 3]))
// three:1:2:3
println(classify4([1, 2, 3, 4]))
// four:1:2:3:4
println(classify4([1, 2, 3, 4, 5]))
// many:1:2:3:4
