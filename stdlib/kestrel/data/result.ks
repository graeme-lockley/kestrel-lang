//! Helpers for the built-in `Result<T, E>` type (`Ok(x)` or `Err(e)`).
//!
//! `Result` represents an operation that can succeed with a value of type `T` or
//! fail with an error of type `E`. All functions take the `Result` as their first
//! argument for clean `|>` pipe composition.
//!
//! Use `andThen` (flat-map) to chain fallible operations, `map` to transform a
//! success value without the possibility of further failure, and `mapError` to
//! transform or wrap the error side. Convert between `Result` and `Option` with
//! `toOption` and `fromOption`.
//!
//! ## Quick Start
//!
//! ```kestrel
//! import * as Res from "kestrel:data/result"
//!
//! val parsed = Ok(41)
//! val next = Res.map(parsed, (n: Int) => n + 1)          // Ok(42)
//! val checked = Res.andThen(next, (n: Int) =>
//!   if (n > 0) Ok(n) else Err("non-positive")
//! )
//! val msg = Res.mapError(Err("bad"), (e: String) => "error: ${e}")
//! ```
//!

/// Return the success value, or `default` if the result is `Err(_)`.
export fun getOrElse<T, E>(r: Result<T, E>, default: T): T = match (r) {
  Err(_) => default
  Ok(x) => x
}

/// Synonym for `getOrElse`; identical behaviour, alternative name.
export fun withDefault<T, E>(r: Result<T, E>, default: T): T = getOrElse(r, default)

/// `True` if `r` is `Ok(_)`.
export fun isOk<T, E>(r: Result<T, E>): Bool = match (r) {
  Err(_) => False
  Ok(_) => True
}

/// `True` if `r` is `Err(_)`.
export fun isErr<T, E>(r: Result<T, E>): Bool = match (r) {
  Err(_) => True
  Ok(_) => False
}

/// Apply `f` to the success value; propagate `Err` unchanged.
export fun map<T, U, E>(r: Result<T, E>, f: (T) -> U): Result<U, E> = match (r) {
  Ok(x) => Ok(f(x))
  Err(e) => Err(e)
}

/// Apply `f` to the error value; propagate `Ok` unchanged.
/// Use to wrap or translate error types.
export fun mapError<T, E, F>(r: Result<T, E>, f: (E) -> F): Result<T, F> = match (r) {
  Ok(x) => Ok(x)
  Err(e) => Err(f(e))
}

/// Flat-map (monadic bind): apply `f` to a success value, or propagate `Err`.
/// Use to chain operations that each return a `Result`.
export fun andThen<T, U, E>(r: Result<T, E>, f: (T) -> Result<U, E>): Result<U, E> = match (r) {
  Ok(x) => f(x)
  Err(e) => Err(e)
}

/// Combine two `Result` values with `f`; returns the first `Err` encountered.
export fun map2<A, B, C, E>(ra: Result<A, E>, rb: Result<B, E>, f: (A, B) -> C): Result<C, E> =
  match (ra) {
    Err(e) => Err(e)
    Ok(a) =>
      match (rb) {
        Err(e) => Err(e)
        Ok(b) => Ok(f(a, b))
      }
  }

/// Combine three `Result` values with `f`; returns the first `Err` encountered.
export fun map3<A, B, C, D, E>(
  ra: Result<A, E>,
  rb: Result<B, E>,
  rc: Result<C, E>,
  f: (A, B, C) -> D
): Result<D, E> =
  match (ra) {
    Err(e) => Err(e)
    Ok(a) =>
      match (rb) {
        Err(e) => Err(e)
        Ok(b) =>
          match (rc) {
            Err(e) => Err(e)
            Ok(c) => Ok(f(a, b, c))
          }
      }
  }

/// Combine four `Result` values with `f`; returns the first `Err` encountered.
export fun map4<A, B, C, D, F, E>(
  ra: Result<A, E>,
  rb: Result<B, E>,
  rc: Result<C, E>,
  rd: Result<D, E>,
  fn: (A, B, C, D) -> F
): Result<F, E> =
  match (ra) {
    Err(e) => Err(e)
    Ok(a) =>
      match (rb) {
        Err(e) => Err(e)
        Ok(b) =>
          match (rc) {
            Err(e) => Err(e)
            Ok(c) =>
              match (rd) {
                Err(e) => Err(e)
                Ok(d) => Ok(fn(a, b, c, d))
              }
          }
      }
  }

/// Combine five `Result` values with `f`; returns the first `Err` encountered.
export fun map5<A, B, C, D, E, G, ErrT>(
  ra: Result<A, ErrT>,
  rb: Result<B, ErrT>,
  rc: Result<C, ErrT>,
  rd: Result<D, ErrT>,
  re: Result<E, ErrT>,
  fn: (A, B, C, D, E) -> G
): Result<G, ErrT> =
  match (ra) {
    Err(e) => Err(e)
    Ok(a) =>
      match (rb) {
        Err(e) => Err(e)
        Ok(b) =>
          match (rc) {
            Err(e) => Err(e)
            Ok(c) =>
              match (rd) {
                Err(e) => Err(e)
                Ok(d) =>
                  match (re) {
                    Err(e) => Err(e)
                    Ok(ev) => Ok(fn(a, b, c, d, ev))
                  }
              }
          }
      }
  }

/// Convert to `Option`: `Ok(x)` becomes `Some(x)`, `Err(_)` becomes `None`.
export fun toOption<T, E>(r: Result<T, E>): Option<T> = match (r) {
  Ok(x) => Some(x)
  Err(_) => None
}

/// Convert from `Option`: `Some(x)` becomes `Ok(x)`, `None` becomes `Err(err)`.
export fun fromOption<T, E>(o: Option<T>, err: E): Result<T, E> = match (o) {
  None => Err(err)
  Some(x) => Ok(x)
}
