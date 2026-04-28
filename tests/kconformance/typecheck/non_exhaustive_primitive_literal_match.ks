// Provenance: tests/conformance/typecheck/invalid/non_exhaustive_primitive_literal_match.ks (baseline S17-50)
// EXPECT: Non-exhaustive match
val n = 1
val result = match (n) {
  0 => 10
}
