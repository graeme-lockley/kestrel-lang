// Provenance: tests/conformance/typecheck/valid/extern_fun_non_parametric.ks (baseline S17-50)
extern fun stringLength(s: String): Int = jvm("kestrel.runtime.KRuntime#stringLength(java.lang.Object)")
fun len(s: String): Int = stringLength(s)
