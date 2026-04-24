//! Declarative CLI argument parser used by Kestrel tools.
//!
//! Define a `CliSpec`, then parse argv with `parse` to obtain options and
//! positional arguments as a structured `ParsedArgs` value.
//!
//! ## Quick Start
//!
//! ```kestrel
//! import * as Cli from "kestrel:dev/cli"
//! import { CliSpec, Flag, Value } from "kestrel:dev/cli"
//!
//! val spec: CliSpec = {
//!   name = "my-tool",
//!   version = "0.1.0",
//!   description = "Example",
//!   usage = "my-tool [--port PORT]",
//!   options = [{ short = None, long = "--port", kind = Value("PORT"), description = "Port" }],
//!   args = []
//! }
//! val parsed = Cli.parse(spec, ["--port", "8080"])
//! ```
import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"
import * as Dict from "kestrel:data/dict"

// ─── Types ────────────────────────────────────────────────────────────────────

/** Whether a CLI option takes a value.
 *  Flag  — boolean presence flag; ParsedArgs.options gets "true".
 *  Value — consumes the next token; the String is the help metavar, e.g. "FILE". */
export type CliOptionKind = Flag | Value(String)

/** A named option, e.g. { short = Some("-o"), long = "--output", kind = Value("FILE"), description = "..." } */
export type CliOption = {
  short: Option<String>,
  long: String,
  kind: CliOptionKind,
  description: String
}

/** A positional argument descriptor. */
export type CliArg = {
  name: String,
  description: String,
  variadic: Bool
}

/** Full description of a CLI tool. */
export type CliSpec = {
  name: String,
  version: String,
  description: String,
  usage: String,
  options: List<CliOption>,
  args: List<CliArg>
}

/** Result of a successful parse.
 *  options   — bare long names (no leading --) mapped to their values.
 *  positional — non-option arguments in order. */
export type ParsedArgs = {
  options: Dict<String, String>,
  positional: List<String>
}

/** Errors produced by parse. */
export type CliError =
    UnknownOption(String)
  | MissingValue(String)
  | MissingArg(String)
  | UnexpectedArg(String)

// ─── Internal helpers ─────────────────────────────────────────────────────────

fun longKey(long: String): String = Str.dropLeft(long, 2)

fun findByLong(opts: List<CliOption>, name: String): Option<CliOption> = match (opts) {
  [] => None
  h :: t => if (Str.equals(h.long, name)) Some(h) else findByLong(t, name)
}

fun findByShort(opts: List<CliOption>, name: String): Option<CliOption> = match (opts) {
  [] => None
  h :: t =>
    match (h.short) {
      None => findByShort(t, name)
      Some(s) => if (Str.equals(s, name)) Some(h) else findByShort(t, name)
    }
}

fun parseLoop(
  specOpts: List<CliOption>,
  args: List<String>,
  opts: Dict<String, String>,
  pos: List<String>
): Result<ParsedArgs, CliError> =
  match (args) {
    [] => Ok({ options = opts, positional = Lst.reverse(pos) })
    arg :: rest =>
      if (Str.equals(arg, "--"))
        Ok({ options = opts, positional = Lst.append(Lst.reverse(pos), rest) })
      else if (Str.startsWith("--", arg)) {
        val bare = Str.dropLeft(arg, 2)
        val eqIdx = Str.indexOf(bare, "=")
        if (eqIdx >= 0) {
          val longName = Str.slice(bare, 0, eqIdx)
          val value = Str.slice(bare, eqIdx + 1, Str.length(bare))
          match (findByLong(specOpts, "--${longName}")) {
            None => Err(UnknownOption("--${longName}"))
            Some(opt) =>
              match (opt.kind) {
                Flag => Err(UnexpectedArg("--${longName}"))
                Value(_) => parseLoop(specOpts, rest, Dict.insert(opts, longName, value), pos)
              }
          }
        } else {
          match (findByLong(specOpts, "--${bare}")) {
            None => Err(UnknownOption("--${bare}"))
            Some(opt) =>
              match (opt.kind) {
                Flag => parseLoop(specOpts, rest, Dict.insert(opts, bare, "true"), pos)
                Value(_) =>
                  match (rest) {
                    [] => Err(MissingValue("--${bare}"))
                    next :: after =>
                      parseLoop(specOpts, after, Dict.insert(opts, bare, next), pos)
                  }
              }
          }
        }
      } else if (Str.startsWith("-", arg) & Str.length(arg) >= 2) {
        val shortName = Str.left(arg, 2)
        match (findByShort(specOpts, shortName)) {
          None => Err(UnknownOption(shortName))
          Some(opt) => {
            val key = longKey(opt.long)
            match (opt.kind) {
              Flag => parseLoop(specOpts, rest, Dict.insert(opts, key, "true"), pos)
              Value(_) => {
                val inline = Str.dropLeft(arg, 2)
                if (Str.length(inline) > 0)
                  parseLoop(specOpts, rest, Dict.insert(opts, key, inline), pos)
                else
                  match (rest) {
                    [] => Err(MissingValue(shortName))
                    next :: after =>
                      parseLoop(specOpts, after, Dict.insert(opts, key, next), pos)
                  }
              }
            }
          }
        }
      } else
        parseLoop(specOpts, rest, opts, arg :: pos)
  }

fun optLeftCol(opt: CliOption): String = {
  val shortPart =
    match (opt.short) {
      None => "    "
      Some(s) => "${s}, "
    }
  val metaPart =
    match (opt.kind) {
      Flag => ""
      Value(meta) => " <${meta}>"
    }
  "${shortPart}${opt.long}${metaPart}"
}

fun colMax(strs: List<String>): Int =
  Lst.foldl(strs, 0, (acc: Int, s: String) =>
    if (Str.length(s) > acc) Str.length(s) else acc
  )

fun formatOptLines(opts: List<CliOption>): String = {
  val leftCols = Lst.map(opts, optLeftCol)
  val colWidth = colMax(leftCols)
  Str.join("\n", Lst.map2(leftCols, opts, (left: String, opt: CliOption) =>
    "  ${Str.padRight(colWidth, " ", left)}  ${opt.description}"
  ))
}

fun formatArgLine(arg: CliArg): String = {
  val variad = if (arg.variadic) "..." else ""
  "  ${arg.name}${variad}  ${arg.description}"
}

fun fmtError(e: CliError): String =
  match (e) {
    UnknownOption(n) => "unknown option: ${n}; run with --help for usage"
    MissingValue(n)  => "option ${n} requires a value"
    MissingArg(n)    => "missing required argument: ${n}"
    UnexpectedArg(n) => "unexpected value for flag option: ${n}"
  }

val builtHelpOpt = {
  short = Some("-h"),
  long = "--help",
  kind = Flag,
  description = "Show this help message and exit"
}

val builtVersionOpt = {
  short = Some("-V"),
  long = "--version",
  kind = Flag,
  description = "Show version and exit"
}

val builtins = [builtHelpOpt, builtVersionOpt]

// ─── Public API ───────────────────────────────────────────────────────────────

/** Parse argv (without program name) against the spec.
 *  --help and --version are NOT intercepted here; use run for that. */
export fun parse(spec: CliSpec, argv: List<String>): Result<ParsedArgs, CliError> =
  parseLoop(spec.options, argv, Dict.emptyStringDict(), [])

/** Render formatted help text for a spec. */
export fun help(spec: CliSpec): String = {
  val header = "${spec.name} ${spec.version} — ${spec.description}"
  val usageLine = "Usage:\n  ${spec.usage}"
  val allOpts = Lst.append(builtins, spec.options)
  val optsSection = "Options:\n${formatOptLines(allOpts)}"
  val argLines = Lst.map(spec.args, formatArgLine)
  val argsSection =
    if (Lst.isEmpty(argLines)) ""
    else "Arguments:\n${Str.join("\n", argLines)}"
  val nonEmpty = Lst.filter(
    [header, "", usageLine, "", optsSection, "", argsSection],
    (s: String) => !Str.isEmpty(s)
  )
  Str.join("\n", nonEmpty)
}

/** Render a short version string: "name vX.Y.Z". */
export fun version(spec: CliSpec): String = "${spec.name} v${spec.version}"

/** Run a CLI tool: intercept --help / --version, then parse argv and call handler.
 *  The handler receives the parsed args and returns an exit code. */
export async fun run(
  spec: CliSpec,
  handler: (ParsedArgs) -> Task<Int>,
  argv: List<String>
): Task<Int> =
  if (Lst.any(argv, (a: String) => Str.equals(a, "--help") | Str.equals(a, "-h"))) {
    println(help(spec));
    0
  } else if (Lst.any(argv, (a: String) => Str.equals(a, "--version") | Str.equals(a, "-V"))) {
    println(version(spec));
    0
  } else
    match (parse(spec, argv)) {
      Err(e) => {
        println(fmtError(e));
        1
      }
      Ok(parsed) => await handler(parsed)
    }
