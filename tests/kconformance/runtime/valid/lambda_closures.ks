// Self-hosted runtime conformance: lambda closures and local-fun recursion.
import { map } from "kestrel:data/list"

println(map([1, 2, 3], (x) => x + 1))
// => [2, 3, 4]

val x = 10
val addX = (y) => x + y
println(addX(5))
// => 15

val _ = {
  val base = 7;
  fun addBase(n: Int): Int = base + n;
  println(addBase(4));
  ()
}
// => 11

val factCase = {
  fun fact(n: Int): Int = if (n <= 1) 1 else n * fact(n - 1);
  println(fact(5));
  ()
}
// => 120

val mutualCase = {
  fun even(n: Int): Bool = if (n == 0) True else odd(n - 1);
  fun odd(n: Int): Bool = if (n == 0) False else even(n - 1);
  println(even(10));
  ()
}
// => True
