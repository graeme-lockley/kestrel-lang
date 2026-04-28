// Provenance: tests/conformance/typecheck/valid/narrowing_option.ks (baseline S17-50)
fun f(o: Option<Int>): Int = if (o is Some) { 1 } else { 0 }
