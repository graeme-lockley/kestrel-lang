// kestrel:list — immutable list utilities.

export fun length(xs: List<X>): Int = match (xs) {
  [] => 0
  _ :: tail => 1 + length(tail)
}

export fun isEmpty(xs: List<X>): Bool = match (xs) {
  [] => True
  _ => False
}

fun revAppend(xs: List<T>, acc: List<T>): List<T> = match (xs) {
  [] => acc
  h :: t => revAppend(t, h :: acc)
}

export fun reverse(xs: List<T>): List<T> = revAppend(xs, [])

export fun append(xs: List<T>, ys: List<T>): List<T> = revAppend(reverse(xs), ys)

export fun foldl(xs: List<A>, z: B, f: (B, A) -> B): B = match (xs) {
  [] => z
  h :: t => foldl(t, f(z, h), f)
}

export fun foldr<A, B>(xs: List<A>, z: B, f: (A, B) -> B): B = match (xs) {
  [] => z
  h :: t => f(h, foldr(t, z, f))
}

export fun concat(xss: List<List<T>>): List<T> =
  foldl(xss, [], (acc: List<T>, xs: List<T>) => append(acc, xs))

export fun intersperse<A>(xs: List<A>, sep: A): List<A> = match (xs) {
  [] => []
  h :: t => intersperseHelp(sep, h, t)
}

fun intersperseHelp<A>(sep: A, h: A, t: List<A>): List<A> = match (t) {
  [] => [h]
  h2 :: t2 => h :: sep :: intersperseHelp(sep, h2, t2)
}

export fun singleton<A>(x: A): List<A> = [x]

fun repList<A>(n: Int, x: A, acc: List<A>): List<A> =
  if (n <= 0) reverse(acc) else repList(n - 1, x, x :: acc)

export fun repeat<A>(n: Int, x: A): List<A> = repList(n, x, [])

export fun range(lo: Int, hi: Int): List<Int> =
  if (lo > hi) [] else lo :: range(lo + 1, hi)

export fun drop(xs: List<T>, n: Int): List<T> =
  if (n <= 0) xs
  else match (xs) {
    [] => [],
    _ :: tl => drop(tl, n - 1)
  }

export fun take<A>(xs: List<A>, n: Int): List<A> =
  if (n <= 0) []
  else match (xs) {
    [] => []
    h :: t => h :: take(t, n - 1)
  }

export fun takeWhile<A>(xs: List<A>, pred: (A) -> Bool): List<A> = match (xs) {
  [] => []
  h :: t => if (pred(h)) h :: takeWhile(t, pred) else []
}

export fun dropWhile<A>(xs: List<A>, pred: (A) -> Bool): List<A> = match (xs) {
  [] => []
  h :: t => if (pred(h)) dropWhile(t, pred) else xs
}

export fun map(xs: List<A>, f: (A) -> B): List<B> = match (xs) {
  [] => []
  h :: t => f(h) :: map(t, f)
}

export fun indexedMap<A, B>(xs: List<A>, f: (Int, A) -> B): List<B> = idxMap(xs, f, 0)

fun idxMap<A, B>(xs: List<A>, f: (Int, A) -> B, i: Int): List<B> = match (xs) {
  [] => []
  h :: t => f(i, h) :: idxMap(t, f, i + 1)
}

export fun map3<A, B, C, D>(xs: List<A>, ys: List<B>, zs: List<C>, fn: (A, B, C) -> D): List<D> =
  match (xs) {
    [] => []
    xh :: xt => match (ys) {
      [] => []
      yh :: yt => match (zs) {
        [] => []
        zh :: zt => fn(xh, yh, zh) :: map3(xt, yt, zt, fn)
      }
    }
  }

export fun map4<A, B, C, D, E>(
  xs: List<A>,
  ys: List<B>,
  zs: List<C>,
  ws: List<D>,
  fn: (A, B, C, D) -> E
): List<E> =
  match (xs) {
    [] => []
    xh :: xt => match (ys) {
      [] => []
      yh :: yt => match (zs) {
        [] => []
        zh :: zt => match (ws) {
          [] => []
          wh :: wt => fn(xh, yh, zh, wh) :: map4(xt, yt, zt, wt, fn)
        }
      }
    }
  }

export fun map5<A, B, C, D, E, F>(
  xs: List<A>,
  ys: List<B>,
  zs: List<C>,
  ws: List<D>,
  vs: List<E>,
  fn: (A, B, C, D, E) -> F
): List<F> =
  match (xs) {
    [] => []
    xh :: xt => match (ys) {
      [] => []
      yh :: yt => match (zs) {
        [] => []
        zh :: zt => match (ws) {
          [] => []
          wh :: wt => match (vs) {
            [] => []
            vh :: vt => fn(xh, yh, zh, wh, vh) :: map5(xt, yt, zt, wt, vt, fn)
          }
        }
      }
    }
  }

export fun filter(xs: List<A>, pred: (A) -> Bool): List<A> = match (xs) {
  [] => []
  h :: t => if (pred(h)) h :: filter(t, pred) else filter(t, pred)
}

export fun filterMap<A, B>(xs: List<A>, f: (A) -> Option<B>): List<B> = match (xs) {
  [] => []
  h :: t =>
    match (f(h)) {
      None => filterMap(t, f)
      Some(x) => x :: filterMap(t, f)
    }
}

export fun concatMap<A, B>(xs: List<A>, f: (A) -> List<B>): List<B> =
  foldr(xs, [], (x: A, acc: List<B>) => append(f(x), acc))

export fun zip<A, B>(xs: List<A>, ys: List<B>): List<(A, B)> =
  match (xs) {
    [] => []
    xh :: xt =>
      match (ys) {
        [] => []
        yh :: yt => (xh, yh) :: zip(xt, yt)
      }
  }

export fun map2<A, B, C>(xs: List<A>, ys: List<B>, fn: (A, B) -> C): List<C> =
  match (xs) {
    [] => []
    xh :: xt =>
      match (ys) {
        [] => []
        yh :: yt => fn(xh, yh) :: map2(xt, yt, fn)
      }
  }

export fun sum(xs: List<Int>): Int = foldl(xs, 0, (a: Int, b: Int) => a + b)

export fun product(xs: List<Int>): Int = foldl(xs, 1, (a: Int, b: Int) => a * b)

export fun member<A>(xs: List<A>, x: A): Bool = match (xs) {
  [] => False
  h :: t => x == h | member(t, x)
}

export fun any<A>(xs: List<A>, pred: (A) -> Bool): Bool = match (xs) {
  [] => False
  h :: t => pred(h) | any(t, pred)
}

export fun all<A>(xs: List<A>, pred: (A) -> Bool): Bool = match (xs) {
  [] => True
  h :: t => pred(h) & all(t, pred)
}

export fun maximum(xs: List<Int>): Option<Int> =
  foldl(xs, None, (acc: Option<Int>, x: Int) =>
    match (acc) {
      None => Some(x)
      Some(m) => if (x > m) Some(x) else acc
    }
  )

export fun minimum(xs: List<Int>): Option<Int> =
  foldl(xs, None, (acc: Option<Int>, x: Int) =>
    match (acc) {
      None => Some(x)
      Some(m) => if (x < m) Some(x) else acc
    }
  )

fun revAcc<A>(xs: List<A>, acc: List<A>): List<A> = match (xs) {
  [] => acc
  h :: t => revAcc(t, h :: acc)
}

fun partAcc<A>(xs: List<A>, pred: (A) -> Bool, ok: List<A>, bad: List<A>): (List<A>, List<A>) =
  match (xs) {
    [] => (revAcc(ok, []), revAcc(bad, []))
    h :: t =>
      if (pred(h)) partAcc(t, pred, h :: ok, bad)
      else partAcc(t, pred, ok, h :: bad)
  }

export fun partition<A>(xs: List<A>, pred: (A) -> Bool): (List<A>, List<A>) = partAcc(xs, pred, [], [])

fun unzipAcc<A, B>(xs: List<(A, B)>, asAcc: List<A>, bsAcc: List<B>): (List<A>, List<B>) = match (xs) {
  [] => (revAcc(asAcc, []), revAcc(bsAcc, []))
  h :: t => unzipAcc(t, h.0 :: asAcc, h.1 :: bsAcc)
}

export fun unzip<A, B>(xs: List<(A, B)>): (List<A>, List<B>) = unzipAcc(xs, [], [])

fun insertSorted(x: Int, xs: List<Int>): List<Int> = match (xs) {
  [] => [x]
  h :: t => if (x <= h) x :: xs else h :: insertSorted(x, t)
}

export fun sort(xs: List<Int>): List<Int> = match (xs) {
  [] => []
  h :: t => insertSorted(h, sort(t))
}

export fun head<A>(xs: List<A>): Option<A> = match (xs) {
  [] => None
  h :: _ => Some(h)
}

export fun tail<A>(xs: List<A>): List<A> = match (xs) {
  [] => []
  _ :: t => t
}

export fun forEach<A>(xs: List<A>, f: (A) -> Unit): Unit = match (xs) {
  []     => ()
  h :: t => { f(h); forEach(t, f) }
}
