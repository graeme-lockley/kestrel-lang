// Provenance: tests/conformance/typecheck/valid/tuple_pattern_match.ks (baseline S17-50)
val p = (1, 2)
val sum = match (p) { (x, y) => x + y }

val nested = ((1, 2), 3)
val nestedSum = match (nested) { ((a, b), c) => a + b + c }
