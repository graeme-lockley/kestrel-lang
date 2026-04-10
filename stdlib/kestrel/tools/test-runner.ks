// kestrel:tools/test-runner — discover and run Kestrel unit tests.
// Usage: kestrel test [--verbose|--summary] [--generate] [--clean] [--refresh] [--allow-http] [files...]

import * as Lst from "kestrel:data/list"
import * as Opt from "kestrel:data/option"
import * as Str from "kestrel:data/string"
import * as Dict from "kestrel:data/dict"
import * as Cli from "kestrel:dev/cli"
import { CliSpec, ParsedArgs, Flag } from "kestrel:dev/cli"
import { getProcess, getEnv, runProcessStream, ProcessSpawnError } from "kestrel:sys/process"
import { listDir, writeText, readText, renameFile, deleteFile, NotFound, PermissionDenied, IoError, DirEntry, File, Dir } from "kestrel:io/fs"
import { all } from "kestrel:sys/task"

// ─── CLI spec ─────────────────────────────────────────────────────────────────

val cliSpec = {
  name = "kestrel test",
  version = "0.1.0",
  description = "Discover and run Kestrel unit tests",
  usage = "kestrel test [--verbose|--summary] [--generate] [--clean] [--refresh] [--allow-http] [files...]",
  options = [
    {
      short = Some("-v"),
      long = "--verbose",
      kind = Flag,
      description = "Print each test result"
    },
    {
      short = Some("-s"),
      long = "--summary",
      kind = Flag,
      description = "Print only the final summary line"
    },
    {
      short = None,
      long = "--generate",
      kind = Flag,
      description = "Write the generated runner file and exit without running tests"
    },
    {
      short = None,
      long = "--clean",
      kind = Flag,
      description = "Delete compiler cache before compiling the generated runner"
    },
    {
      short = None,
      long = "--refresh",
      kind = Flag,
      description = "Re-fetch all remote dependencies"
    },
    {
      short = None,
      long = "--allow-http",
      kind = Flag,
      description = "Allow plain http:// imports"
    }
  ],
  args = [
    {
      name = "paths",
      description = "Test files or directories (default: tests/unit/ and stdlib/kestrel/ up to 3 levels)",
      variadic = True
    }
  ]
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

fun hasSuffix(s: String, suffix: String): Bool = Str.endsWith(suffix, s)

fun isAbsolute(path: String): Bool =
  if (Str.length(path) > 0) Str.equals(Str.slice(path, 0, 1), "/") else False

fun resolvePath(base: String, path: String): String =
  if (isAbsolute(path)) path else "${base}/${path}"

fun resolvePaths(base: String, paths: List<String>): List<String> =
  Lst.map(paths, (p: String) => resolvePath(base, p))

fun filterToTestFiles(paths: List<String>): List<String> =
  Lst.filter(paths, (p: String) => hasSuffix(p, ".test.ks"))

async fun listDirOrExit(path: String): Task<List<DirEntry>> =
  match (await listDir(path)) {
    Ok(entries) => entries,
    Err(err) => {
      val message =
        match (err) {
          NotFound => "not found"
          PermissionDenied => "permission denied"
          IoError(_) => "io error"
        };
      println("kestrel test: listDir failed for ${path}: ${message}");
      exit(1);
      []
    }
  }

fun getTestFilePaths(entries: List<DirEntry>, acc: List<String>): List<String> =
  match (entries) {
    [] => acc,
    hd :: tl => match (hd) {
      Dir(_) => getTestFilePaths(tl, acc),
      File(p) => if (hasSuffix(p, ".test.ks")) getTestFilePaths(tl, p :: acc)
                 else getTestFilePaths(tl, acc)
    }
  }

fun getDirPaths(entries: List<DirEntry>, acc: List<String>): List<String> =
  match (entries) {
    [] => acc,
    hd :: tl => match (hd) {
      Dir(path) => getDirPaths(tl, path :: acc),
      File(_) => getDirPaths(tl, acc)
    }
  }

async fun writeTextOrExit(path: String, content: String): Task<Unit> =
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

async fun runProcessStreamOrExit(program: String, args: List<String>): Task<Int> =
  match (await runProcessStream(program, args)) {
    Ok(exitCode) => exitCode,
    Err(ProcessSpawnError(_)) => {
      println("kestrel test: runProcess failed for ${program}: process error");
      exit(1);
      1
    }
  }

fun buildImports(tests: List<String>, idx: Int): String =
  match (tests) {
    [] => "",
    hd :: tl =>
      "import { run as run${Str.fromInt(idx)} } from \"${hd}\"\n${buildImports(tl, idx + 1)}"
  }

fun buildCalls(count: Int, idx: Int): String =
  if (idx >= count)
    ""
  else
    "  await run${Str.fromInt(idx)}(root)\n${buildCalls(count, idx + 1)}"

fun collectFlag(parsed: ParsedArgs, flag: String): List<String> =
  match (Dict.get(parsed.options, Str.dropLeft(flag, 2))) {
    Some(_) => [flag]
    None => []
  }

fun buildCompilerFlags(parsed: ParsedArgs): List<String> =
  Lst.concat([
    collectFlag(parsed, "--clean"),
    collectFlag(parsed, "--refresh"),
    collectFlag(parsed, "--allow-http")
  ])

// ─── Handler ──────────────────────────────────────────────────────────────────

/** Entry point for `kestrel:tools/test-runner` (invoked via `./kestrel run kestrel:tools/test-runner`).
 *  proc.cwd is the project root. KESTREL_BIN env var identifies the kestrel binary. */
async fun handler(parsed: ParsedArgs): Task<Int> = {
  val proc = getProcess()
  val rootDir = proc.cwd
  val kestrelBin = Opt.withDefault(getEnv("KESTREL_BIN"), "${rootDir}/kestrel")
  val outputModeStr =
    match (Dict.get(parsed.options, "summary")) {
      Some(_) => "outputSummary"
      None =>
        match (Dict.get(parsed.options, "verbose")) {
          Some(_) => "outputVerbose"
          None => "outputCompact"
        }
    }

  val unitDir = "${rootDir}/tests/unit"
  val stdlibDir = "${rootDir}/stdlib/kestrel"

  val tests =
    if (Lst.isEmpty(parsed.positional)) {
      val unitEntries = await listDirOrExit(unitDir)
      val unitTests = getTestFilePaths(unitEntries, [])
      val stdlibEntries = await listDirOrExit(stdlibDir)
      val stdlibTopFiles = getTestFilePaths(stdlibEntries, [])
      val level1Dirs = getDirPaths(stdlibEntries, [])
      val level1EntryLists = await all(Lst.map(level1Dirs, (d: String) => listDirOrExit(d)))
      val level1Entries = Lst.concat(level1EntryLists)
      val level1Files = getTestFilePaths(level1Entries, [])
      val level2Dirs = getDirPaths(level1Entries, [])
      val level2EntryLists = await all(Lst.map(level2Dirs, (d: String) => listDirOrExit(d)))
      val level2Entries = Lst.concat(level2EntryLists)
      val level2Files = getTestFilePaths(level2Entries, [])
      val stdlibTests = Lst.append(stdlibTopFiles, Lst.append(level1Files, level2Files))
      Lst.append(unitTests, stdlibTests)
    } else
      resolvePaths(rootDir, filterToTestFiles(parsed.positional))

  val testCount = Lst.length(tests)
  val impLines = buildImports(tests, 0)
  val calls = buildCalls(testCount, 0)

  val genHead =
    "import { printSummary, makeRoot, outputCompact, outputVerbose, outputSummary } from \"kestrel:tools/test\"\n";
  val genMid =
    "\nasync fun main(): Task<Unit> = {\n  val root = makeRoot(";
  val genRest = ")\n";
  val genTail = "  printSummary(root);\n  ()\n}\n\nmain()\n";
  val generatedSource =
    "${genHead}${impLines}${genMid}${outputModeStr}${genRest}${calls}${genTail}"

  val generatedPath = "${rootDir}/.kestrel_test_runner.ks"
  val tmpPath = "${generatedPath}.new"
  await writeTextOrExit(tmpPath, generatedSource)

  val existing = await readText(generatedPath)
  val needsUpdate =
    match (existing) {
      Ok(content) => !Str.equals(content, generatedSource)
      Err(_) => True
    }

  if (needsUpdate) {
    val _ = await renameFile(tmpPath, generatedPath);
    ()
  } else {
    val _ = await deleteFile(tmpPath);
    ()
  };

  match (Dict.get(parsed.options, "generate")) {
    Some(_) => 0
    None => {
      val compilerFlags = buildCompilerFlags(parsed)
      val innerArgs = Lst.append(["run"], Lst.append(compilerFlags, [generatedPath]))
      await runProcessStreamOrExit(kestrelBin, innerArgs)
    }
  }
}

// ─── Entry point ─────────────────────────────────────────────────────────────

export async fun main(allArgs: List<String>): Task<Unit> = {
  val code = await Cli.run(cliSpec, handler, allArgs)
  exit(code)
}

main(getProcess().args)
