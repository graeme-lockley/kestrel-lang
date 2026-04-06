// Minimal reproduction for S08-09: var/val inside while loop body causes VerifyError
// A val declared inside a while body allocates a new slot each iteration; the loop-head
// stackmap frame didn't cover that slot → JVM rejects the class with VerifyError.

fun sumList(items: List<Int>): Int = {
  var total = 0
  var rest = items
  while (rest != []) {
    val n = match (rest) { h :: _ => h, _ => 0 }   // val inside while body
    total := total + n;
    rest := match (rest) { _ :: t => t, _ => [] }
  }
  total
}

println(sumList([1, 2, 3, 4, 5]))   // expected: 15
println(sumList([]))                 // expected: 0
