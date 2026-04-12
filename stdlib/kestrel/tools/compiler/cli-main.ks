import * as Lst from "kestrel:data/list"
import { getProcess, runProcessStream, ProcessSpawnError, exit } from "kestrel:sys/process"
import * as Driver from "kestrel:tools/compiler/driver"

export type ParsedCommand = {
  command: String,
  args: List<String>
}

fun usage(): String =
  "Usage: kestrel <run|build|dis|test|fmt|doc|lock> [args...]"

fun supported(command: String): Bool =
  command == "run" | command == "build" | command == "dis" |
  command == "test" | command == "fmt" | command == "doc" |
  command == "lock"

export fun parseCommand(argv: List<String>): Result<ParsedCommand, String> =
  match (argv) {
    [] => Err(usage())
    command :: rest =>
      if (supported(command)) Ok({ command = command, args = rest })
      else Err("unknown command: ${command}\n${usage()}")
  }

export fun forwardArgs(parsed: ParsedCommand): (String, List<String>) =
  ("./kestrel", parsed.command :: parsed.args)

fun defaultCompileOptions(cwd: String): Driver.CompileOptions = {
  outDir = "${cwd}/.kestrel/jvm",
  stdlibDir = "${cwd}/stdlib",
  cacheRoot = "${cwd}/.kestrel/cache",
  allowHttp = False,
  writeKti = True
}

async fun runBuildScaffold(args: List<String>, cwd: String): Task<Int> =
  match (args) {
    [] => 0
    entryPath :: _ => {
      val result = await Driver.compileFile(entryPath, defaultCompileOptions(cwd));
      if (result.ok) 0
      else {
        println("kestrel cli: driver scaffold compile failed for ${entryPath}");
        1
      }
    }
  }

async fun dispatch(parsed: ParsedCommand, cwd: String): Task<Int> = {
  val buildStatus =
    if (parsed.command == "build") await runBuildScaffold(parsed.args, cwd)
    else 0;
  if (buildStatus != 0) buildStatus
  else {
    val forward = forwardArgs(parsed);
    match (await runProcessStream(forward.0, forward.1)) {
      Ok(code) => code
      Err(ProcessSpawnError(_)) => {
        println("kestrel cli: process spawn error");
        1
      }
    }
  }
}

export async fun main(allArgs: List<String>): Task<Unit> = {
  val proc = getProcess()
  val code =
    match (parseCommand(allArgs)) {
      Ok(parsed) => await dispatch(parsed, proc.cwd)
      Err(msg) => {
        println(msg);
        1
      }
    }
  exit(code)
}