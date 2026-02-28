import { message as message1 } from "./m1.ks"
import { message as message2 } from "./m2.ks"

import { hello } from "./m3.ks"

println(message1())
println(message2())

hello := "hello"

println({a = 1, b = hello})
println([1, 2, 3, "123", 5])
println(Some("hello"))

// --- Var captured by reference: closure and block share the same storage ---
// inc() mutates n and returns the new value; calling inc() + inc() gives 1 + 2 = 3
val byRefResult = { var n = 0; fun inc(): Int = { n := n + 1; n }; inc() + inc() }
println("by-ref inc() + inc() = ${byRefResult}")

// After the closure mutates n, the block sees the same n
val afterMutate = { var n = 0; fun setOne(): Unit = { n := 1; () }; setOne(); n }
println("after setOne(), n = ${afterMutate}")
