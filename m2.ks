import { hello } from "./m3.ks"

println("loading m2")

export fun message(): String = "${hello()} worlds from m2!"
