import * as Res from "kestrel:result"
import * as Str from "kestrel:string"
import { map } from "kestrel:task"

export type ProcessError = ProcessSpawnError(String)

export type ProcessResult = { exitCode: Int, stdout: String }

extern fun getOs(): String =
  jvm("kestrel.runtime.KRuntime#getOs()")

extern fun getArgs(): List<String> =
  jvm("kestrel.runtime.KRuntime#getArgs()")

extern fun getCwd(): String =
  jvm("kestrel.runtime.KRuntime#getCwd()")

extern fun runProcessAsync(program: String, args: List<String>): Task<Result<ProcessResult, String>> =
  jvm("kestrel.runtime.KRuntime#runProcessAsync(java.lang.Object,java.lang.Object)")

export fun getProcess(): P = {
  val os = getOs();
  val a = getArgs();
  val c = getCwd();
  { os = os, args = a, env = [], cwd = c }
}

fun mapProcessError(code: String): ProcessError =
  if (Str.startsWith("process_error:", code)) ProcessSpawnError(Str.dropLeft(code, 14))
  else ProcessSpawnError(code)

export fun runProcess(program: String, args: List<String>): Task<Result<ProcessResult, ProcessError>> =
  map(runProcessAsync(program, args), (result: Result<ProcessResult, String>) => Res.mapError(result, mapProcessError))
