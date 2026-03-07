import { Suite, group, eq } from "kestrel:test"

// Nullary constructors
type Color = Red | Green | Blue

fun colorToInt(c: Color): Int = match (c) {
  Red => 0
  Green => 1
  Blue => 2
}

// Non-generic Option type (Kestrel doesn't support type parameters on type decls)
type Opt = None | Some(Int)

fun unwrap(o: Opt): Int = match (o) {
  None => 0
  Some { field_0 = x } => x
}

// Multi-arg constructors - using record-style with numbered fields
type Tree = Leaf(Int) | Node(Tree, Tree)

fun treeSum(t: Tree): Int = match (t) {
  Leaf { field_0 = x } => x
  Node { field_0 = l, field_1 = r } => treeSum(l) + treeSum(r)
}

// Single constructor
type Point = MkPoint(Int, Int)

fun pointX(p: Point): Int = match (p) {
  MkPoint { field_0 = x, field_1 = y } => x
}

fun pointY(p: Point): Int = match (p) {
  MkPoint { field_0 = x, field_1 = y } => y
}

export fun run(s: Suite): Unit =
  group(s, "user-defined ADTs", (s1: Suite) => {
    group(s1, "nullary constructors", (sg: Suite) => {
      eq(sg, "Red to int", colorToInt(Red), 0)
      eq(sg, "Green to int", colorToInt(Green), 1)
      eq(sg, "Blue to int", colorToInt(Blue), 2)
    })

    group(s1, "unary constructors", (sg: Suite) => {
      eq(sg, "unwrap Some(5)", unwrap(Some(5)), 5)
      eq(sg, "unwrap Some(42)", unwrap(Some(42)), 42)
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
