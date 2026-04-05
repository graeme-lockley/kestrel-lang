import { getProcess, runProcess, ProcessSpawnError } from "kestrel:process"
import { listDir, writeText, NotFound, PermissionDenied, IoError, DirEntry, File, Dir } from "kestrel:fs"
import * as Lst from "kestrel:list"
import * as Opt from "kestrel:option"
import * as Str from "kestrel:string"

val proc = getProcess()
val cwd = proc.cwd

fun getRootDir(args: List<String>, fallback: String): String =
  args |> Lst.drop(2) |> Lst.head |> Opt.withDefault(fallback)
  
val rootDir = getRootDir(proc.args, cwd)

fun hasSuffix(s: String, suffix: String): Bool = Str.endsWith(suffix, s)

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

async fun writeTextOrExit(path: String, content: String): Task<Unit> = {
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
}

async fun runProcessOrExit(program: String, args: List<String>): Task<Int> = {
  match (await runProcess(program, args)) {
    Ok(r) => {
      print(r.stdout);
      r.exitCode
    },
    Err(ProcessSpawnError(_)) => {
      println("kestrel test: runProcess failed for ${program}: process error");
      exit(1);
      1
    }
  }
}

fun collectTests(entries: List<DirEntry>, acc: List<String>): List<String> =
  match (entries) {
    [] => acc,
    hd :: tl =>
      match (hd) {
        Dir(_) => collectTests(tl, acc),
        File(p) =>
          if (hasSuffix(p, ".test.ks")) collectTests(tl, p :: acc)
          else collectTests(tl, acc)
      }
  }

fun hasFlag(args: List<String>, flag: String): Bool =
  Lst.any(args, (hd: String) => Str.equals(hd, flag))

fun excludeTestFlags(args: List<String>): List<String> =
  Lst.filter(
    args,
    (hd: String) => !(Str.equals(hd, "--summary") | Str.equals(hd, "--verbose"))
  )

fun checkTestOutputFlags(args: List<String>): Unit = {
  val sum = hasFlag(args, "--summary");
  val verb = hasFlag(args, "--verbose");

  if (sum & verb) {
    println("kestrel test: use either --verbose or --summary, not both");
    exit(1)
  }
}

// argv layout is [exe, script, project root, ...paths]. JVM entry pads with "" "".
fun getPathArgs(allArgs: List<String>): List<String> = excludeTestFlags(Lst.drop(allArgs, 3))

fun filterToTestFiles(paths: List<String>): List<String> =
  Lst.filter(paths, (p: String) => hasSuffix(p, ".test.ks"))

fun isAbsolute(path: String): Bool =
  if (Str.length(path) > 0) Str.equals(Str.slice(path, 0, 1), "/") else False

fun resolvePath(base: String, path: String): String =
  if (isAbsolute(path)) path else "${base}/${path}"

fun resolvePaths(base: String, paths: List<String>): List<String> =
  Lst.map(paths, (p: String) => resolvePath(base, p))

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

val unitDir = "${rootDir}/tests/unit"
val stdlibDir = "${rootDir}/stdlib/kestrel"

async fun main(): Task<Unit> = {
  checkTestOutputFlags(proc.args)

  val pathArgs = getPathArgs(proc.args)
  val outputModeStr =
    if (hasFlag(proc.args, "--summary")) "outputSummary"
    else if (hasFlag(proc.args, "--verbose")) "outputVerbose" 
    else "outputCompact"

  val tests =
    if (Lst.length(pathArgs) == 0) {
      val unitEntries = await listDirOrExit(unitDir)
      val stdlibEntries = await listDirOrExit(stdlibDir)
      val unitTests = collectTests(unitEntries, [])
      val stdlibTests = collectTests(stdlibEntries, [])
      Lst.append(unitTests, stdlibTests)
    } else
      resolvePaths(rootDir, filterToTestFiles(pathArgs))

  val testCount = Lst.length(tests)

  val impLines = buildImports(tests, 0)
  val calls = buildCalls(testCount, 0)

  val genHead =
    "import { printSummary, outputCompact, outputVerbose, outputSummary } from \"kestrel:test\"\nimport { nowMs, isTtyStdout } from \"kestrel:basics\"\n";
  val genMid =
    "\nval isTty = isTtyStdout()\nval counts = { mut passed = 0, mut failed = 0, mut startTime = nowMs(), mut spinnerActive = False, mut compactExpanded = False }\nval root = { depth = 1, output = ";
  val genRest = ", isTty = isTty, counts = counts }\n\nasync fun main(): Task<Unit> = {\n";
  val genTail = "  printSummary(counts);\n  ()\n}\n\nmain()\n";
  val generatedSource =
    "${genHead}${impLines}${genMid}${outputModeStr}${genRest}${calls}${genTail}"

  val generatedPath = "${rootDir}/.kestrel_test_runner.ks"

  // Write to a temp file, then only replace if content changed (preserves timestamp to avoid recompilation)
  val tmpPath = "${generatedPath}.new"
  await writeTextOrExit(tmpPath, generatedSource)
  val _cmp = await runProcessOrExit("sh", ["-c", "cmp -s '${tmpPath}' '${generatedPath}' 2>/dev/null && rm '${tmpPath}' || mv '${tmpPath}' '${generatedPath}'"])

  val exitCode = await runProcessOrExit("./scripts/kestrel", ["run", generatedPath])
  exit(exitCode)
}

main()
