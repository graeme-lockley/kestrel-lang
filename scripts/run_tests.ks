import { getProcess, runProcess } from "kestrel:process"
import { listDir, writeText } from "kestrel:fs"
import { drop } from "kestrel:list"

val proc = getProcess()
val cwd = proc.cwd

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

fun getPathArgs(allArgs: List<String>): List<String> = excludeFlag(drop(2, allArgs))

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
      val line = "import { run as run${idx} } from \"${hd}\"\n";
      val rest = buildImports(tl, idx + 1);
      "${line}${rest}"
    }
  }

fun buildCalls(count: Int, idx: Int): String =
  if (idx >= count) ""
  else {
    val line = "run${idx}(root)\n";
    val rest = buildCalls(count, idx + 1);
    "${line}${rest}"
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

val unitDir = "${cwd}/tests/unit"
val stdlibDir = "${cwd}/stdlib/kestrel"
val pathArgs = getPathArgs(proc.args)
val summaryOnly = checkSummaryFlag(proc.args)
val tests = if (listLength(pathArgs) == 0) {
  val unitEntries = listDir(unitDir)
  val stdlibEntries = listDir(stdlibDir)
  val unitTests = collectTests(unitEntries, [])
  val stdlibTests = collectTests(stdlibEntries, [])
  append(unitTests, stdlibTests)
} else resolvePaths(proc.cwd, filterToTestFiles(pathArgs))
val testCount = listLength(tests)

val imports = buildImports(tests, 0)
val calls = buildCalls(testCount, 0)

val summaryVal = if (summaryOnly) "True" else "False"

val generatedSource = "import { printSummary } from \"kestrel:test\"\n${imports}\nval counts = { mut passed = 0, mut failed = 0 }\nval root = { depth = 1, summaryOnly = ${summaryVal}, counts = counts }\n\n${calls}\nprintSummary(counts)\n"

val generatedPath = "/tmp/kestrel_test_runner.ks"
writeText(generatedPath, generatedSource)

val exitCode = runProcess("./scripts/kestrel", ["run", generatedPath])
exit(exitCode)
