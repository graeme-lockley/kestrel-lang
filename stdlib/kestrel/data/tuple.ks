// kestrel:tuple — Pair helpers (pipe-friendly: tuple first).

export fun pair<A, B>(a: A, b: B): (A, B) = (a, b)

export fun first<A, B>(t: (A, B)): A = t.0

export fun second<A, B>(t: (A, B)): B = t.1

export fun mapFirst<A, B, X>(t: (A, B), f: (A) -> X): (X, B) = (f(t.0), t.1)

export fun mapSecond<A, B, Y>(t: (A, B), f: (B) -> Y): (A, Y) = (t.0, f(t.1))

export fun mapBoth<A, B, X, Y>(t: (A, B), f: (A) -> X, g: (B) -> Y): (X, Y) = (f(t.0), g(t.1))
