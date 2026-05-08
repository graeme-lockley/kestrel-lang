// Self-hosted runtime conformance: closure capture over val vs var.
val _ = {
  val frozen = 10;
  fun readFrozen(): Int = frozen;

  var counter = 20;
  fun getCounter(): Int = counter;
  counter := 99;

  println(readFrozen());
  println(getCounter());
  ()
}
// => 10
// => 99
