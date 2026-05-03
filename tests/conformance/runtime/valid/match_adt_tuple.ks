// Runtime conformance: EMatch with ADT constructor and tuple patterns.

type Color = Red | Green | Blue(Int)

fun colorName(c: Color): String =
  match (c) {
    Red      => "red"
    Green    => "green"
    Blue(n)  => "blue-${n}"
  }

fun sumPair(p: (Int, Int)): Int =
  match (p) {
    (a, b) => a + b
  }

println(colorName(Red))
// red
println(colorName(Green))
// green
println(colorName(Blue(7)))
// blue-7
println(sumPair((3, 4)))
// 7
println(sumPair((10, 20)))
// 30
