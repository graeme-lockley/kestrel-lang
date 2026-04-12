//! Declaration signature pretty-printer for Kestrel doc entries.
//! Takes a `DocEntry` (from `kestrel:dev/doc/extract`) and returns a
//! normalised, human-readable signature string suitable for display in the
//! documentation browser.
import * as Lst from "kestrel:data/list"
import * as Opt from "kestrel:data/option"
import * as Str from "kestrel:data/string"
import { DocEntry, DKFun, DKType, DKExternFun } from "kestrel:dev/doc/extract"

export type FormatOptions = {
  multilineFunctions: Bool
}

fun isFunctionLike(entry: DocEntry): Bool =
  entry.kind == DKFun | entry.kind == DKExternFun

fun splitTopLevelParamsLoop(s: String, i: Int, start: Int, parenDepth: Int, bracketDepth: Int, braceDepth: Int, angleDepth: Int, revParts: List<String>): List<String> =
  if (i >= Str.length(s)) Str.trim(Str.slice(s, start, i)) :: revParts
  else {
    val ch = Str.codePointAt(s, i);
    if (ch == 40) splitTopLevelParamsLoop(s, i + 1, start, parenDepth + 1, bracketDepth, braceDepth, angleDepth, revParts)
    else if (ch == 41) splitTopLevelParamsLoop(s, i + 1, start, parenDepth - 1, bracketDepth, braceDepth, angleDepth, revParts)
    else if (ch == 91) splitTopLevelParamsLoop(s, i + 1, start, parenDepth, bracketDepth + 1, braceDepth, angleDepth, revParts)
    else if (ch == 93) splitTopLevelParamsLoop(s, i + 1, start, parenDepth, bracketDepth - 1, braceDepth, angleDepth, revParts)
    else if (ch == 123) splitTopLevelParamsLoop(s, i + 1, start, parenDepth, bracketDepth, braceDepth + 1, angleDepth, revParts)
    else if (ch == 125) splitTopLevelParamsLoop(s, i + 1, start, parenDepth, bracketDepth, braceDepth - 1, angleDepth, revParts)
    else if (ch == 60) splitTopLevelParamsLoop(s, i + 1, start, parenDepth, bracketDepth, braceDepth, angleDepth + 1, revParts)
    else if (ch == 62) splitTopLevelParamsLoop(s, i + 1, start, parenDepth, bracketDepth, braceDepth, angleDepth - 1, revParts)
    else if (ch == 44 & parenDepth == 0 & bracketDepth == 0 & braceDepth == 0 & angleDepth == 0)
      splitTopLevelParamsLoop(s, i + 1, i + 1, parenDepth, bracketDepth, braceDepth, angleDepth, Str.trim(Str.slice(s, start, i)) :: revParts)
    else splitTopLevelParamsLoop(s, i + 1, start, parenDepth, bracketDepth, braceDepth, angleDepth, revParts)
  }

fun splitTopLevelParams(s: String): List<String> =
  if (Str.isEmpty(Str.trim(s))) []
  else Lst.reverse(splitTopLevelParamsLoop(s, 0, 0, 0, 0, 0, 0, []))

fun findParenClose(sig: String, i: Int, parenDepth: Int): Int =
  if (i >= Str.length(sig)) -1
  else {
    val ch = Str.codePointAt(sig, i);
    if (ch == 40) findParenClose(sig, i + 1, parenDepth + 1)
    else if (ch == 41) {
      val nextDepth = parenDepth - 1;
      if (nextDepth == 0) i else findParenClose(sig, i + 1, nextDepth)
    }
    else findParenClose(sig, i + 1, parenDepth)
  }

fun multilineFunction(sig: String): String = {
  val open = Str.indexOf(sig, "(");
  if (open < 0) sig
  else {
    val close = findParenClose(sig, open + 1, 1);
    if (close < 0) sig
    else {
      val params = splitTopLevelParams(Str.slice(sig, open + 1, close));
      if (Lst.isEmpty(params)) sig
      else {
        val head = Str.slice(sig, 0, open + 1);
        val tail = Str.slice(sig, close, Str.length(sig));
        val body = Str.join(",\n", Lst.map(params, (p: String) => "  ${p}"));
        "${head}\n${body}\n${tail}"
      }
    }
  }
}

fun splitTopLevelByPipeLoop(s: String, i: Int, start: Int, parenDepth: Int, bracketDepth: Int, braceDepth: Int, angleDepth: Int, revParts: List<String>): List<String> =
  if (i >= Str.length(s)) Str.trim(Str.slice(s, start, i)) :: revParts
  else {
    val ch = Str.codePointAt(s, i);
    if (ch == 40) splitTopLevelByPipeLoop(s, i + 1, start, parenDepth + 1, bracketDepth, braceDepth, angleDepth, revParts)
    else if (ch == 41) splitTopLevelByPipeLoop(s, i + 1, start, parenDepth - 1, bracketDepth, braceDepth, angleDepth, revParts)
    else if (ch == 91) splitTopLevelByPipeLoop(s, i + 1, start, parenDepth, bracketDepth + 1, braceDepth, angleDepth, revParts)
    else if (ch == 93) splitTopLevelByPipeLoop(s, i + 1, start, parenDepth, bracketDepth - 1, braceDepth, angleDepth, revParts)
    else if (ch == 123) splitTopLevelByPipeLoop(s, i + 1, start, parenDepth, bracketDepth, braceDepth + 1, angleDepth, revParts)
    else if (ch == 125) splitTopLevelByPipeLoop(s, i + 1, start, parenDepth, bracketDepth, braceDepth - 1, angleDepth, revParts)
    else if (ch == 60) splitTopLevelByPipeLoop(s, i + 1, start, parenDepth, bracketDepth, braceDepth, angleDepth + 1, revParts)
    else if (ch == 62) splitTopLevelByPipeLoop(s, i + 1, start, parenDepth, bracketDepth, braceDepth, angleDepth - 1, revParts)
    else if (ch == 124 & parenDepth == 0 & bracketDepth == 0 & braceDepth == 0 & angleDepth == 0)
      splitTopLevelByPipeLoop(s, i + 1, i + 1, parenDepth, bracketDepth, braceDepth, angleDepth, Str.trim(Str.slice(s, start, i)) :: revParts)
    else splitTopLevelByPipeLoop(s, i + 1, start, parenDepth, bracketDepth, braceDepth, angleDepth, revParts)
  }

fun splitTopLevelByPipe(s: String): List<String> =
  if (Str.isEmpty(Str.trim(s))) []
  else Lst.reverse(splitTopLevelByPipeLoop(s, 0, 0, 0, 0, 0, 0, []))

fun multilineType(sig: String): String = {
  val eqPos = Str.indexOf(sig, "=");
  if (eqPos < 0)
    sig
  else {
    val head = Str.trim(Str.slice(sig, 0, eqPos));
    val rhs = Str.trim(Str.slice(sig, eqPos + 1, Str.length(sig)));
    val variants = splitTopLevelByPipe(rhs);
    if (Lst.length(variants) <= 1)
      sig
    else {
      val first = Opt.getOrElse(Lst.head(variants), "");
      val rest = Lst.drop(variants, 1);
      val firstLine = "    ${first}";
      val restLines = Lst.map(rest, (variant: String) => "  | ${variant}");
      val body = Str.join("\n", firstLine :: restLines);
      "${head} =\n${body}"
    }
  }
}

/// Format a `DocEntry` signature for display.
/// For `DKType` entries the full declaration is returned as-is (no truncation),
/// since the complete body is part of the type's public API.
/// When `multilineFunctions` is enabled, `fun` and `extern fun` declarations are
/// rendered one parameter per line for docs readability.
/// For all other kinds the signature is trimmed and truncated with ` …` if it
/// exceeds 120 characters.
export fun formatWith(entry: DocEntry, opts: FormatOptions): String = {
  val sig = Str.trim(entry.signature)
  if (entry.kind == DKType) multilineType(sig)
  else if (opts.multilineFunctions & isFunctionLike(entry)) multilineFunction(sig)
  else if (Str.length(sig) > 120) "${Str.slice(sig, 0, 117)} …"
  else sig
}

export fun format(entry: DocEntry): String =
  formatWith(entry, { multilineFunctions = False })
