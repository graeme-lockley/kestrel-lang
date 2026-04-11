import { sortBy, sortWith } from "kestrel:data/list"
import { length } from "kestrel:data/string"

println(sortBy((x) => x, [3, 1, 2]))
// [1, 2, 3]

println(sortWith((a, b) => a - b, [3, 1, 2]))
// [1, 2, 3]

println(sortWith((a, b) => b - a, [3, 1, 2]))
// [3, 2, 1]

println(sortBy((s) => length(s), ["bb", "a", "ccc"]))
// [a, bb, ccc]

println(sortBy((x) => x, []))
// []

println(sortBy((x) => x, [42]))
// [42]
