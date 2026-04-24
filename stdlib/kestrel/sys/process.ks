//! Process and environment access utilities.
//!
//! Exposes process metadata (args/cwd/os/env), subprocess execution helpers,
//! and exit control for command-line tools.
//!
//! ## Quick Start
//!
//! ```kestrel
//! import * as Proc from "kestrel:sys/process"
//!
//! val p = Proc.getProcess()
//! val who = Proc.getEnv("USER")
//! val r = await Proc.runProcess("echo", ["hello"])
//! ```

import * as Res from "kestrel:data/result"
import * as Str from "kestrel:data/string"
import { map } from "kestrel:sys/task"

export type ProcessError = ProcessSpawnError(String)

export type ProcessResult = { exitCode: Int, stdout: String }

extern fun getOs(): String =
  jvm("kestrel.runtime.KRuntime#getOs()")

extern fun getArgs(): List<String> =
  jvm("kestrel.runtime.KRuntime#getArgs()")

extern fun getCwd(): String =
  jvm("kestrel.runtime.KRuntime#getCwd()")

export extern fun getEnv(name: String): Option<String> =
  jvm("kestrel.runtime.KRuntime#getEnv(java.lang.Object)")

extern fun getEnvAllImpl(): List<(String, String)> =
  jvm("kestrel.runtime.KRuntime#getEnvAll()")

extern fun runProcessAsync(program: String, args: List<String>): Task<Result<ProcessResult, String>> =
  jvm("kestrel.runtime.KRuntime#runProcessAsync(java.lang.Object,java.lang.Object)")

extern fun runProcessStreamAsync(program: String, args: List<String>): Task<Result<Int, String>> =
  jvm("kestrel.runtime.KRuntime#runProcessStreamAsync(java.lang.Object,java.lang.Object)")

export extern fun exit(code: Int): Unit =
  jvm("kestrel.runtime.KRuntime#exit(java.lang.Object)")

export fun getProcess(): P = {
  val os = getOs();
  val a = getArgs();
  val c = getCwd();
  { os = os, args = a, env = getEnvAllImpl(), cwd = c }
}

fun mapProcessError(code: String): ProcessError =
  if (Str.startsWith("process_error:", code)) ProcessSpawnError(Str.dropLeft(code, 14))
  else ProcessSpawnError(code)

export fun runProcess(program: String, args: List<String>): Task<Result<ProcessResult, ProcessError>> =
  map(runProcessAsync(program, args), (result: Result<ProcessResult, String>) => Res.mapError(result, mapProcessError))

export fun runProcessStream(program: String, args: List<String>): Task<Result<Int, ProcessError>> =
  map(runProcessStreamAsync(program, args), (result: Result<Int, String>) => Res.mapError(result, mapProcessError))

export extern fun runInProcess(classpath: List<String>, mainClass: String, args: List<String>): Unit =
  jvm("kestrel.runtime.KRuntime#runInProcess(java.lang.Object,java.lang.Object,java.lang.Object)")

export extern fun setSystemProperty(key: String, value: String): Unit =
  jvm("kestrel.runtime.KRuntime#setSystemProperty(java.lang.Object,java.lang.Object)")
