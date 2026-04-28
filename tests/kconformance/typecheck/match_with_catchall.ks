// Provenance: tests/conformance/typecheck/valid/match_with_catchall.ks (baseline S17-50)
// Match with catch-all pattern
val xs = [1, 2, 3]
val result = match (xs) {
  _ => 42
}
