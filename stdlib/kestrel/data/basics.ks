//! Miscellaneous numeric, boolean, and general-purpose helpers.
//!
//! Acts as the catch-all for utilities that do not belong to a specific data
//! structure: integer arithmetic variants, boolean logic, numeric conversions,
//! floating-point math, and wall-clock time. Widely imported across the stdlib.
//!
//! Division semantics: Kestrel's built-in `/` and `%` on `Int` use truncated
//! division (rounds toward zero, remainder sign follows dividend). Use `modBy`
//! for floored modulo whose result sign always matches the divisor (Python-style),
//! and `remainderBy` for truncated remainder whose sign matches the dividend
//! (C-style `%`).
//!
//! ## Quick Start
//!
//! ```kestrel
//! import * as B from "kestrel:data/basics"
//!
//! val bounded = B.clamp(0, 100, 140) // 100
//! val m1 = B.modBy(10, -13)          // 7
//! val r1 = B.remainderBy(10, -13)    // -3
//! val ok = B.xor(True, False)        // True
//! val ms = B.nowMs()
//! ```
//!

/// The identity function; returns its argument unchanged.
/// Useful as a no-op callback or default transform.
export fun identity<A>(a: A): A = a

/// Return `a`, ignoring `_b`. Useful as a constant-valued fold accumulator.
export fun always<A, B>(a: A, _b: B): A = a

/// Clamp `n` to the inclusive range `[lo, hi]`.
/// Returns `lo` if `n < lo`, `hi` if `n > hi`, or `n` otherwise.
export fun clamp(lo: Int, hi: Int, n: Int): Int =
  if (n < lo) lo else if (n > hi) hi else n

/// Arithmetic negation; returns `0 - n`.
export fun negate(n: Int): Int = 0 - n

/** Truncated division toward zero (Kestrel `/` on Int). */
fun tdiv(a: Int, b: Int): Int = if (b == 0) 0 else a / b

/** Remainder for truncated division (`n - divisor * tdiv(n, divisor)`). Int `%` is floored-style; do not use `%` here. */
fun tremTrunc(n: Int, divisor: Int): Int =
  if (divisor == 0) 0 else n - divisor * tdiv(n, divisor)

/** Floored division: floor(n / divisor) for integers. */
fun floorDiv(n: Int, divisor: Int): Int =
  if (divisor == 0) {
    0
  } else {
    val q = tdiv(n, divisor)
    val r = tremTrunc(n, divisor)
    if (r != 0 & ((r > 0) != (divisor > 0))) q - 1 else q
  }

/// Floored modulo: result always has the same sign as `divisor`.
/// Equivalent to Python's `%`. Example: `modBy(360, -10) == 350`.
/// Returns `0` when `divisor == 0`.
export fun modBy(divisor: Int, n: Int): Int =
  if (divisor == 0) {
    0
  } else {
    n - divisor * floorDiv(n, divisor)
  }

/// Truncated remainder: result has the same sign as `n` (the dividend).
/// Equivalent to C's `%`. Example: `remainderBy(10, -13) == -3`.
/// Returns `0` when `divisor == 0`.
export fun remainderBy(divisor: Int, n: Int): Int = tremTrunc(n, divisor)

/// Logical exclusive-or; `True` when exactly one of `a` and `b` is `True`.
export fun xor(a: Bool, b: Bool): Bool = (a | b) & !(a & b)

/// Logical negation; equivalent to `!b`.
export fun not(b: Bool): Bool = !b

/// Convert an `Int` to `Float`. May lose precision for very large integers.
export extern fun toFloat(n: Int): Float =
  jvm("kestrel.runtime.KRuntime#intToFloat(java.lang.Object)")

/// Truncate a `Float` toward zero and return the result as `Int`.
export extern fun truncate(f: Float): Int =
  jvm("kestrel.runtime.KRuntime#floatToInt(java.lang.Object)")

/// Return the greatest `Int` less than or equal to `f` (floor).
export extern fun floor(f: Float): Int =
  jvm("kestrel.runtime.KRuntime#floatFloor(java.lang.Object)")

/// Return the smallest `Int` greater than or equal to `f` (ceiling).
export extern fun ceiling(f: Float): Int =
  jvm("kestrel.runtime.KRuntime#floatCeil(java.lang.Object)")

/// Round `f` to the nearest `Int`, with ties rounding toward positive infinity.
export extern fun round(f: Float): Int =
  jvm("kestrel.runtime.KRuntime#floatRound(java.lang.Object)")

/// Absolute value of `f`.
export extern fun abs(f: Float): Float =
  jvm("kestrel.runtime.KRuntime#floatAbs(java.lang.Object)")

/// Square root of `f`. Returns `NaN` for negative inputs.
export extern fun sqrt(f: Float): Float =
  jvm("kestrel.runtime.KRuntime#floatSqrt(java.lang.Object)")

/// `True` if `f` is IEEE 754 NaN (not-a-number).
export extern fun isNaN(f: Float): Bool =
  jvm("kestrel.runtime.KRuntime#floatIsNan(java.lang.Object)")

/// `True` if `f` is positive or negative infinity.
export extern fun isInfinite(f: Float): Bool =
  jvm("kestrel.runtime.KRuntime#floatIsInfinite(java.lang.Object)")

/// Current wall-clock time in milliseconds since the Unix epoch.
export extern fun nowMs(): Int =
  jvm("kestrel.runtime.KRuntime#nowMs()")

