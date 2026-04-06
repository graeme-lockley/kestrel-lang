// Minimal reproduction for S08-08: varNames pollution across top-level functions
// If the bug is present, `f2` will emit CHECKCAST KRecord on slot 1 (a raw Int), causing ClassCastException.
// Function order matters: f1 must declare `var result` BEFORE f2 declares `val result`.

fun f1(n: Int): Int = {
  var result = n + 1
  result
}

fun f2(b: Bool): Int = {
  val result = 42     // val - should NOT be in varNames; bug: polluted from f1's `var result`
  if (b) result + 1 else result
}

println(f1(10));         // expected: 11
println(f2(True));       // expected: 43  (with bug: ClassCastException)
println(f2(False))       // expected: 42  (with bug: ClassCastException)
