// Provenance: tests/conformance/typecheck/valid/unit_literal_match.ks (baseline S17-50)
val u = ()
val result = match (u) {
  () => 1
}
