import { expectTrue } from "kestrel:test"
import { format, print } from "kestrel:stack"
import { length } from "kestrel:string"

// format returns a non-empty string for numbers
expectTrue(length(format(42)) >= 1)
expectTrue(length(format(0)) >= 1)
// print runs without error (smoke test)
val _ = print(99)
