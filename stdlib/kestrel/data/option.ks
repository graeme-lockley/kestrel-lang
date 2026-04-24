//! Helpers for the built-in `Option<A>` type (`Some(x)` or `None`).
//!
//! `Option` represents a value that may or may not be present. All functions take
//! the `Option` as their first argument so they compose cleanly with the `|>` pipe
//! operator.
//!
//! Use `andThen` (flat-map) for chained fallible operations where each step produces
//! an `Option`. Use `map` when the transform cannot itself fail. Use `map2`–`map5`
//! to combine multiple independent `Option` values; the result is `None` if any
//! input is `None`.
//!
//! ## Quick Start
//!
//! ```kestrel
//! import * as Opt from "kestrel:data/option"
//!
//! val name = Some("kestrel")
//! val upper = Opt.map(name, (s: String) => "${s}!")
//! val fallback = Opt.withDefault(None, "unknown")
//! val chained = Opt.andThen(Some(21), (n: Int) => Some(n * 2))
//! val both = Opt.map2(Some(2), Some(3), (a: Int, b: Int) => a + b)
//! ```
//!

/// Return the value inside `o`, or `default` if `o` is `None`.
export fun getOrElse<A>(o: Option<A>, default: A): A = match (o) {
  None => default
  Some(x) => x
}

/// Synonym for `getOrElse`; identical behaviour, alternative name.
export fun withDefault<A>(o: Option<A>, default: A): A = getOrElse(o, default)

/// `True` if `o` is `None`.
export fun isNone<A>(o: Option<A>): Bool = match (o) {
  None => True
  Some(_) => False
}

/// `True` if `o` is `Some(_)`.
export fun isSome<A>(o: Option<A>): Bool = match (o) {
  None => False
  Some(_) => True
}

/// Apply `f` to the value inside `o`; propagate `None` unchanged.
export fun map<A, B>(o: Option<A>, f: (A) -> B): Option<B> = match (o) {
  None => None
  Some(x) => Some(f(x))
}

/// Flat-map (monadic bind): apply `f` to the value inside `o`, or return `None`.
/// Use to chain operations that each return an `Option`.
export fun andThen<A, B>(o: Option<A>, f: (A) -> Option<B>): Option<B> = match (o) {
  None => None
  Some(x) => f(x)
}

/// Combine two `Option` values with `f`; returns `None` if either input is `None`.
export fun map2<A, B, C>(oa: Option<A>, ob: Option<B>, f: (A, B) -> C): Option<C> =
  match (oa) {
    None => None
    Some(a) =>
      match (ob) {
        None => None
        Some(b) => Some(f(a, b))
      }
  }

/// Combine three `Option` values with `f`; returns `None` if any input is `None`.
export fun map3<A, B, C, D>(
  oa: Option<A>,
  ob: Option<B>,
  oc: Option<C>,
  f: (A, B, C) -> D
): Option<D> =
  match (oa) {
    None => None
    Some(a) =>
      match (ob) {
        None => None
        Some(b) =>
          match (oc) {
            None => None
            Some(c) => Some(f(a, b, c))
          }
      }
  }

/// Combine four `Option` values with `f`; returns `None` if any input is `None`.
export fun map4<A, B, C, D, E>(
  oa: Option<A>,
  ob: Option<B>,
  oc: Option<C>,
  od: Option<D>,
  f: (A, B, C, D) -> E
): Option<E> =
  match (oa) {
    None => None
    Some(a) =>
      match (ob) {
        None => None
        Some(b) =>
          match (oc) {
            None => None
            Some(c) =>
              match (od) {
                None => None
                Some(d) => Some(f(a, b, c, d))
              }
          }
      }
  }

/// Combine five `Option` values with `f`; returns `None` if any input is `None`.
export fun map5<A, B, C, D, E, F>(
  oa: Option<A>,
  ob: Option<B>,
  oc: Option<C>,
  od: Option<D>,
  oe: Option<E>,
  f: (A, B, C, D, E) -> F
): Option<F> =
  match (oa) {
    None => None
    Some(a) =>
      match (ob) {
        None => None
        Some(b) =>
          match (oc) {
            None => None
            Some(c) =>
              match (od) {
                None => None
                Some(d) =>
                  match (oe) {
                    None => None
                    Some(e) => Some(f(a, b, c, d, e))
                  }
              }
          }
      }
  }
