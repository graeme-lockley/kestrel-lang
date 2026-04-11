import { toHexString, toHexStringPadded, toBinaryString, toOctalString } from "kestrel:data/string"

println(toHexString(255))
// ff

println(toHexString(0))
// 0

println(toHexString(16))
// 10

println(toHexStringPadded(4, 255))
// 00ff

println(toHexStringPadded(2, 255))
// ff

println(toBinaryString(5))
// 101

println(toBinaryString(0))
// 0

println(toOctalString(8))
// 10

println(toOctalString(0))
// 0
