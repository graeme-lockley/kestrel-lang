extern fun get<V>(x: V): V = jvm("kestrel.runtime.KRuntime#formatOne(java.lang.Object)")
fun forceString(x: String): String = x
val s = forceString(get("ok"))
