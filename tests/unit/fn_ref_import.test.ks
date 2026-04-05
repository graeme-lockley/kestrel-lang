import { Suite, group, eq } from "kestrel:tools/test"
import { parseInt } from "kestrel:data/string"
import { map } from "kestrel:data/list"

export async fun run(s: Suite): Task<Unit> =
  group(s, "imported function values", (sg: Suite) => {
    eq(sg, "map([\"1\",\"2\",\"3\"], parseInt)", map(["1", "2", "3"], parseInt), [1, 2, 3])
  })

