// 7
// True
// False
extern fun strLen(s: String): Int = jvm("java.lang.String#length():int")
extern fun strIsEmpty(s: String): Bool = jvm("java.lang.String#isEmpty():boolean")

println(strLen("kestrel"))
println(strIsEmpty(""))
println(strIsEmpty("hello"))
