// Repro for S08-10: exception handler frame must cover locals allocated in try body
// Expected output:
// 0
// 100

fun safeCond(flag: Bool): Int =
  try {
    val x = 99  // Simple val, not problematic
    if (flag) throw(x) else 0
  } catch (e) {
    e => e + 1
  }

println(safeCond(False))
println(safeCond(True))
