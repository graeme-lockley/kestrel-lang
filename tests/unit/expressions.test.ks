import { Suite, group, eq } from "kestrel:test"

fun double(x: Int): Int = x * 2
fun add1(x: Int): Int = x + 1
fun increment(x: Int): Int = x + 1

export fun run(s: Suite): Unit =
  group(s, "expressions", (s1: Suite) => {
    group(s1, "pipe", (p: Suite) => {
      eq(p, "3 |> double", 3 |> double, 6);
      eq(p, "3 |> double |> add1", 3 |> double |> add1, 7);
      eq(p, "double <| 5", double <| 5, 10);
      ()
    });
    group(s1, "higher_order", (ho: Suite) => {
      eq(ho, "double(double(5))", double(double(5)), 20);
      eq(ho, "increment(increment(10))", increment(increment(10)), 12);
      ()
    });
    ()
  })
