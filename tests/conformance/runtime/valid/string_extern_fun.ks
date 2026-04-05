// Runtime conformance: length, slice, indexOf, equals, toUpperCase, toLowerCase, trim via extern fun
import { length, slice, indexOf, equals, toUpperCase, toLowerCase, trim } from "kestrel:data/string"

val s = "Hello, World!"
println(length(s))
// 13
println(slice(s, 0, 5))
// Hello
println(indexOf(s, "World"))
// 7
println(equals(s, "Hello, World!"))
// True
println(toUpperCase("hello"))
// HELLO
println(toLowerCase("WORLD"))
// world
println(trim("  spaced  "))
// spaced
