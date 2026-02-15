// Test tuple creation and element access
val pair = (10, 20)
print(pair.0)
print(pair.1)

// Test inline tuple access
val first = (100, 200, 300).0
val second = (100, 200, 300).1
val third = (100, 200, 300).2

print(first)
print(second)
print(third)

// Test nested tuples
val nested = ((1, 2), (3, 4))
val a = nested.0.0
val b = nested.0.1
val c = nested.1.0
val d = nested.1.1

print(a)
print(b)
print(c)
print(d)
