// Self-hosted runtime conformance: Option match dispatch.
fun describe(opt: Option<Int>): String =
  match (opt) {
    None => "nothing"
    Some(v) => "got ${v}"
  }

println(describe(None))
// => nothing
println(describe(Some(42)))
// => got 42
println(describe(Some(0)))
// => got 0
