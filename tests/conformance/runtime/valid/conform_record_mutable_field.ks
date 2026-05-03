// Runtime conformance: mutable record field assignment.
val _ = {
  val c = { mut x = 0 };
  c.x := 42;
  println(c.x);
  c.x := c.x + 1;
  println(c.x);
  ()
}
// 42
// 43
