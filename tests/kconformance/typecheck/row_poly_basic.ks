// Provenance: tests/conformance/typecheck/valid/row_poly_basic.ks (baseline S17-50)
// Row polymorphism: function that takes a record with x field
fun getX(p: { x: Int }): Int = p.x

val p1 = { x = 10 }
val x1 = getX(p1)
