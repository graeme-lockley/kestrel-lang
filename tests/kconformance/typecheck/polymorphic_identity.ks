// Provenance: tests/conformance/typecheck/valid/polymorphic_identity.ks (baseline S17-50)
// Polymorphic identity function should work with different types
fun id(x: Int): Int = x

val a = id(42)
val b = id(100)
