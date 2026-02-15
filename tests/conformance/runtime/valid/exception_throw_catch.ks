// Runtime conformance: exception throw/catch (spec 08 §2.3, §2.5). try block runs; catch runs when throw is used.
val x = try { 10 } catch (e) { e => 0 }
println(x)
// 10
val y = try { 20 } catch (e) { e => 99 }
println(y)
// 20
