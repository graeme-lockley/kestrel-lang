extern fun stringLength(s: String): Int = jvm("kestrel.runtime.KRuntime#stringLength(java.lang.Object)")
fun len(s: String): Int = stringLength(s)
