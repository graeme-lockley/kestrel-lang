import { find, findIndex, findMap, last } from "kestrel:data/list"

println(find((x) => x > 2, [1, 2, 3, 4]))
// Some(3)

println(find((x) => x > 10, [1, 2, 3]))
// None

println(findIndex((x) => x == 3, [1, 2, 3, 4]))
// Some(2)

println(findIndex((x) => x == 99, [1, 2]))
// None

println(findMap((x) => if (x > 2) Some(x * 10) else None, [1, 2, 3]))
// Some(30)

println(last([1, 2, 3]))
// Some(3)

println(last([]))
// None
