// Test logical not operator

// Basic logical not
val a = !True
val b = !False
val _ = print(a)
// true
val _ = print(b)
// false

// Double negation
val c = !!True
val _ = print(c)
// true

// Not with comparisons
val d = !(5 > 3)
val _ = print(d)
// true
val e = !(10 == 20)
val _ = print(e)
// false

// Not in conditional
val result = if (!False) 100 else 200
val _ = print(result)
// 200
