import { Suite, group, eq } from "kestrel:dev/test"
import { counter } from "../fixtures/export_var_helper.ks"

export async fun run(s: Suite): Task<Unit> =
  group(s, "export var", (s1: Suite) => {
    counter := 0
    val c0 = counter
    eq(s1, "initial value", c0, 0)
    counter := 42
    val c1 = counter
    eq(s1, "after assign", c1, 42)
    counter := 100
    val c3 = counter
    eq(s1, "second assign", c3, 100)
  })
