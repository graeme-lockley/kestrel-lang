// Runtime conformance: parseFloat, toFloat
import { parseFloat, toFloat } from "kestrel:data/string"

println(parseFloat("3.14"))
// Some(3.14)
println(parseFloat("bad"))
// None
println(parseFloat(""))
// None
println(parseFloat("1e10"))
// Some(1.0E10)
println(parseFloat("-0.5"))
// Some(-0.5)
println(toFloat("2.5"))
// 2.5
println(toFloat("x"))
// 0.0
