// Test logical not operator

val t = True
val f = False

print(!True)
// false
print(!t)
// false

print(!False)
// true
print(!f)
// true

// Double negation
print(!!True)
// true
print(!!t)
// true

// Not with comparisons
val d = !(5 > 3)
print(d)
// false
val e = !(10 == 20)
print(e)
// true

// Not in conditional
val result = if (!False) 100 else 200
print(result)
// 100
