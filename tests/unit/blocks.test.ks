import { Suite, group, eq } from "kestrel:dev/test"

// Minimal: block with var not inside a closure (direct function return)
fun testVarBlockDirect(): Int = { var x = 0; x := 1; x }

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:lang/blocks", (s1: Suite) => {
    group(s1, "val", (sg: Suite) => {
      eq(sg, "single val", { val x = 1; x }, 1)
      eq(sg, "multiple vals", { val x = 1; val y = 2; x + y }, 3)
      eq(sg, "shadowing", { val x = 10; val x = 2; x }, 2)
    })

    group(s1, "var", (sg: Suite) => {
      eq(sg, "var block in fun (no closure)", testVarBlockDirect(), 1)
      eq(sg, "assign and read", { var x = 0; x := 1; x }, 1)
      eq(sg, "increment pattern", { var x = 5; x := x + 1; x }, 6)
    })

    group(s1, "nested blocks", (sg: Suite) => {
      eq(sg, "block in block", { val x = { val y = 1; y + 1 }; x }, 2)
      eq(sg, "inner shadowing", { val x = 10; val r = { val x = 1; x }; r }, 1)
    })
    
    group(s1, "block as expression", (sg: Suite) => {
      val result = { val a = 1; val b = 2; a + b }
      eq(sg, "bind block result", result, 3)
      eq(sg, "inline block", { val t = { val u = 4; val v = 5; u * v }; t }, 20)
    })
  })
