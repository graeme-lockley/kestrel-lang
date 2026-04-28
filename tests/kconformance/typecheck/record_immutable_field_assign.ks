// Provenance: tests/conformance/typecheck/invalid/record_immutable_field_assign.ks (baseline S17-50)
// EXPECT: immutable
val r = { x = 1 }
val _ = { r.x := 2; () }
