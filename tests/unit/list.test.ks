import { expectEqual, expectTrue } from "kestrel:test"
import { length, isEmpty } from "kestrel:list"

expectEqual(length([]), 0)
expectEqual(length([1]), 1)
expectEqual(length([1, 2, 3]), 3)
expectTrue(isEmpty([]))
expectTrue(isEmpty([]))
