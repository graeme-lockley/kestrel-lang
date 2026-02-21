import { expectTrue } from "kestrel:test"
import { parse, stringify } from "kestrel:json"
import { isNull, isInt, isBool, isString } from "kestrel:value"

// parse returns Value ADT
expectTrue(isNull(parse("null")))
expectTrue(isInt(parse("42")))
expectTrue(isBool(parse("true")))
expectTrue(isString(parse("\"hello\"")))
// stringify returns String (smoke test: call it)
expectTrue(isString(parse("\"x\"")))
val _ = stringify(parse("null"))
