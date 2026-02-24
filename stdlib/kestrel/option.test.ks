import { Suite, group, eq } from "kestrel:test"
import { getOrElse, isNone, isSome } from "kestrel:option"

export fun run(s: Suite): Unit =
  group(s, "option", (s1: Suite) => {
    group(s1, "construction", (sg: Suite) => {
      eq(sg, "Some(42) pattern match", match (Some(42)) { None => 0, Some { value = v } => v }, 42)
      eq(sg, "None pattern match", match (None) { None => 99, Some { value = _ } => 0 }, 99)
    })

    group(s1, "matching", (sg: Suite) => {
      eq(sg, "extract Some(7)", match (Some(7)) { None => 0, Some { value = x } => x }, 7)
      eq(sg, "handle None", match (None) { None => 0, Some { value = x } => x }, 0)
    })

    group(s1, "helpers", (sg: Suite) => {
      eq(sg, "getOrElse Some(5) 0", getOrElse(Some(5), 0), 5)
      eq(sg, "getOrElse None 0", getOrElse(None, 0), 0)
      eq(sg, "getOrElse None 100", getOrElse(None, 100), 100)
      eq(sg, "isSome Some(1)", isSome(Some(1)), True)
      eq(sg, "isSome None", isSome(None), False)
      eq(sg, "isNone None", isNone(None), True)
      eq(sg, "isNone Some(1)", isNone(Some(1)), False)
    })
    
    group(s1, "nested", (sg: Suite) => {
      val inner = match (Some(Some(1))) {
        None => 0,
        Some { value = o } => match (o) { None => 0, Some { value = v } => v }
      }
      eq(sg, "Some(Some(1))", inner, 1)
    })
  })
