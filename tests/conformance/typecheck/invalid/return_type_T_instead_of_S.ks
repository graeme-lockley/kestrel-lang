// EXPECT: Return type must be the same as the body type
// Body has type S (from f: T -> S); return must be S, not T (S and T do not unify)
fun apply(f: T -> S, x: T): T = f(x)
