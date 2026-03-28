// EXPECT: Tuple pattern has
val p = (1, 2)
val r = match (p) { (a, b, c) => a }
