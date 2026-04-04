// 5
// hi!
extern type JStringBuilder = jvm("java.lang.StringBuilder")
extern fun stringLength(s: String): Int = jvm("kestrel.runtime.KRuntime#stringLength(java.lang.Object)")
extern fun formatOne(x: String): String = jvm("kestrel.runtime.KRuntime#formatOne(java.lang.Object)")
extern fun sbNew(): JStringBuilder = jvm("java.lang.StringBuilder#<init>()")
extern fun sbAppend(sb: JStringBuilder, s: String): JStringBuilder = jvm("java.lang.StringBuilder#append(java.lang.String)")
extern fun sbToString(sb: JStringBuilder): String = jvm("java.lang.StringBuilder#toString()")

val n = stringLength("hello")
println(n)

val b = sbNew()
val b2 = sbAppend(b, "hi")
val b3 = sbAppend(b2, "!")
println(sbToString(b3))
