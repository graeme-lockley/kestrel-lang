import { inc } from "./mut_helper.ks"

val rec = { mut x = 0 }
inc(rec)
println(__format_one(rec.x))
