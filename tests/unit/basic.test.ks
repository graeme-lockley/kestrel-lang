import { Suite, group, eq } from "kestrel:test"

export fun run(s: Suite): Unit =
  group(s, "basic", (s1: Suite) => {
    eq(s1, "1 + 1 == 2", "${1 + 1}", "${2}");
    eq(s1, "true is true", "${True}", "${True}");
    ()
  })
