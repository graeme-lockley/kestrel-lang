// Provenance: tests/conformance/typecheck/invalid/extern_fun_parametric_unknown_type.ks (baseline S17-50)
// EXPECT: Unknown type: W
extern fun bad<V>(x: V): W = jvm("kestrel.runtime.KRuntime#formatOne(java.lang.Object)")
