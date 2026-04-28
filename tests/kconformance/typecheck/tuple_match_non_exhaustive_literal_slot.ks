// Provenance: tests/conformance/typecheck/invalid/tuple_match_non_exhaustive_literal_slot.ks (baseline S17-50)
// EXPECT: Non-exhaustive match
val p = (1, 2)
val r = match (p) { (0, y) => y }
