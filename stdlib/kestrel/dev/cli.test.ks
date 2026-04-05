import { Suite, group, eq, isTrue, isFalse } from "kestrel:test"
import * as Cli from "kestrel:dev/cli"
import * as Dict from "kestrel:data/dict"
import * as Opt from "kestrel:data/option"
import * as Res from "kestrel:data/result"
import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"

val verboseOpt = {
  short = Some("-v"),
  long = "--verbose",
  kind = Cli.Flag,
  description = "Be verbose"
}

val outputOpt = {
  short = Some("-o"),
  long = "--output",
  kind = Cli.Value("FILE"),
  description = "Output file"
}

val countOpt = {
  short = None,
  long = "--count",
  kind = Cli.Value("N"),
  description = "Count value"
}

val fileArg = {
  name = "file",
  description = "Input file",
  variadic = False
}

val filesArg = {
  name = "files",
  description = "Input files",
  variadic = True
}

val testSpec = {
  name = "mytool",
  version = "1.2.3",
  description = "A handy tool",
  usage = "mytool [options] <file>",
  options = [verboseOpt, outputOpt, countOpt],
  args = [fileArg]
}

fun parseOk(argv: List<String>): Cli.ParsedArgs =
  match (Cli.parse(testSpec, argv)) {
    Ok(p) => p
    Err(_) => { options = Dict.emptyStringDict(), positional = [] }
  }

fun parseErr(argv: List<String>): Bool =
  Res.isErr(Cli.parse(testSpec, argv))

export async fun run(s: Suite): Task<Unit> =
  group(s, "cli", (s1: Suite) => {
    group(s1, "version", (sg: Suite) => {
      eq(sg, "version string", Cli.version(testSpec), "mytool v1.2.3")
    });

    group(s1, "parse flags", (sg: Suite) => {
      val p = parseOk(["--verbose"])
      eq(sg, "flag true", Opt.getOrElse(Dict.get(p.options, "verbose"), ""), "true");
      eq(sg, "no positional", Lst.length(p.positional), 0)
    });

    group(s1, "parse short flag", (sg: Suite) => {
      val p = parseOk(["-v"])
      eq(sg, "short flag true", Opt.getOrElse(Dict.get(p.options, "verbose"), ""), "true")
    });

    group(s1, "parse value option", (sg: Suite) => {
      val p = parseOk(["--output", "out.txt"])
      eq(sg, "value stored", Opt.getOrElse(Dict.get(p.options, "output"), ""), "out.txt")
    });

    group(s1, "parse --key=value", (sg: Suite) => {
      val p = parseOk(["--output=result.txt"])
      eq(sg, "eq-form value", Opt.getOrElse(Dict.get(p.options, "output"), ""), "result.txt")
    });

    group(s1, "parse short value", (sg: Suite) => {
      val p = parseOk(["-o", "out.txt"])
      eq(sg, "short value", Opt.getOrElse(Dict.get(p.options, "output"), ""), "out.txt")
    });

    group(s1, "parse short inline value", (sg: Suite) => {
      val p = parseOk(["-oout.txt"])
      eq(sg, "inline value", Opt.getOrElse(Dict.get(p.options, "output"), ""), "out.txt")
    });

    group(s1, "parse positional", (sg: Suite) => {
      val p = parseOk(["foo.txt"])
      eq(sg, "positional[0]", Opt.getOrElse(Lst.head(p.positional), ""), "foo.txt");
      eq(sg, "positional count", Lst.length(p.positional), 1)
    });

    group(s1, "parse mixed", (sg: Suite) => {
      val p = parseOk(["--verbose", "--output", "out.txt", "foo.txt"])
      eq(sg, "flag set", Opt.getOrElse(Dict.get(p.options, "verbose"), ""), "true");
      eq(sg, "value set", Opt.getOrElse(Dict.get(p.options, "output"), ""), "out.txt");
      eq(sg, "positional", Opt.getOrElse(Lst.head(p.positional), ""), "foo.txt")
    });

    group(s1, "parse -- separator", (sg: Suite) => {
      val p = parseOk(["--", "--not-an-option"])
      eq(sg, "after -- is positional", Opt.getOrElse(Lst.head(p.positional), ""), "--not-an-option")
    });

    group(s1, "parse unknown option", (sg: Suite) => {
      isTrue(sg, "unknown long", parseErr(["--unknown"]))
    });

    group(s1, "parse missing value", (sg: Suite) => {
      isTrue(sg, "missing value", parseErr(["--output"]))
    });

    group(s1, "parse flag with =value is error", (sg: Suite) => {
      isTrue(sg, "flag cannot take =value", parseErr(["--verbose=yes"]))
    });

    group(s1, "help contains name and description", (sg: Suite) => {
      val h = Cli.help(testSpec)
      isTrue(sg, "contains name", Str.contains("mytool", h));
      isTrue(sg, "contains version", Str.contains("1.2.3", h));
      isTrue(sg, "contains description", Str.contains("A handy tool", h));
      isTrue(sg, "contains --help", Str.contains("--help", h));
      isTrue(sg, "contains --version", Str.contains("--version", h));
      isTrue(sg, "contains --verbose", Str.contains("--verbose", h));
      isTrue(sg, "contains --output", Str.contains("--output", h));
      isTrue(sg, "contains Options:", Str.contains("Options:", h));
      isTrue(sg, "contains Usage:", Str.contains("Usage:", h))
    });

    group(s1, "help args section", (sg: Suite) => {
      val specWithArg: Cli.CliSpec = {
        name = "t", version = "1", description = "d", usage = "t <files...>",
        options = [],
        args = [filesArg]
      }
      val h = Cli.help(specWithArg)
      isTrue(sg, "contains Arguments:", Str.contains("Arguments:", h));
      isTrue(sg, "variadic notation", Str.contains("files...", h))
    });

    group(s1, "help no args section when empty", (sg: Suite) => {
      val specNoArgs: Cli.CliSpec = {
        name = "t", version = "1", description = "d", usage = "t",
        options = [],
        args = []
      }
      val h = Cli.help(specNoArgs)
      isFalse(sg, "no Arguments: when empty", Str.contains("Arguments:", h))
    })
  })
