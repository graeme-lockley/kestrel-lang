import { empty, singleton, insert, remove, get, member, size, isEmpty, fromList, toList, map, filter, foldl, union, diff, intersect } from "kestrel:data/structdict"
import { length, sortBy } from "kestrel:data/list"

println(isEmpty(empty()))
// True

println(size(singleton(1, "one")))
// 1

println(get(insert(insert(empty(), 1, "one"), 2, "two"), 1))
// Some(one)

println(get(insert(insert(empty(), 1, "one"), 2, "two"), 99))
// None

println(member(insert(empty(), Some(42), "x"), Some(42)))
// True

println(member(insert(empty(), Some(42), "x"), Some(99)))
// False

println(get(insert(empty(), Some(1), "hello"), Some(1)))
// Some(hello)

println(size(remove(insert(insert(empty(), 1, "a"), 2, "b"), 1)))
// 1

println(get(remove(insert(insert(empty(), 1, "a"), 2, "b"), 1), 1))
// None

println(size(fromList([(1, "a"), (2, "b"), (3, "c")])))
// 3

println(length(toList(fromList([(1, "a"), (2, "b")]))))
// 2
