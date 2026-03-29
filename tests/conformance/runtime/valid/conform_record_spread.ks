val base = { a = 1, b = 2 }
val ext = { ...base, c = 3 }
println(ext.a)
println(ext.c)
// 1
// 3
