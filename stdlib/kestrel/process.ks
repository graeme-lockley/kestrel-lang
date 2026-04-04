import * as Res from "kestrel:result"
import * as Str from "kestrel:string"
import { map } from "kestrel:task"

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

export fun runProcess(program: String, args: List<String>): Task<Result<ProcessResult, ProcessError>> =
  map(__run_process(program, args), (result: Result<ProcessResult, String>) => Res.mapError(result, mapProcessError))
