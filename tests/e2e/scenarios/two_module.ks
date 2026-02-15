// E2E: two-module program — imports from local .ks and runs
import { double } from "./lib_double.ks"

val a = double(3)
val b = double(double(2))

println(a)
// 6
println(b)
// 8
