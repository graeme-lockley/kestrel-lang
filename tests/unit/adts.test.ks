import { Suite, group, eq } from "kestrel:test"

// Nullary constructors
type Color = Red | Green | Blue

fun colorToInt(c: Color): Int = match (c) {
  Red => 0
  Green => 1
  Blue => 2
}

// Generic Option type
type Opt<T> = None | Some(T)

fun unwrap<T>(o: Opt<T>, default: T): T = match (o) {
  None => default
  Some(x) => x
}

// Generic Tree type
type Tree<T> = Leaf(T) | Node(Tree<T>, Tree<T>)

fun treeMap<T, R>(t: Tree<T>, f: (T) -> R): Tree<R> = match (t) {
  Leaf(x) => Leaf(f(x))
  Node(l, r) => Node(treeMap(l, f), treeMap(r, f))
}

fun treeSum(t: Tree<Int>): Int = match (t) {
  Leaf(x) => x
  Node(l, r) => treeSum(l) + treeSum(r)
}

// Single constructor - non-generic
type Point = MkPoint(Int, Int)

fun pointX(p: Point): Int = match (p) {
  MkPoint(x, _) => x
}

fun pointY(p: Point): Int = match (p) {
  MkPoint(_, y) => y
}

export fun run(s: Suite): Unit =
  group(s, "user-defined ADTs", (s1: Suite) => {
    group(s1, "nullary constructors", (sg: Suite) => {
      eq(sg, "Red to int", colorToInt(Red), 0)
      eq(sg, "Green to int", colorToInt(Green), 1)
      eq(sg, "Blue to int", colorToInt(Blue), 2)
    })

    group(s1, "generic ADTs", (sg: Suite) => {
      eq(sg, "unwrap Some(5)", unwrap(Some(5), 0), 5)
      eq(sg, "unwrap Some(42)", unwrap(Some(42), 0), 42)
      eq(sg, "unwrap None Int", unwrap(None, 100), 100)
      eq(sg, "unwrap None String", unwrap(None, "default"), "default")
      eq(sg, "treeMap double", treeMap(Leaf(3), (x) => x * 2), Leaf(6))
      eq(sg, "treeMap toString", treeMap(Leaf(5), (x) => x), Leaf(5))
    })

    group(s1, "multi-arg constructors", (sg: Suite) => {
      eq(sg, "treeSum Leaf(5)", treeSum(Leaf(5)), 5)
      eq(sg, "treeSum Node(Leaf(1), Leaf(2))", treeSum(Node(Leaf(1), Leaf(2))), 3)
      val tree3 = Node(Node(Leaf(1), Leaf(2)), Leaf(3))
      eq(sg, "treeSum tree3", treeSum(tree3), 6)
      eq(sg, "pointX MkPoint(3, 4)", pointX(MkPoint(3, 4)), 3)
      eq(sg, "pointY MkPoint(3, 4)", pointY(MkPoint(3, 4)), 4)
    })
  })
