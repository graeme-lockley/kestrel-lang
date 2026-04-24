//! Generated-runner builder/executor for `kestrel test`.
//!
//! Produces the synthetic test runner source, writes only when changed, and
//! invokes subprocess execution with selected compiler/runtime flags.

import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"
import * as Dict from "kestrel:data/dict"
import { ParsedArgs } from "kestrel:dev/cli"
import { runProcessStream, ProcessSpawnError } from "kestrel:sys/process"
import { writeText, readText, renameFile, deleteFile, NotFound, PermissionDenied, IoError } from "kestrel:io/fs"

// ─── Code generation ──────────────────────────────────────────────────────────

export fun buildImports(tests: List<String>, idx: Int): String =
  match (tests) {
    [] => "",
    hd :: tl =>
      "import { run as run${Str.fromInt(idx)} } from \"${hd}\"\n${buildImports(tl, idx + 1)}"
  }

export fun buildCalls(count: Int, idx: Int): String =
  if (idx >= count)
    ""
  else
    "  await run${Str.fromInt(idx)}(root)\n${buildCalls(count, idx + 1)}"

/** Assemble the complete generated-runner source for the given test list and output mode. */
export fun buildSource(tests: List<String>, outputModeStr: String): String = {
  val testCount = Lst.length(tests)
  val impLines = buildImports(tests, 0)
  val calls = buildCalls(testCount, 0)
  val genHead =
    "import { printSummary, makeRoot, outputCompact, outputVerbose, outputSummary } from \"kestrel:dev/test\"\n";
  val genMid =
    "\nasync fun main(): Task<Unit> = {\n  val root = makeRoot(";
  val genRest = ")\n";
  val genTail = "  printSummary(root);\n  ()\n}\n\nmain()\n";
  "${genHead}${impLines}${genMid}${outputModeStr}${genRest}${calls}${genTail}"
}

// ─── File I/O ─────────────────────────────────────────────────────────────────

export async fun writeTextOrExit(path: String, content: String): Task<Unit> =
  match (await writeText(path, content)) {
    Ok(_) => (),
    Err(err) => {
      val message =
        match (err) {
          NotFound => "not found"
          PermissionDenied => "permission denied"
          IoError(_) => "io error"
        };
      println("kestrel test: writeText failed for ${path}: ${message}");
      exit(1)
    }
  }

/** Write `generatedPath` only when the source differs from what is already on disk.
 *  Uses a temporary file and atomic rename to avoid partial writes. */
export async fun writeRunnerIfChanged(generatedPath: String, source: String): Task<Unit> = {
  val tmpPath = "${generatedPath}.new"
  await writeTextOrExit(tmpPath, source)
  val existing = await readText(generatedPath)
  val needsUpdate =
    match (existing) {
      Ok(content) => !Str.equals(content, source)
      Err(_) => True
    }
  if (needsUpdate) {
    val _ = await renameFile(tmpPath, generatedPath);
    ()
  } else {
    val _ = await deleteFile(tmpPath);
    ()
  }
}

// ─── Subprocess execution ─────────────────────────────────────────────────────

export async fun runProcessStreamOrExit(program: String, args: List<String>): Task<Int> =
  match (await runProcessStream(program, args)) {
    Ok(exitCode) => exitCode,
    Err(ProcessSpawnError(_)) => {
      println("kestrel test: runProcess failed for ${program}: process error");
      exit(1);
      1
    }
  }

// ─── Compiler flag helpers ────────────────────────────────────────────────────

export fun collectFlag(parsed: ParsedArgs, flag: String): List<String> =
  match (Dict.get(parsed.options, Str.dropLeft(flag, 2))) {
    Some(_) => [flag]
    None => []
  }

export fun buildCompilerFlags(parsed: ParsedArgs): List<String> =
  Lst.concat([
    collectFlag(parsed, "--clean"),
    collectFlag(parsed, "--refresh"),
    collectFlag(parsed, "--allow-http")
  ])
