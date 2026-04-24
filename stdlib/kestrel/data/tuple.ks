//! Pair (2-tuple) helpers with the tuple as the subject for `|>` pipe composition.
//!
//! Kestrel's built-in tuple literal syntax (`(a, b)`) and field access via `.0`/`.1`
//! are the primary API for pairs. This module adds named constructors and mapping
//! functions for cases where passing a function over a pair is cleaner than
//! pattern-matching with a destructure.
//!
//! ## Quick Start
//!
//! ```kestrel
//! import * as Tup from "kestrel:data/tuple"
//!
//! val t = Tup.pair("kestrel", 7)
//! val a = Tup.first(t)
//! val b = Tup.second(t)
//! val bumped = Tup.mapSecond(t, (n: Int) => n + 1)
//! val both = Tup.mapBoth(t, (s: String) => "${s}!", (n: Int) => n * 10)
//! ```
//!

/// Construct a pair `(a, b)`. Useful as a higher-order function.
export fun pair<A, B>(a: A, b: B): (A, B) = (a, b)

/// Return the first element of the pair. Equivalent to `t.0`.
export fun first<A, B>(t: (A, B)): A = t.0

/// Return the second element of the pair. Equivalent to `t.1`.
export fun second<A, B>(t: (A, B)): B = t.1

/// Apply `f` to the first element and return a new pair with the result.
export fun mapFirst<A, B, X>(t: (A, B), f: (A) -> X): (X, B) = (f(t.0), t.1)

/// Apply `g` to the second element and return a new pair with the result.
export fun mapSecond<A, B, Y>(t: (A, B), f: (B) -> Y): (A, Y) = (t.0, f(t.1))

/// Apply `f` to the first element and `g` to the second; return the transformed pair.
export fun mapBoth<A, B, X, Y>(t: (A, B), f: (A) -> X, g: (B) -> Y): (X, Y) = (f(t.0), g(t.1))
