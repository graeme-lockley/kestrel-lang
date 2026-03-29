import { getProcess, runProcess } from "kestrel:process"
import { listDir, writeText } from "kestrel:fs"
import { drop } from "kestrel:list"
import { fromInt } from "kestrel:string"

val proc = getProcess()
val cwd = proc.cwd

fun getRootDir(args: List<String>, fallback: String): String =
  match (drop(2, args)) {
    [] => fallback,
    hd :: _ => hd
  }
val rootDir = getRootDir(proc.args, cwd)

fun hasSuffix(s: String, suffix: String): Bool = {
  val sLen = __string_length(s);
  val suffLen = __string_length(suffix);
  if (sLen < suffLen) False
  else __string_equals(__string_slice(s, sLen - suffLen, sLen), suffix)
}

fun collectTests(entries: List<String>, acc: List<String>): List<String> =
  match (entries) {
    [] => acc,
    hd :: tl => {
      val tabIdx = __string_index_of(hd, "\t");
      val path = __string_slice(hd, 0, tabIdx);
      val kind = __string_slice(hd, tabIdx + 1, __string_length(hd));
      if (__string_equals(kind, "dir")) {
        val subEntries = listDir(path);
        val subAcc = collectTests(subEntries, acc);
        collectTests(tl, subAcc)
      }
      else if (hasSuffix(path, ".test.ks")) collectTests(tl, path :: acc)
      else collectTests(tl, acc)
    }
  }

fun checkSummaryFlag(args: List<String>): Bool =
  match (args) {
    [] => False,
    hd :: tl => if (__string_equals(hd, "--summary")) True else checkSummaryFlag(tl)
  }

fun excludeFlag(args: List<String>): List<String> =
  match (args) {
    [] => [],
    hd :: tl => if (__string_equals(hd, "--summary")) excludeFlag(tl) else hd :: excludeFlag(tl)
  }

// argv layout must match VM: [vm binary, .kbc path, project root, ...paths]. JVM entry pads with "" "".
fun getPathArgs(allArgs: List<String>): List<String> = excludeFlag(drop(3, allArgs))

fun filterToTestFiles(paths: List<String>): List<String> =
  match (paths) {
    [] => [],
    hd :: tl => if (hasSuffix(hd, ".test.ks")) hd :: filterToTestFiles(tl) else filterToTestFiles(tl)
  }

fun isAbsolute(path: String): Bool =
  if (__string_length(path) > 0) __string_equals(__string_slice(path, 0, 1), "/") else False

fun resolvePath(base: String, path: String): String =
  if (isAbsolute(path)) path else "${base}/${path}"

fun resolvePaths(base: String, paths: List<String>): List<String> =
  match (paths) {
    [] => [],
    hd :: tl => resolvePath(base, hd) :: resolvePaths(base, tl)
  }

fun buildImports(tests: List<String>, idx: Int): String =
  match (tests) {
    [] => "",
    hd :: tl => {
      val alias = __string_concat("run", fromInt(idx));
      val line = __string_concat(
        __string_concat(__string_concat(__string_concat("import { run as ", alias), " } from \""), hd),
        "\"\n"
      );
      val rest = buildImports(tl, idx + 1);
      __string_concat(line, rest)
    }
  }

fun buildCalls(count: Int, idx: Int): String =
  if (idx >= count) ""
  else {
    val line = __string_concat(__string_concat(__string_concat("run", fromInt(idx)), "(root)"), "\n");
    val rest = buildCalls(count, idx + 1);
    __string_concat(line, rest)
  }

fun listLength(lst: List<String>): Int =
  match (lst) {
    [] => 0,
    _ :: tl => 1 + listLength(tl)
  }

fun append(a: List<String>, b: List<String>): List<String> =
  match (a) {
    [] => b,
    h :: t => h :: append(t, b)
  }

val unitDir = "${rootDir}/tests/unit"
val stdlibDir = "${rootDir}/stdlib/kestrel"
val pathArgs = getPathArgs(proc.args)
val summaryOnly = checkSummaryFlag(proc.args)
val tests = if (listLength(pathArgs) == 0) {
  val unitEntries = listDir(unitDir)
  val stdlibEntries = listDir(stdlibDir)
  val unitTests = collectTests(unitEntries, [])
  val stdlibTests = collectTests(stdlibEntries, [])
  append(unitTests, stdlibTests)
} else resolvePaths(rootDir, filterToTestFiles(pathArgs))
val testCount = listLength(tests)

val impLines = buildImports(tests, 0)
val calls = buildCalls(testCount, 0)

val summaryVal = if (summaryOnly) "True" else "False"

val genHead = "import { printSummary } from \"kestrel:test\"\n";
val genMid =
  "\nval counts = { mut passed = 0, mut failed = 0, mut startTime = __now_ms() }\nval root = { depth = 1, summaryOnly = ";
val genRest = ", counts = counts }\n\n";
val genTail = "printSummary(counts)\n";
val generatedSource = __string_concat(
  __string_concat(__string_concat(__string_concat(__string_concat(genHead, impLines), genMid), summaryVal), genRest),
  __string_concat(calls, genTail)
)

val generatedPath = "${rootDir}/.kestrel_test_runner.ks"
writeText(generatedPath, generatedSource)

val exitCode = runProcess("./scripts/kestrel", ["run", generatedPath])
exit(exitCode)
