// EXPECT: Return type must be the same as the body type
// Declared return Int but body has type S (from f: T -> S); return type should be S
fun apply(f: T -> S, x: T): Int = f(x)
