// Provenance: tests/conformance/typecheck/invalid/extern_fun_unresolved_type.ks (baseline S17-50)
// EXPECT: Unknown type
extern fun bad(x: MissingType): Int = jvm("kestrel.runtime.KRuntime#stringLength(java.lang.Object)")
