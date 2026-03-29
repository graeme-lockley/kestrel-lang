val n = match (match (True) { True => 1, False => 0 }) {
  0 => "zero"
  1 => "one"
  _ => "many"
}
