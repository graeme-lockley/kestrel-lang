//! Integer utility functions and pseudo-random number generation.
//!
//! Supplements the built-in `Int` arithmetic operators with randomisation helpers
//! backed by `java.util.Random` (seeded at JVM startup). Results are NOT
//! cryptographically secure; use an external source for security-sensitive work.
//!
//! ## Quick Start
//!
//! ```kestrel
//! import * as Int from "kestrel:data/int"
//!
//! val die = Int.randomRange(1, 6)
//! val idx = Int.random(10) // 0..9
//! ```
//!
//! For deterministic tests, avoid relying on random output values directly.

/// Return a pseudo-random `Int` in `[0, bound)` (zero inclusive, bound exclusive).
/// Behaviour is undefined when `bound <= 0`.
export extern fun random(bound: Int): Int =
  jvm("kestrel.runtime.KRuntime#randomInt(java.lang.Long)")

/// Return a pseudo-random `Int` in `[lo, hi]` (both endpoints inclusive).
/// Behaviour is undefined when `lo > hi`.
export extern fun randomRange(lo: Int, hi: Int): Int =
  jvm("kestrel.runtime.KRuntime#randomIntRange(java.lang.Long,java.lang.Long)")
