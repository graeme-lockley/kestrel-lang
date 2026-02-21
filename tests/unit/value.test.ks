import { expectTrue } from "kestrel:test"
import { isNull, isBool, isInt, isFloat, isString, isArray, isObject } from "kestrel:value"

expectTrue(isNull(Null))
expectTrue(isBool(Bool(True)))
expectTrue(isInt(Int(42)))
expectTrue(isFloat(Float(3.14)))
expectTrue(isString(String("hello")))
expectTrue(isArray(Array([])))
expectTrue(isObject(Object([])))
expectTrue(isNull(Bool(False)) == False)
expectTrue(isBool(Null) == False)
