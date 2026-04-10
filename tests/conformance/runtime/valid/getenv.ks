// Runtime conformance: getEnv returns Some/None based on environment variable presence
import { getEnv } from "kestrel:sys/process"
import * as Opt from "kestrel:data/option"

val pathOpt = getEnv("PATH")
println(Opt.isSome(pathOpt))
// True

val missing = getEnv("KESTREL_DOES_NOT_EXIST_XYZ_12345")
println(missing)
// None
