// Canonical VM/runtime exceptions (61-bit Int overflow, divide/mod by zero).
// The VM allocates these by name when arithmetic traps; user code should import them to catch or annotate.
export exception ArithmeticOverflow
export exception DivideByZero
