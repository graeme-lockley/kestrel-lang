// Runtime conformance: nested fun over block val (snapshot) vs var (shared cell).
// Parse note: semicolons after fun so the call below is the block result expression.
val _ = {
  val frozen = 10;
  fun readFrozen(): Int = frozen;
  var counter = 20;
  fun getCounter(): Int = counter;
  counter := 99;
  val snap: Int = readFrozen();
  val cur = getCounter();
  println(snap);
  println(cur);
  ()
}
// 10
// 99
