import { Suite, group, eq } from "kestrel:test"
import { getOrElse, isOk, isErr } from "kestrel:result"

export fun run(s: Suite): Unit =
  group(s, "result", (s1: Suite) => {
    group(s1, "construction", (sg: Suite) => {
      eq(sg, "Ok(42) pattern match", match (Ok(42)) { Err { value = _ } => 0, Ok { value = v } => v }, 42)
      eq(sg, "Err(1) pattern match", match (Err(1)) { Err { value = e } => e, Ok { value = _ } => 0 }, 1)
    })

    group(s1, "matching", (sg: Suite) => {
      eq(sg, "extract Ok(7)", match (Ok(7)) { Err { value = _ } => 0, Ok { value = x } => x }, 7)
      eq(sg, "extract Err(3)", match (Err(3)) { Err { value = e } => e, Ok { value = _ } => 0 }, 3)
    })
    
    group(s1, "helpers", (sg: Suite) => {
      eq(sg, "getOrElse Ok(5) 0", getOrElse(Ok(5), 0), 5)
      eq(sg, "getOrElse Err(1) 0", getOrElse(Err(1), 0), 0)
      eq(sg, "getOrElse Err(1) 100", getOrElse(Err(1), 100), 100)
      eq(sg, "isOk Ok(1)", isOk(Ok(1)), True)
      eq(sg, "isOk Err(1)", isOk(Err(1)), False)
      eq(sg, "isErr Err(1)", isErr(Err(1)), True)
      eq(sg, "isErr Ok(1)", isErr(Ok(1)), False)
    })
  })
