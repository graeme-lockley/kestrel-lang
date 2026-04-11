import { getProcess, getEnv } from "kestrel:sys/process"
import * as Lst from "kestrel:data/list"

val env = getProcess().env

println(Lst.length(env) > 0)
// True

val pathEntries = Lst.filter(env, (entry: (String, String)) => entry.0 == "PATH")
println(Lst.length(pathEntries) > 0)
// True

val pathVal = match (Lst.head(pathEntries)) {
  Some(e) => e.1,
  None => ""
}
println(getEnv("PATH") == Some(pathVal))
// True
