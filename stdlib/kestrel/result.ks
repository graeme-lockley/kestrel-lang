// kestrel:result — Result helpers (subject first for piping).

export fun getOrElse<T, E>(r: Result<T, E>, default: T): T = match (r) {
  Err{ value = _ } => default
  Ok{ value = x } => x
}

export fun withDefault<T, E>(r: Result<T, E>, default: T): T = getOrElse(r, default)

export fun isOk<T, E>(r: Result<T, E>): Bool = match (r) {
  Err{ value = _ } => False
  Ok{ value = _ } => True
}

export fun isErr<T, E>(r: Result<T, E>): Bool = match (r) {
  Err{ value = _ } => True
  Ok{ value = _ } => False
}

export fun map<T, U, E>(r: Result<T, E>, f: (T) -> U): Result<U, E> = match (r) {
  Ok{ value = x } => Ok(f(x))
  Err{ value = e } => Err(e)
}

export fun mapError<T, E, F>(r: Result<T, E>, f: (E) -> F): Result<T, F> = match (r) {
  Ok{ value = x } => Ok(x)
  Err{ value = e } => Err(f(e))
}

export fun andThen<T, U, E>(r: Result<T, E>, f: (T) -> Result<U, E>): Result<U, E> = match (r) {
  Ok{ value = x } => f(x)
  Err{ value = e } => Err(e)
}

export fun map2<A, B, C, E>(ra: Result<A, E>, rb: Result<B, E>, f: (A, B) -> C): Result<C, E> =
  match (ra) {
    Err{ value = e } => Err(e)
    Ok{ value = a } =>
      match (rb) {
        Err{ value = e } => Err(e)
        Ok{ value = b } => Ok(f(a, b))
      }
  }

export fun map3<A, B, C, D, E>(
  ra: Result<A, E>,
  rb: Result<B, E>,
  rc: Result<C, E>,
  f: (A, B, C) -> D
): Result<D, E> =
  match (ra) {
    Err{ value = e } => Err(e)
    Ok{ value = a } =>
      match (rb) {
        Err{ value = e } => Err(e)
        Ok{ value = b } =>
          match (rc) {
            Err{ value = e } => Err(e)
            Ok{ value = c } => Ok(f(a, b, c))
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
    Err{ value = e } => Err(e)
    Ok{ value = a } =>
      match (rb) {
        Err{ value = e } => Err(e)
        Ok{ value = b } =>
          match (rc) {
            Err{ value = e } => Err(e)
            Ok{ value = c } =>
              match (rd) {
                Err{ value = e } => Err(e)
                Ok{ value = d } => Ok(fn(a, b, c, d))
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
    Err{ value = e } => Err(e)
    Ok{ value = a } =>
      match (rb) {
        Err{ value = e } => Err(e)
        Ok{ value = b } =>
          match (rc) {
            Err{ value = e } => Err(e)
            Ok{ value = c } =>
              match (rd) {
                Err{ value = e } => Err(e)
                Ok{ value = d } =>
                  match (re) {
                    Err{ value = e } => Err(e)
                    Ok{ value = ev } => Ok(fn(a, b, c, d, ev))
                  }
              }
          }
      }
  }

export fun toOption<T, E>(r: Result<T, E>): Option<T> = match (r) {
  Ok{ value = x } => Some(x)
  Err{ value = _ } => None
}

export fun fromOption<T, E>(o: Option<T>, err: E): Result<T, E> = match (o) {
  None => Err(err)
  Some{ value = x } => Ok(x)
}
