// Provenance: tests/conformance/typecheck/invalid/return_type_must_match_body.ks (baseline S17-50)
// EXPECT: Return type must be the same as the body type
// Declared return Int but body has type S (from f: T -> S); return type should be S
fun apply(f: T -> S, x: T): Int = f(x)
