// kestrel:tools/test — discover and run Kestrel unit tests.
// Usage: kestrel test [--verbose|--summary] [--generate] [--clean] [--refresh] [--allow-http] [files...]

import * as Lst from "kestrel:data/list"
import * as Opt from "kestrel:data/option"
import * as Dict from "kestrel:data/dict"
import * as Cli from "kestrel:dev/cli"
import { CliSpec, ParsedArgs, Flag } from "kestrel:dev/cli"
import * as Discovery from "kestrel:tools/test/discovery"
import * as Runner from "kestrel:tools/test/runner"
import { getProcess, getEnv } from "kestrel:sys/process"

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

// ─── Handler ──────────────────────────────────────────────────────────────────

/** Entry point for `kestrel:tools/test` (invoked via `./kestrel run kestrel:tools/test`).
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
    if (Lst.isEmpty(parsed.positional))
      await Discovery.discoverTests(unitDir, stdlibDir)
    else
      Discovery.resolvePaths(rootDir, Discovery.filterToTestFiles(parsed.positional))

  val generatedPath = "${rootDir}/.kestrel_test_runner.ks"
  val source = Runner.buildSource(tests, outputModeStr)
  await Runner.writeRunnerIfChanged(generatedPath, source)

  match (Dict.get(parsed.options, "generate")) {
    Some(_) => 0
    None => {
      val compilerFlags = Runner.buildCompilerFlags(parsed)
      val innerArgs = Lst.append(["run"], Lst.append(compilerFlags, [generatedPath]))
      await Runner.runProcessStreamOrExit(kestrelBin, innerArgs)
    }
  }
}

// ─── Entry point ─────────────────────────────────────────────────────────────

export async fun main(allArgs: List<String>): Task<Unit> = {
  val code = await Cli.run(cliSpec, handler, allArgs)
  exit(code)
}

main(getProcess().args)
