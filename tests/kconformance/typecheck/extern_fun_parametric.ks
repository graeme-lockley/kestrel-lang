// Provenance: tests/conformance/typecheck/valid/extern_fun_parametric.ks (baseline S17-50)
extern fun get<V>(x: V): V = jvm("kestrel.runtime.KRuntime#formatOne(java.lang.Object)")
fun forceString(x: String): String = x
val s = forceString(get("ok"))
