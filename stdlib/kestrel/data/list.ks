//! Immutable singly-linked list utilities — the primary collection type in Kestrel.
//!
//! `List<A>` is the standard sequential container: pattern-matchable, structurally
//! composable, and safely shareable across concurrent tasks. The runtime represents
//! it as a classic cons-cell chain; all functions are pure and allocation-based.
//!
//! Performance: `length`, `reverse`, `append`, `map`, `filter`, `foldl`, and most
//! traversals are O(n). `head`, `tail`, and `::` (cons) are O(1).
//! For O(1) random access and in-place mutation use `kestrel:data/array`.
//!
//! Sorting: `sort` works on `List<Int>` only. For other element types use
//! `sortWith` (provide a comparator returning negative/zero/positive) or
//! `sortBy` (map each element to an `Int` key).

/// Number of elements. O(n) — avoid calling in a tight loop; prefer structural descent.
export extern fun length<X>(xs: List<X>): Int =
  jvm("kestrel.runtime.KRuntime#listLength(java.lang.Object)")

/// `True` if `xs` has no elements.
export fun isEmpty(xs: List<X>): Bool = match (xs) {
  [] => True
  _ => False
}

fun revAppend(xs: List<T>, acc: List<T>): List<T> = match (xs) {
  [] => acc
  h :: t => revAppend(t, h :: acc)
}

/// Return a new list with elements in reverse order.
export fun reverse(xs: List<T>): List<T> = revAppend(xs, [])

/// Return the concatenation of `xs` followed by `ys`. O(length(xs)).
export fun append(xs: List<T>, ys: List<T>): List<T> = revAppend(reverse(xs), ys)

/// Left fold: `f(f(f(z, x1), x2), …, xn)`. Tail-recursive; use for sums, building maps, etc.
export fun foldl(xs: List<A>, z: B, f: (B, A) -> B): B = match (xs) {
  [] => z
  h :: t => foldl(t, f(z, h), f)
}

/// Right fold: `f(x1, f(x2, … f(xn, z)))`. Preserves list structure; not stack-safe for very long lists.
export fun foldr<A, B>(xs: List<A>, z: B, f: (A, B) -> B): B = match (xs) {
  [] => z
  h :: t => f(h, foldr(t, z, f))
}

/// Flatten a list of lists into a single list, preserving order.
export fun concat(xss: List<List<T>>): List<T> =
  foldl(xss, [], (acc: List<T>, xs: List<T>) => append(acc, xs))

/// Insert `sep` between every pair of consecutive elements. Empty and singleton lists are unchanged.
export fun intersperse<A>(xs: List<A>, sep: A): List<A> = match (xs) {
  [] => []
  h :: t => intersperseHelp(sep, h, t)
}

fun intersperseHelp<A>(sep: A, h: A, t: List<A>): List<A> = match (t) {
  [] => [h]
  h2 :: t2 => h :: sep :: intersperseHelp(sep, h2, t2)
}

/// Wrap a single value in a list: `singleton(x)` == `[x]`.
export fun singleton<A>(x: A): List<A> = [x]

fun repList<A>(n: Int, x: A, acc: List<A>): List<A> =
  if (n <= 0) reverse(acc) else repList(n - 1, x, x :: acc)

/// Return a list of `n` copies of `x`. Returns `[]` when `n <= 0`.
export fun repeat<A>(n: Int, x: A): List<A> = repList(n, x, [])

/// `[lo, lo+1, …, hi]`. Returns `[]` when `lo > hi`.
export fun range(lo: Int, hi: Int): List<Int> =
  if (lo > hi) [] else lo :: range(lo + 1, hi)

/// Discard the first `n` elements; return the remainder. Safe when `n > length(xs)`.
export fun drop(xs: List<T>, n: Int): List<T> =
  if (n <= 0) xs
  else match (xs) {
    [] => [],
    _ :: tl => drop(tl, n - 1)
  }

/// Return the first `n` elements. Safe when `n > length(xs)`.
export fun take<A>(xs: List<A>, n: Int): List<A> =
  if (n <= 0) []
  else match (xs) {
    [] => []
    h :: t => h :: take(t, n - 1)
  }

/// Return the longest prefix of `xs` for which `pred` holds.
export fun takeWhile<A>(xs: List<A>, pred: (A) -> Bool): List<A> = match (xs) {
  [] => []
  h :: t => if (pred(h)) h :: takeWhile(t, pred) else []
}

/// Drop elements while `pred` holds and return the first element that fails and the rest.
export fun dropWhile<A>(xs: List<A>, pred: (A) -> Bool): List<A> = match (xs) {
  [] => []
  h :: t => if (pred(h)) dropWhile(t, pred) else xs
}

/// Apply `f` to every element and collect results. Structure-preserving.
export fun map(xs: List<A>, f: (A) -> B): List<B> = match (xs) {
  [] => []
  h :: t => f(h) :: map(t, f)
}

/// Like `map` but passes the 0-based index as the first argument to `f`.
export fun indexedMap<A, B>(xs: List<A>, f: (Int, A) -> B): List<B> = idxMap(xs, f, 0)

fun idxMap<A, B>(xs: List<A>, f: (Int, A) -> B, i: Int): List<B> = match (xs) {
  [] => []
  h :: t => f(i, h) :: idxMap(t, f, i + 1)
}

/// Map over three lists simultaneously; stops at the shortest.
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

/// Map over four lists simultaneously; stops at the shortest.
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

/// Map over five lists simultaneously; stops at the shortest.
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

/// Keep only elements where `pred(x)` is `True`.
export fun filter(xs: List<A>, pred: (A) -> Bool): List<A> = match (xs) {
  [] => []
  h :: t => if (pred(h)) h :: filter(t, pred) else filter(t, pred)
}

/// Apply `f` to each element; keep only the `Some` results, unwrapping them.
export fun filterMap<A, B>(xs: List<A>, f: (A) -> Option<B>): List<B> = match (xs) {
  [] => []
  h :: t =>
    match (f(h)) {
      None => filterMap(t, f)
      Some(x) => x :: filterMap(t, f)
    }
}

/// `map` then `concat`: apply `f` to each element and flatten the resulting lists.
export fun concatMap<A, B>(xs: List<A>, f: (A) -> List<B>): List<B> =
  foldr(xs, [], (x: A, acc: List<B>) => append(f(x), acc))

/// Pair elements at matching positions; stops at the shorter list.
export fun zip<A, B>(xs: List<A>, ys: List<B>): List<(A, B)> =
  match (xs) {
    [] => []
    xh :: xt =>
      match (ys) {
        [] => []
        yh :: yt => (xh, yh) :: zip(xt, yt)
      }
  }

/// Map over two lists simultaneously; stops at the shorter list.
export fun map2<A, B, C>(xs: List<A>, ys: List<B>, fn: (A, B) -> C): List<C> =
  match (xs) {
    [] => []
    xh :: xt =>
      match (ys) {
        [] => []
        yh :: yt => fn(xh, yh) :: map2(xt, yt, fn)
      }
  }

/// Sum of all elements. Returns `0` for an empty list.
export fun sum(xs: List<Int>): Int = foldl(xs, 0, (a: Int, b: Int) => a + b)

/// Product of all elements. Returns `1` for an empty list.
export fun product(xs: List<Int>): Int = foldl(xs, 1, (a: Int, b: Int) => a * b)

/// `True` if `x` is an element of `xs` (uses structural equality `==`).
export fun member<A>(xs: List<A>, x: A): Bool = match (xs) {
  [] => False
  h :: t => x == h | member(t, x)
}

/// `True` if `pred` returns `True` for at least one element.
export fun any<A>(xs: List<A>, pred: (A) -> Bool): Bool = match (xs) {
  [] => False
  h :: t => pred(h) | any(t, pred)
}

/// `True` if `pred` returns `True` for every element.
export fun all<A>(xs: List<A>, pred: (A) -> Bool): Bool = match (xs) {
  [] => True
  h :: t => pred(h) & all(t, pred)
}

/// Largest element, or `None` for an empty list.
export fun maximum(xs: List<Int>): Option<Int> =
  foldl(xs, None, (acc: Option<Int>, x: Int) =>
    match (acc) {
      None => Some(x)
      Some(m) => if (x > m) Some(x) else acc
    }
  )

/// Smallest element, or `None` for an empty list.
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

/// Split `xs` into `(matching, non-matching)` based on `pred`, preserving relative order.
export fun partition<A>(xs: List<A>, pred: (A) -> Bool): (List<A>, List<A>) = partAcc(xs, pred, [], [])

fun unzipAcc<A, B>(xs: List<(A, B)>, asAcc: List<A>, bsAcc: List<B>): (List<A>, List<B>) = match (xs) {
  [] => (revAcc(asAcc, []), revAcc(bsAcc, []))
  h :: t => unzipAcc(t, h.0 :: asAcc, h.1 :: bsAcc)
}

/// Split a list of pairs into a pair of lists: `([a1, a2, …], [b1, b2, …])`.
export fun unzip<A, B>(xs: List<(A, B)>): (List<A>, List<B>) = unzipAcc(xs, [], [])

fun insertSorted(x: Int, xs: List<Int>): List<Int> = match (xs) {
  [] => [x]
  h :: t => if (x <= h) x :: xs else h :: insertSorted(x, t)
}

/// Sort a `List<Int>` in ascending order. For other types use `sortWith` or `sortBy`.
export fun sort(xs: List<Int>): List<Int> = match (xs) {
  [] => []
  h :: t => insertSorted(h, sort(t))
}

/// First element, or `None` for an empty list. O(1).
export fun head<A>(xs: List<A>): Option<A> = match (xs) {
  [] => None
  h :: _ => Some(h)
}

/// All elements after the head. Returns `[]` for an empty list. O(1).
export fun tail<A>(xs: List<A>): List<A> = match (xs) {
  [] => []
  _ :: t => t
}

/// Execute `f` on each element for side effects; returns `Unit`. Use for IO/logging.
export fun forEach<A>(xs: List<A>, f: (A) -> Unit): Unit = match (xs) {
  []     => ()
  h :: t => { f(h); forEach(t, f) }
}

fun generateAcc<A>(i: Int, n: Int, f: (Int) -> A): List<A> =
  if (i >= n) []
  else f(i) :: generateAcc(i + 1, n, f)

/// Build a list of `n` elements by calling `f(i)` for `i` in `0..n-1`. Returns `[]` when `n <= 0`.
export fun generate<A>(n: Int, f: (Int) -> A): List<A> = generateAcc(0, n, f)

fun insertWith<A>(cmp: (A, A) -> Int, x: A, xs: List<A>): List<A> = match (xs) {
  [] => [x]
  h :: t => if (cmp(x, h) <= 0) x :: xs else h :: insertWith(cmp, x, t)
}

/// Sort by a comparator `cmp(a, b)` returning negative, zero, or positive.
export fun sortWith<A>(cmp: (A, A) -> Int, xs: List<A>): List<A> = match (xs) {
  [] => []
  h :: t => insertWith(cmp, h, sortWith(cmp, t))
}

/// Sort by mapping each element to an `Int` key; the element with the smallest key comes first.
export fun sortBy<A>(f: (A) -> Int, xs: List<A>): List<A> =
  sortWith((a: A, b: A) => f(a) - f(b), xs)

/// Return the first element matching `pred`, or `None`.
export fun find<A>(pred: (A) -> Bool, xs: List<A>): Option<A> = match (xs) {
  [] => None
  h :: t => if (pred(h)) Some(h) else find(pred, t)
}

fun findIndexAcc<A>(pred: (A) -> Bool, xs: List<A>, i: Int): Option<Int> = match (xs) {
  [] => None
  h :: t => if (pred(h)) Some(i) else findIndexAcc(pred, t, i + 1)
}

/// Return the 0-based index of the first element matching `pred`, or `None`.
export fun findIndex<A>(pred: (A) -> Bool, xs: List<A>): Option<Int> =
  findIndexAcc(pred, xs, 0)

/// Apply `f` to each element; return the first `Some` result, or `None`.
export fun findMap<A, B>(f: (A) -> Option<B>, xs: List<A>): Option<B> = match (xs) {
  [] => None
  h :: t =>
    match (f(h)) {
      None => findMap(f, t)
      Some(b) => Some(b)
    }
}

/// Last element, or `None` for an empty list. O(n).
export fun last<A>(xs: List<A>): Option<A> = match (xs) {
  [] => None
  h :: [] => Some(h)
  _ :: t => last(t)
}
