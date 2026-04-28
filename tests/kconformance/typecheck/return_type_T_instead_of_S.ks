// Provenance: tests/conformance/typecheck/invalid/return_type_T_instead_of_S.ks (baseline S17-50)
// EXPECT: Return type must be the same as the body type
// Body has type S (from f: T -> S); return must be S, not T (S and T do not unify)
fun apply(f: T -> S, x: T): T = f(x)
