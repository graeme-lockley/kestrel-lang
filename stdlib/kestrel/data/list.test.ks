import { Suite, group, eq, isTrue, isFalse } from "kestrel:tools/test"
import { append, fromInt } from "kestrel:data/string"
import * as List from "kestrel:data/list"
import * as Arr  from "kestrel:data/array"

fun inc(n: Int): Int = n + 1

fun isEven(n: Int): Bool = n % 2 == 0

fun sumAcc(acc: Int, x: Int): Int = acc + x

fun emptyInts(): List<Int> = []

export async fun run(s: Suite): Task<Unit> = {
  group(s, "list", (s1: Suite) => {
    group(s1, "length", (sg: Suite) => {
      eq(sg, "empty", List.length(emptyInts()), 0)
      eq(sg, "singleton", List.length([1]), 1)
      eq(sg, "multi-element", List.length([1, 2, 3]), 3)
    })

    group(s1, "isEmpty", (sg: Suite) => {
      isTrue(sg, "empty", List.isEmpty(emptyInts()))
      isFalse(sg, "non-empty", List.isEmpty([1, 2, 3]))
      isFalse(sg, "singleton", List.isEmpty(["Hello"]))
    })

    group(s1, "drop", (sg: Suite) => {
      eq(sg, "drop 0", List.drop([1, 2, 3], 0), [1, 2, 3])
      eq(sg, "drop negative", List.drop([1, 2, 3], -1), [1, 2, 3])
      eq(sg, "drop 1", List.drop([1, 2, 3], 1), [2, 3])
      eq(sg, "drop 2", List.drop([1, 2, 3], 2), [3])
      eq(sg, "drop 3", List.drop([1, 2, 3], 3), emptyInts())
      eq(sg, "drop past length", List.drop([1, 2, 3], 10), emptyInts())
      eq(sg, "drop from empty", List.drop(emptyInts(), 2), emptyInts())
      eq(sg, "drop 2 strings", List.drop(["a", "b", "c"], 2), ["c"])
    })

    group(s1, "map", (sg: Suite) => {
      eq(sg, "empty", List.map(emptyInts(), inc), emptyInts())
      eq(sg, "ints", List.map([1, 2, 3], inc), [2, 3, 4])
    })

    group(s1, "indexedMap", (sg: Suite) => {
      eq(
        sg,
        "strings",
        List.indexedMap(["a", "b"], (i: Int, t: String) => append(fromInt(i), t)),
        ["0a", "1b"]
      )
      eq(sg, "sum index", List.indexedMap([2, 3], (i: Int, n: Int) => i + n), [2, 4])
      eq(sg, "empty ints", List.indexedMap(emptyInts(), (i: Int, n: Int) => n), emptyInts())
    })

    group(s1, "intersperse repeat", (sg: Suite) => {
      eq(sg, "intersperse", List.intersperse([1, 2, 3], 0), [1, 0, 2, 0, 3])
      eq(sg, "intersperse singleton", List.intersperse([1], 0), [1])
      eq(sg, "intersperse empty", List.intersperse(emptyInts(), 0), emptyInts())
      eq(sg, "repeat", List.repeat(3, 7), [7, 7, 7])
      eq(sg, "repeat zero", List.repeat(0, 7), emptyInts())
      eq(sg, "repeat one", List.repeat(1, 9), [9])
    })

    group(s1, "filter", (sg: Suite) => {
      eq(sg, "empty", List.filter(emptyInts(), isEven), emptyInts())
      eq(sg, "evens", List.filter([1, 2, 3, 4], isEven), [2, 4])
    })

    group(s1, "foldl", (sg: Suite) => {
      eq(sg, "sum", List.foldl([1, 2, 3], 0, sumAcc), 6)
      eq(sg, "empty", List.foldl(emptyInts(), 0, sumAcc), 0)
    })

    group(s1, "sum", (sg: Suite) => {
      eq(sg, "empty", List.sum(emptyInts()), 0)
      eq(sg, "singleton", List.sum([7]), 7)
      eq(sg, "several", List.sum([1, 2, 3]), 6)
    })

    group(s1, "reverse", (sg: Suite) => {
      eq(sg, "empty", List.reverse(emptyInts()), emptyInts())
      eq(sg, "list", List.reverse([1, 2, 3]), [3, 2, 1])
    })

    group(s1, "append concat", (sg: Suite) => {
      eq(sg, "append", List.append([1, 2], [3, 4]), [1, 2, 3, 4])
      eq(sg, "concat", List.concat([[1, 2], [3], emptyInts()]), [1, 2, 3])
    })

    group(s1, "range take", (sg: Suite) => {
      eq(sg, "range", List.range(1, 3), [1, 2, 3])
      eq(sg, "range singleton", List.range(5, 5), [5])
      eq(sg, "range empty", List.range(3, 1), emptyInts())
      eq(sg, "take", List.take([1, 2, 3], 2), [1, 2])
      eq(sg, "take zero", List.take([1, 2, 3], 0), emptyInts())
      eq(sg, "take past", List.take([1, 2], 99), [1, 2])
      eq(sg, "take empty", List.take(emptyInts(), 3), emptyInts())
    })

    group(s1, "foldr concatMap", (sg: Suite) => {
      eq(sg, "foldr snoc", List.foldr([1, 2, 3], emptyInts(), (x: Int, acc: List<Int>) => List.append(acc, [x])), [3, 2, 1])
      eq(sg, "concatMap", List.concatMap([1, 2], (n: Int) => [n, n]), [1, 1, 2, 2])
    })

    group(s1, "member any all", (sg: Suite) => {
      isTrue(sg, "member", List.member([1, 2, 3], 2))
      isFalse(sg, "not member", List.member([1, 2, 3], 9))
      isFalse(sg, "member empty", List.member(emptyInts(), 1))
      isTrue(sg, "any", List.any([1, 2, 3], (n: Int) => n > 2))
      isFalse(sg, "any false", List.any([1, 2, 3], (n: Int) => n > 9))
      isFalse(sg, "any empty", List.any(emptyInts(), (n: Int) => True))
      isTrue(sg, "all", List.all([1, 2, 3], (n: Int) => n > 0))
      isFalse(sg, "all false", List.all([1, 2, 3], (n: Int) => n < 2))
      isTrue(sg, "all empty", List.all(emptyInts(), (n: Int) => False))
    })

    group(s1, "product max min", (sg: Suite) => {
      eq(sg, "product", List.product([2, 3, 4]), 24)
      eq(sg, "product empty", List.product(emptyInts()), 1)
      eq(sg, "product singleton", List.product([7]), 7)
      eq(sg, "maximum", List.maximum([3, 1, 2]), Some(3))
      eq(sg, "minimum", List.minimum([3, 1, 2]), Some(1))
      eq(sg, "maximum empty", List.maximum(emptyInts()), None)
      eq(sg, "minimum empty", List.minimum(emptyInts()), None)
      eq(sg, "maximum ties", List.maximum([1, 3, 3, 2]), Some(3))
    })

    group(s1, "partition unzip sort", (sg: Suite) => {
      eq(sg, "partition", List.partition([1, 2, 3, 4], isEven), ([2, 4], [1, 3]))
      eq(sg, "partition empty", List.partition(emptyInts(), isEven), (emptyInts(), emptyInts()))
      eq(sg, "partition none", List.partition([1, 3, 5], isEven), (emptyInts(), [1, 3, 5]))
      val abPairs = [(1, "a"), (2, "b")]
      val uz = List.unzip(abPairs)
      eq(sg, "unzip first", uz.0, [1, 2])
      eq(sg, "unzip second", uz.1, ["a", "b"])
      val uzE = List.unzip([])
      eq(sg, "unzip empty", uzE.0, emptyInts())
      eq(sg, "unzip empty snd", uzE.1, [])
      eq(sg, "sort", List.sort([3, 1, 2]), [1, 2, 3])
      eq(sg, "sort empty", List.sort(emptyInts()), emptyInts())
      eq(sg, "sort single", List.sort([42]), [42])
      eq(sg, "sort dupes", List.sort([2, 1, 2]), [1, 2, 2])
    })

    group(s1, "head tail filterMap map2", (sg: Suite) => {
      eq(sg, "head", List.head([5, 6]), Some(5))
      eq(sg, "head empty", List.head(emptyInts()), None)
      eq(sg, "tail", List.tail([5, 6, 7]), [6, 7])
      eq(sg, "tail empty", List.tail(emptyInts()), emptyInts())
      eq(sg, "tail singleton", List.tail([9]), emptyInts())
      fun dub(n: Int): Option<Int> = if (n % 2 == 0) Some(n) else None
      eq(sg, "filterMap", List.filterMap([1, 2, 3, 4], dub), [2, 4])
      eq(sg, "filterMap none", List.filterMap([1, 3, 5], dub), emptyInts())
      eq(sg, "filterMap empty", List.filterMap(emptyInts(), dub), emptyInts())
      eq(sg, "map2", List.map2([1, 2], [10, 20], (a: Int, b: Int) => a + b), [11, 22])
      eq(sg, "map2 short ys", List.map2([1, 2, 3], [10, 20], (a: Int, b: Int) => a + b), [11, 22])
      eq(sg, "map2 short xs", List.map2([1], [10, 20, 30], (a: Int, b: Int) => a + b), [11])
    })

    group(s1, "singleton zip mapN", (sg: Suite) => {
      eq(sg, "singleton", List.singleton(7), [7])
      eq(sg, "zip", List.zip([1, 2], ["a", "b"]), [(1, "a"), (2, "b")])
      eq(sg, "zip short", List.zip([1, 2, 3], ["a"]), [(1, "a")])
      eq(
        sg,
        "map3",
        List.map3([1, 2], [10, 20], [100, 200], (a: Int, b: Int, c: Int) => a + b + c),
        [111, 222]
      )
      eq(
        sg,
        "map4",
        List.map4([1, 2], [1, 1], [1, 1], [1, 1], (a: Int, b: Int, c: Int, d: Int) => a + b + c + d),
        [4, 5]
      )
      eq(
        sg,
        "map5",
        List.map5([1], [2], [3], [4], [5], (a: Int, b: Int, c: Int, d: Int, e: Int) => a + b + c + d + e),
        [15]
      )
    })

    group(s1, "takeWhile dropWhile", (sg: Suite) => {
      eq(sg, "takeWhile", List.takeWhile([2, 4, 5, 6], isEven), [2, 4])
      eq(sg, "takeWhile all", List.takeWhile([2, 4], isEven), [2, 4])
      eq(sg, "takeWhile none", List.takeWhile([1, 2], isEven), emptyInts())
      eq(sg, "takeWhile empty", List.takeWhile(emptyInts(), isEven), emptyInts())
      eq(sg, "dropWhile", List.dropWhile([2, 4, 5, 6], isEven), [5, 6])
      eq(sg, "dropWhile all", List.dropWhile([2, 4], isEven), emptyInts())
      eq(sg, "dropWhile none", List.dropWhile([1, 2], isEven), [1, 2])
    })

    group(s1, "generate", (sg: Suite) => {
      eq(sg, "identity indices", List.generate(4, (i: Int) => i), [0, 1, 2, 3])
      eq(sg, "squares",         List.generate(5, (i: Int) => i * i), [0, 1, 4, 9, 16])
      eq(sg, "zero length",     List.generate(0, (i: Int) => i), emptyInts())
    })

    group(s1, "forEach", (sg: Suite) => {
      val acc = Arr.new()
      List.forEach([1, 2, 3], (x: Int) => Arr.push(acc, x))
      eq(sg, "visits all elements in order", Arr.toList(acc), [1, 2, 3])

      val acc2 = Arr.new()
      List.forEach(emptyInts(), (x: Int) => Arr.push(acc2, x))
      eq(sg, "empty list", Arr.toList(acc2), emptyInts())
    })
  })
}
