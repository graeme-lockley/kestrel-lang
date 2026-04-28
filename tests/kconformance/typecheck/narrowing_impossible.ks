// Provenance: tests/conformance/typecheck/invalid/narrowing_impossible.ks (baseline S17-50)
// EXPECT: Cannot narrow
fun f(x: Int): Bool = x is String
