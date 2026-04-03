import { Suite, group, eq } from "kestrel:test"
import { parseInt } from "kestrel:string"
import { map } from "kestrel:list"

export async fun run(s: Suite): Task<Unit> =
  group(s, "imported function values", (sg: Suite) => {
    eq(sg, "map([\"1\",\"2\",\"3\"], parseInt)", map(["1", "2", "3"], parseInt), [1, 2, 3])
  })

