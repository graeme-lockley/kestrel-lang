// Runtime conformance: sys/path utilities
import * as P from "kestrel:sys/path"

println(P.join(["a", "b", "c"]))
// a/b/c
println(P.dirname("/a/b/c.ks"))
// /a/b
println(P.basename("/a/b/c.ks"))
// c.ks
println(P.resolve("/a/b", "../c"))
// /a/c
println(P.isAbsolute("/foo"))
// True
println(P.isAbsolute("foo"))
// False
println(P.extension("c.ks"))
// Some(ks)
println(P.extension("Makefile"))
// None
println(P.withoutExtension("/a/b/c.ks"))
// /a/b/c
println(P.normalize("/a/b/../c"))
// /a/c
println(P.splitPath("/a/b/c.ks"))
// { 0 = /a/b, 1 = c.ks }
