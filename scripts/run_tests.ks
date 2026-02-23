import { getProcess, runProcess } from "kestrel:process"
import { listDir, writeText } from "kestrel:fs"

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

val testDir = "${cwd}/tests/unit"
val entries = listDir(testDir)
val tests = collectTests(entries, [])
val testCount = listLength(tests)
val summaryOnly = checkSummaryFlag(proc.args)

val imports = buildImports(tests, 0)
val calls = buildCalls(testCount, 0)

val summaryVal = if (summaryOnly) "True" else "False"

val generatedSource = "import { printSummary } from \"kestrel:test\"\n${imports}\nval counts = { mut passed = 0, mut failed = 0 }\nval root = { depth = 1, summaryOnly = ${summaryVal}, counts = counts }\n\n${calls}\nprintSummary(counts)\n"

val generatedPath = "/tmp/kestrel_test_runner.ks"
writeText(generatedPath, generatedSource)

val exitCode = runProcess("./scripts/kestrel", ["run", generatedPath])
exit(exitCode)
