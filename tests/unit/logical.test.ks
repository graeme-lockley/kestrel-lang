import { Suite, group, eq, isTrue, isFalse } from "kestrel:dev/test"

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:lang/logical", (s1: Suite) => {
    group(s1, "and", (sg: Suite) => {
      isTrue(sg, "True & True", True & True)
      isFalse(sg, "True & False", True & False)
      isFalse(sg, "False & True", False & True)
      isFalse(sg, "False & False", False & False)
    })

    group(s1, "or", (sg: Suite) => {
      isTrue(sg, "True | False", True | False)
      isTrue(sg, "False | True", False | True)
      isFalse(sg, "False | False", False | False)
      isTrue(sg, "True | True", True | True)
    })
    
    group(s1, "not", (sg: Suite) => {
      isFalse(sg, "!True", !True)
      isTrue(sg, "!False", !False)
    })
    
    group(s1, "compound", (sg: Suite) => {
      isTrue(sg, "!(3>5)&(2<4)", !(3 > 5) & (2 < 4))
      isTrue(sg, "(True|False)&(False|True)", (True | False) & (False | True))
      eq(sg, "if (!(False|False)) -100 else -200", if (!(False | False)) -100 else -200, -100)
    })
    
    group(s1, "short circuit and", (sg: Suite) => {
      isFalse(sg, "False & True yields False", False & True)
      isFalse(sg, "False & False yields False", False & False)
    })
    
    group(s1, "short circuit or", (sg: Suite) => {
      isTrue(sg, "True | False yields True", True | False)
      isTrue(sg, "True | True yields True", True | True)
    })
  })
