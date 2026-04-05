// Async helper fixture for cross-module async tests (S06-11).
// Exports an async function that can be imported and awaited from other modules.

export async fun asyncDouble(n: Int): Task<Int> = n * 2
