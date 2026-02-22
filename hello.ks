import { message as message1 } from "./m1.ks"
import { message as message2 } from "./m2.ks"

import { hello } from "./m3.ks"

println(message1())
println(message2())

hello := "hello"

println({a = 1, b = hello})
println([1, 2, 3, 4, 5])
println(Some(10))
