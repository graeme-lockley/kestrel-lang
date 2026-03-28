// Runtime conformance: while loop iteration and nested while.
val _ = {
  var i = 0
  while (i < 3) {
    println(i)
    i := i + 1
    ()
  }
  // 0
  // 1
  // 2
  var outer = 0
  while (outer < 2) {
    var inner = 0
    while (inner < 2) {
      println(outer * 10 + inner)
      inner := inner + 1
      ()
    }
    outer := outer + 1
    ()
  }
  // 0
  // 1
  // 10
  // 11
  ()
}
