import { parseIntRadix, formatInt, indexOfChar } from "kestrel:data/string"

println(parseIntRadix(16, "ff"))
// Some(255)

println(parseIntRadix(16, "FF"))
// Some(255)

println(parseIntRadix(2, "1010"))
// Some(10)

println(parseIntRadix(8, "17"))
// Some(15)

println(parseIntRadix(10, "42"))
// Some(42)

println(parseIntRadix(16, "xyz"))
// None

println(parseIntRadix(16, ""))
// None

println(formatInt(4, 255))
// 0255

println(formatInt(4, 1))
// 0001

println(formatInt(4, 12345))
// 12345

println(indexOfChar('b', "abc"))
// Some(1)

println(indexOfChar('z', "abc"))
// None
