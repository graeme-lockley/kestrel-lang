import { getProcess, runProcess } from "kestrel:process"
import { listDir, writeText } from "kestrel:fs"
import * as Lst from "kestrel:list"
import * as Str from "kestrel:string"

val proc = getProcess()
val cwd = proc.cwd

fun getRootDir(args: List<String>, fallback: String): String =
  match (Lst.take(1, Lst.drop(2, args))) {
    [] => fallback,
    hd :: _ => hd
  }
  
val rootDir = getRootDir(proc.args, cwd)

fun hasSuffix(s: String, suffix: String): Bool = Str.endsWith(suffix, s)

fun collectTests(entries: List<String>, acc: List<String>): List<String> =
  match (entries) {
    [] => acc,
    hd :: tl => {
      val tabIdx = Str.indexOf(hd, "\t");
      val path = if (tabIdx >= 0) Str.slice(hd, 0, tabIdx) else hd;
      val kind =
        if (tabIdx >= 0) Str.slice(hd, tabIdx + 1, Str.length(hd)) else "file";
      if (Str.equals(kind, "dir")) {
        val subEntries = listDir(path);
        val subAcc = collectTests(subEntries, acc);
        collectTests(tl, subAcc)
      }
      else if (hasSuffix(path, ".test.ks")) collectTests(tl, path :: acc)
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

// argv layout must match VM: [vm binary, .kbc path, project root, ...paths]. JVM entry pads with "" "".
fun getPathArgs(allArgs: List<String>): List<String> = excludeTestFlags(Lst.drop(3, allArgs))

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
    "run${Str.fromInt(idx)}(root)\n${buildCalls(count, idx + 1)}"

val unitDir = "${rootDir}/tests/unit"
val stdlibDir = "${rootDir}/stdlib/kestrel"
val _flagsOk = checkTestOutputFlags(proc.args)
val pathArgs = getPathArgs(proc.args)
val outputModeStr =
  if (hasFlag(proc.args, "--summary")) "outputSummary"
  else if (hasFlag(proc.args, "--verbose")) "outputVerbose" 
  else "outputCompact"

val tests = 
  if (Lst.length(pathArgs) == 0) {
    val unitEntries = listDir(unitDir)
    val stdlibEntries = listDir(stdlibDir)
    val unitTests = collectTests(unitEntries, [])
    val stdlibTests = collectTests(stdlibEntries, [])
    Lst.append(unitTests, stdlibTests)
  } else 
    resolvePaths(rootDir, filterToTestFiles(pathArgs))

val testCount = Lst.length(tests)

val impLines = buildImports(tests, 0)
val calls = buildCalls(testCount, 0)

val genHead =
  "import { printSummary, outputCompact, outputVerbose, outputSummary } from \"kestrel:test\"\n";
val genMid =
  "\nval counts = { mut passed = 0, mut failed = 0, mut startTime = __now_ms(), mut compactStackBox = { frames = [] }, mut compactExpanded = False }\nval root = { depth = 1, output = ";
val genRest = ", counts = counts }\n\n";
val genTail = "printSummary(counts)\n";
val generatedSource =
  "${genHead}${impLines}${genMid}${outputModeStr}${genRest}${calls}${genTail}"

val generatedPath = "${rootDir}/.kestrel_test_runner.ks"
writeText(generatedPath, generatedSource)

val exitCode = runProcess("./scripts/kestrel", ["run", generatedPath])
exit(exitCode)
