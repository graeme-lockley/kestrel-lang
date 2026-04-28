// Provenance: tests/conformance/parse/valid/cons_and_pipeline.ks (baseline S17-50)
fun double(x: Int): Int = x * 2
fun inc(x: Int): Int = x + 1
val xs = 1 :: 2 :: []
val y = 3 |> double |> inc
