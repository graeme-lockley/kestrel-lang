// kestrel:basics — numeric, boolean, and general helpers (pipe-friendly where noted).

export fun identity<A>(a: A): A = a

export fun always<A, B>(a: A, _b: B): A = a

export fun clamp(lo: Int, hi: Int, n: Int): Int =
  if (n < lo) lo else if (n > hi) hi else n

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

/** Floored modulo: result has the same sign as `divisor`. */
export fun modBy(divisor: Int, n: Int): Int =
  if (divisor == 0) {
    0
  } else {
    n - divisor * floorDiv(n, divisor)
  }

/** Truncated remainder (sign of dividend). */
export fun remainderBy(divisor: Int, n: Int): Int = tremTrunc(n, divisor)

export fun xor(a: Bool, b: Bool): Bool = (a | b) & !(a & b)

export fun not(b: Bool): Bool = !b

export fun toFloat(n: Int): Float = __int_to_float(n)

export fun truncate(f: Float): Int = __float_to_int(f)

export fun floor(f: Float): Int = __float_floor(f)

export fun ceiling(f: Float): Int = __float_ceil(f)

export fun round(f: Float): Int = __float_round(f)

export fun abs(f: Float): Float = __float_abs(f)

export fun sqrt(f: Float): Float = __float_sqrt(f)

export fun isNaN(f: Float): Bool = __float_is_nan(f)

export fun isInfinite(f: Float): Bool = __float_is_infinite(f)

/** Wall-clock time in milliseconds (VM `__now_ms`). */
export fun nowMs(): Int = __now_ms()
