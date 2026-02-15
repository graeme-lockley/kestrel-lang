import { expectEqual, expectTrue } from "kestrel:test"
import { getOrElse, isNone, isSome } from "kestrel:option"

expectEqual(getOrElse(Some(1), 0), 1)
expectEqual(getOrElse(None, 42), 42)
expectTrue(isNone(None))
expectTrue(isSome(Some(1)))
expectTrue(isSome(Some(99)))
