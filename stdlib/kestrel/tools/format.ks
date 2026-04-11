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
import { GREEN, RED, DIM, RESET, CHECK, CROSS, terminalInfo } from "kestrel:io/console"
import { nowMs } from "kestrel:data/basics"

val _isTty = terminalInfo().isTty
val _grn = if (_isTty) GREEN else ""
val _red = if (_isTty) RED else ""
val _dim = if (_isTty) DIM else ""
val _rst = if (_isTty) RESET else ""

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
            if (!summaryMode) println("${_dim}───${_rst}") else ();
            if (bad > 0)
              println("${_grn}${passCount} ${CHECK}${_rst}  ${_red}${bad} ${CROSS}${_rst}  ${_dim}(${elapsed}ms)${_rst}")
            else
              println("${_grn}${passCount} ${CHECK}${_rst}  ${_dim}(${elapsed}ms)${_rst}");
            if (anyFail) 1 else 0
          }
          path :: rest => {
            val t0 = nowMs()
            val result = await checkFile(path)
            val elapsed = nowMs() - t0
            match (result) {
              Err(e) => {
                if (!summaryMode) println("${_red}${CROSS}${_rst} ${path} ${_dim}(${elapsed}ms)${_rst} — error: ${fmtError(e)}") else ();
                await checkAll(rest, True, passCount, failCount, errorCount + 1)
              }
              Ok(alreadyFmt) =>
                if (alreadyFmt) {
                  if (!summaryMode) println("${_grn}${CHECK}${_rst} ${path} ${_dim}(${elapsed}ms)${_rst}") else ();
                  await checkAll(rest, anyFail, passCount + 1, failCount, errorCount)
                } else {
                  if (!summaryMode) println("${_red}${CROSS}${_rst} ${path} ${_dim}(${elapsed}ms)${_rst} — not formatted") else ();
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
            if (!summaryMode) println("${_dim}───${_rst}") else ();
            if (failCount > 0)
              println("${_grn}${passCount} ${CHECK}${_rst}  ${_red}${failCount} ${CROSS}${_rst}  ${_dim}(${elapsed}ms)${_rst}")
            else
              println("${_grn}${passCount} ${CHECK}${_rst}  ${_dim}(${elapsed}ms)${_rst}");
            if (anyFail) 1 else 0
          }
          path :: rest => {
            val t0 = nowMs()
            val result = await formatFile(path)
            val elapsed = nowMs() - t0
            match (result) {
              Err(e) => {
                if (!summaryMode) println("${_red}${CROSS}${_rst} ${path} ${_dim}(${elapsed}ms)${_rst} — error: ${fmtError(e)}") else ();
                await formatAll(rest, True, passCount, failCount + 1)
              }
              Ok(_) => {
                if (!summaryMode) println("${_grn}${CHECK}${_rst} ${path} ${_dim}(${elapsed}ms)${_rst}") else ();
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
