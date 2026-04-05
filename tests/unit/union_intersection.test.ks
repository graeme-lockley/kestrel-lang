import { Suite, group, eq } from "kestrel:tools/test"

fun takeU(x: Int | Bool): Int = if (x is Int) x else 0

export async fun run(s: Suite): Task<Unit> =
  group(s, "union subtyping at runtime", (sg: Suite) => {
    eq(sg, "call with Int literal", takeU(7), 7)
    eq(sg, "call with Bool", takeU(False), 0)
  })
