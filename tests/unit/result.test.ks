import { expectEqual, expectTrue } from "kestrel:test"
import { getOrElse, isOk, isErr } from "kestrel:result"

expectEqual(getOrElse(Ok(10), 0), 10)
expectEqual(getOrElse(Err(1), 99), 99)
expectTrue(isOk(Ok(1)))
expectTrue(isErr(Err(0)))
