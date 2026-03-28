// EXPECT: Non-exhaustive match
val p = (1, 2)
val r = match (p) { (0, y) => y }
