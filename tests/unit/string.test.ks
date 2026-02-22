import { expectEqual, expectTrue } from "kestrel:test"
import { length, slice, indexOf, equals, toUpperCase } from "kestrel:string"

expectEqual(length(""), 0)
expectEqual(length("hello"), 5)
expectEqual(length("a"), 1)
expectTrue(equals("", ""))
expectTrue(equals("hi", "hi"))
expectTrue(equals(slice("hello", 0, 2), "he"))
expectEqual(indexOf("hello", "ll"), 2)
expectEqual(indexOf("hello", "x"), -1)
expectTrue(equals(toUpperCase("abc"), "ABC"))
