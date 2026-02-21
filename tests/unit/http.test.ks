import { expectTrue } from "kestrel:test"
import { nowMs } from "kestrel:http"

// nowMs returns current time in milliseconds
val t = nowMs()
expectTrue(t >= 0)
