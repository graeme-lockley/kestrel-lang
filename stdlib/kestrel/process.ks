import * as Res from "kestrel:result"
import * as Str from "kestrel:string"

export type ProcessError = ProcessSpawnError(String)

export type ProcessResult = { exitCode: Int, stdout: String }

export fun getProcess(): P = {
  val os = __get_os();
  val a = __get_args();
  val c = __get_cwd();
  { os = os, args = a, env = [], cwd = c }
}

fun mapProcessError(code: String): ProcessError =
  if (Str.startsWith("process_error:", code)) ProcessSpawnError(Str.dropLeft(code, 14))
  else ProcessSpawnError(code)

export async fun runProcess(program: String, args: List<String>): Task<Result<ProcessResult, ProcessError>> = {
  val result = await __run_process(program, args)
  Res.mapError(result, mapProcessError)
}
