// Provenance: tests/conformance/typecheck/valid/boolean_logic.ks (baseline S17-50)
// Boolean logic with short-circuit evaluation
val a = True & False
val b = True | False
val c = (1 < 2) & (3 > 2)
val d = (1 > 2) | (3 < 4)
