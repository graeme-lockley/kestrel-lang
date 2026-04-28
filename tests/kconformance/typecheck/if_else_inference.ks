// Provenance: tests/conformance/typecheck/valid/if_else_inference.ks (baseline S17-50)
// If-else type inference
val a = if (True) 1 else 2
val b = if (1 < 2) 10 else 20
val c = if (False) True else False
