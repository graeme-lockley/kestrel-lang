// kestrel:tools/bootstrap — compile the self-hosted Kestrel compiler entry point.
// Usage: kestrel bootstrap

import * as Opt from "kestrel:data/option"
import { getProcess, getEnv, exit } from "kestrel:sys/process"
import * as Compiler from "kestrel:tools/bootstrap/compiler"

// ─── Entry point ──────────────────────────────────────────────────────────────

/// Bootstrap the self-hosted CLI classes into the JVM cache and exit with the result code.
export async fun main(allArgs: List<String>): Task<Unit> = {
  val proc     = getProcess()
  val rootDir  = proc.cwd
  val home     = Opt.withDefault(getEnv("HOME"), "/root")
  val jvmCache = Opt.withDefault(getEnv("KESTREL_JVM_CACHE"), "${home}/.kestrel/jvm")
  val code     = await Compiler.compileCliEntry(rootDir, jvmCache)
  exit(code)
}

main(getProcess().args)
