// kestrel:tools/format — opinionated Kestrel source code formatter.
// Usage: kestrel fmt [--check] [--stdin] [files-or-dirs...]

import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"
import * as Dict from "kestrel:data/dict"
import { readStdin, collectFiles, pathBaseName } from "kestrel:io/fs"
import { all } from "kestrel:sys/task"
import * as Cli from "kestrel:dev/cli"
import { CliSpec, ParsedArgs, Flag } from "kestrel:dev/cli"
import {
  FormatError, FmtParseError, FmtIoError,
  format, formatFile, checkFile
} from "kestrel:tools/format/formatter"
import { getProcess } from "kestrel:sys/process"
import { GREEN, RED, DIM, RESET, CHECK, CROSS } from "kestrel:io/console"
import { nowMs } from "kestrel:data/basics"

// ─── File resolution ─────────────────────────────────────────────────────────

fun isKsFile(path: String): Bool =
  Str.endsWith(".ks", path)

fun isIgnoreDir(path: String): Bool = {
  val base = pathBaseName(path)
  Str.startsWith(".", base) | Str.equals(base, "node_modules")
}

async fun resolveInput(path: String): Task<List<String>> =
  if (isKsFile(path)) [path]
  else await collectFiles(path, isKsFile, isIgnoreDir)

async fun resolveInputs(paths: List<String>): Task<List<String>> = {
  val lists = await all(Lst.map(paths, (p: String) => resolveInput(p)))
  Lst.concat(lists)
}

// ─── CLI spec ────────────────────────────────────────────────────────────────

val cliSpec = {
  name = "kestrel fmt",
  version = "0.1.0",
  description = "Opinionated Kestrel source code formatter",
  usage = "kestrel fmt [--check] [--stdin] [--summary] [files-or-dirs...]",
  options = [
    {
      short = Some("-c"),
      long = "--check",
      kind = Flag,
      description = "Check if files are formatted; exit 1 if not"
    },
    {
      short = None,
      long = "--stdin",
      kind = Flag,
      description = "Read from stdin, write formatted output to stdout"
    },
    {
      short = Some("-s"),
      long = "--summary",
      kind = Flag,
      description = "Print only the summary line; suppress per-file output"
    }
  ],
  args = [
    {
      name = "files",
      description = "Kestrel source files or directories to format (default: current directory)",
      variadic = True
    }
  ]
}

// ─── CLI handler ─────────────────────────────────────────────────────────────

fun fmtError(e: FormatError): String =
  match (e) {
    FmtParseError(msg, _, ln, col) => "parse error at ${ln}:${col}: ${msg}"
    FmtIoError(msg) => "io error: ${msg}"
  }

fun flagSet(parsed: ParsedArgs, name: String): Bool =
  match (Dict.get(parsed.options, name)) {
    Some(_) => True
    None => False
  }

async fun handler(parsed: ParsedArgs): Task<Int> = {
  val useStdin = flagSet(parsed, "stdin")
  val checkMode = flagSet(parsed, "check")
  val summaryMode = flagSet(parsed, "summary")
  if (useStdin) {
    val src = await readStdin()
    match (format(src)) {
      Err(e) => {
        println(fmtError(e));
        1
      }
      Ok(formatted) => {
        print(formatted);
        0
      }
    }
  } else {
    val proc = getProcess()
    val targets =
      if (Lst.isEmpty(parsed.positional))
        await resolveInputs([proc.cwd])
      else
        await resolveInputs(parsed.positional)
    val startMs = nowMs()
    if (checkMode) {
      async fun checkAll(files: List<String>, anyFail: Bool, passCount: Int, failCount: Int, errorCount: Int): Task<Int> =
        match (files) {
          [] => {
            val elapsed = nowMs() - startMs
            val bad = failCount + errorCount
            if (!summaryMode) println("${DIM}───${RESET}") else ();
            if (bad > 0)
              println("${GREEN}${passCount} ${CHECK}${RESET}  ${RED}${bad} ${CROSS}${RESET}  ${DIM}(${elapsed}ms)${RESET}")
            else
              println("${GREEN}${passCount} ${CHECK}${RESET}  ${DIM}(${elapsed}ms)${RESET}");
            if (anyFail) 1 else 0
          }
          path :: rest => {
            val t0 = nowMs()
            val result = await checkFile(path)
            val elapsed = nowMs() - t0
            match (result) {
              Err(e) => {
                if (!summaryMode) println("${RED}${CROSS}${RESET} ${path} ${DIM}(${elapsed}ms)${RESET} — error: ${fmtError(e)}") else ();
                await checkAll(rest, True, passCount, failCount, errorCount + 1)
              }
              Ok(alreadyFmt) =>
                if (alreadyFmt) {
                  if (!summaryMode) println("${GREEN}${CHECK}${RESET} ${path} ${DIM}(${elapsed}ms)${RESET}") else ();
                  await checkAll(rest, anyFail, passCount + 1, failCount, errorCount)
                } else {
                  if (!summaryMode) println("${RED}${CROSS}${RESET} ${path} ${DIM}(${elapsed}ms)${RESET} — not formatted") else ();
                  await checkAll(rest, True, passCount, failCount + 1, errorCount)
                }
            }
          }
        }
      await checkAll(targets, False, 0, 0, 0)
    } else {
      async fun formatAll(files: List<String>, anyFail: Bool, passCount: Int, failCount: Int): Task<Int> =
        match (files) {
          [] => {
            val elapsed = nowMs() - startMs
            if (!summaryMode) println("${DIM}───${RESET}") else ();
            if (failCount > 0)
              println("${GREEN}${passCount} ${CHECK}${RESET}  ${RED}${failCount} ${CROSS}${RESET}  ${DIM}(${elapsed}ms)${RESET}")
            else
              println("${GREEN}${passCount} ${CHECK}${RESET}  ${DIM}(${elapsed}ms)${RESET}");
            if (anyFail) 1 else 0
          }
          path :: rest => {
            val t0 = nowMs()
            val result = await formatFile(path)
            val elapsed = nowMs() - t0
            match (result) {
              Err(e) => {
                if (!summaryMode) println("${RED}${CROSS}${RESET} ${path} ${DIM}(${elapsed}ms)${RESET} — error: ${fmtError(e)}") else ();
                await formatAll(rest, True, passCount, failCount + 1)
              }
              Ok(_) => {
                if (!summaryMode) println("${GREEN}${CHECK}${RESET} ${path} ${DIM}(${elapsed}ms)${RESET}") else ();
                await formatAll(rest, anyFail, passCount + 1, failCount)
              }
            }
          }
        }
      await formatAll(targets, False, 0, 0)
    }
  }
}

// ─── Entry point ─────────────────────────────────────────────────────────────

export async fun main(allArgs: List<String>): Task<Unit> = {
  val code = await Cli.run(cliSpec, handler, allArgs)
  exit(code)
}

main(getProcess().args)
