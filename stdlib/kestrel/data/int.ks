// kestrel:data/int — integer utilities and random number generation.

/** Returns a pseudo-random Int in [0, bound). */
export extern fun random(bound: Int): Int =
  jvm("kestrel.runtime.KRuntime#randomInt(java.lang.Long)")

/** Returns a pseudo-random Int in [lo, hi] (inclusive on both ends). */
export extern fun randomRange(lo: Int, hi: Int): Int =
  jvm("kestrel.runtime.KRuntime#randomIntRange(java.lang.Long,java.lang.Long)")
