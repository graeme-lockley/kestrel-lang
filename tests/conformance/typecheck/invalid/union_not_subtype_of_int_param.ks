// EXPECT: Cannot unify
fun needInt(x: Int): Int = x
fun givesUnion(): Int | Bool = True
val bad = needInt(givesUnion())
