import { Suite, group, eq, isTrue } from "kestrel:test"

fun optLen(o: Option<Int>): Int =
  if (o is None) { 0 } else {
    match (o) {
      Some(n) => n,
      None => 0
    }
  }

type Fruit = Apple | Orange

fun fruitTag(f: Fruit): Int =
  if (f is Apple) { 1 } else { 2 }

val narrowRec = { x = 1, y = 2 }

export async fun run(s: Suite): Task<Unit> =
  group(s, "is narrowing", (sg: Suite) => {
    eq(sg, "None branch", optLen(None), 0)
    eq(sg, "Some branch", optLen(Some(5)), 5)
    eq(sg, "ADT Apple", fruitTag(Apple), 1)
    eq(sg, "ADT Orange", fruitTag(Orange), 2)
    isTrue(sg, "prim is Int", (42 is Int))
    isTrue(sg, "record subset field", (narrowRec is { x: Int }))
    isTrue(sg, "record full shape", (narrowRec is { x: Int, y: Int }))
  })
