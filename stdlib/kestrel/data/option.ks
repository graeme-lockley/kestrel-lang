// kestrel:option — Option helpers (subject first for piping).

export fun getOrElse<A>(o: Option<A>, default: A): A = match (o) {
  None => default
  Some(x) => x
}

export fun withDefault<A>(o: Option<A>, default: A): A = getOrElse(o, default)

export fun isNone<A>(o: Option<A>): Bool = match (o) {
  None => True
  Some(_) => False
}

export fun isSome<A>(o: Option<A>): Bool = match (o) {
  None => False
  Some(_) => True
}

export fun map<A, B>(o: Option<A>, f: (A) -> B): Option<B> = match (o) {
  None => None
  Some(x) => Some(f(x))
}

export fun andThen<A, B>(o: Option<A>, f: (A) -> Option<B>): Option<B> = match (o) {
  None => None
  Some(x) => f(x)
}

export fun map2<A, B, C>(oa: Option<A>, ob: Option<B>, f: (A, B) -> C): Option<C> =
  match (oa) {
    None => None
    Some(a) =>
      match (ob) {
        None => None
        Some(b) => Some(f(a, b))
      }
  }

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
