// kestrel:result — Result helpers (subject first for piping).

export fun getOrElse<T, E>(r: Result<T, E>, default: T): T = match (r) {
  Err(_) => default
  Ok(x) => x
}

export fun withDefault<T, E>(r: Result<T, E>, default: T): T = getOrElse(r, default)

export fun isOk<T, E>(r: Result<T, E>): Bool = match (r) {
  Err(_) => False
  Ok(_) => True
}

export fun isErr<T, E>(r: Result<T, E>): Bool = match (r) {
  Err(_) => True
  Ok(_) => False
}

export fun map<T, U, E>(r: Result<T, E>, f: (T) -> U): Result<U, E> = match (r) {
  Ok(x) => Ok(f(x))
  Err(e) => Err(e)
}

export fun mapError<T, E, F>(r: Result<T, E>, f: (E) -> F): Result<T, F> = match (r) {
  Ok(x) => Ok(x)
  Err(e) => Err(f(e))
}

export fun andThen<T, U, E>(r: Result<T, E>, f: (T) -> Result<U, E>): Result<U, E> = match (r) {
  Ok(x) => f(x)
  Err(e) => Err(e)
}

export fun map2<A, B, C, E>(ra: Result<A, E>, rb: Result<B, E>, f: (A, B) -> C): Result<C, E> =
  match (ra) {
    Err(e) => Err(e)
    Ok(a) =>
      match (rb) {
        Err(e) => Err(e)
        Ok(b) => Ok(f(a, b))
      }
  }

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

export fun toOption<T, E>(r: Result<T, E>): Option<T> = match (r) {
  Ok(x) => Some(x)
  Err(_) => None
}

export fun fromOption<T, E>(o: Option<T>, err: E): Result<T, E> = match (o) {
  None => Err(err)
  Some(x) => Ok(x)
}
