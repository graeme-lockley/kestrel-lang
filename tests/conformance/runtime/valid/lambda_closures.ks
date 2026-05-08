// Runtime conformance: closure behavior currently implemented in self-hosted codegen.
import { map } from "kestrel:data/list"

println(map([1, 2, 3], (x) => x + 1))
// [2, 3, 4]

val x = 10
val addX = (y) => x + y
println(addX(5))
// 15

val _ = {
  val base = 7;
  fun addBase(n: Int): Int = base + n;
  println(addBase(4));
  ()
}
// 11
