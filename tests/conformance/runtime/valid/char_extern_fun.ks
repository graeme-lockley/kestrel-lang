// Runtime conformance: codePoint, fromCode, charToString via extern fun pathway
import { codePoint, fromCode, charToString } from "kestrel:data/char"

val cp = codePoint('A')
println(cp)
// 65
val s = charToString('Z')
println(s)
// Z
val roundtrip = codePoint(fromCode(98))
println(roundtrip)
// 98
