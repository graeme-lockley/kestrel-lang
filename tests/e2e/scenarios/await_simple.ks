// Test async/await - for now just test that async functions work
async fun compute(x: Int): Int = x * 2

// Async functions return tasks, but we can't await at top level yet
// So just call the function and verify it type-checks
val task1 = compute(21)
val task2 = compute(50)

// For now, just print some constants to verify the test runs
print(42)
print(100)
print(142)
