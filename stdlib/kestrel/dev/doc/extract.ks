// kestrel:dev/doc/extract — Doc-comment extractor for Kestrel source files.
//
// Re-lexes a source string and produces a DocModule ADT describing the
// module's doc prose, exported declarations, and their attached doc-comment
// strings.  Supports /// per-declaration comments, //! module-level prose,
// and /** … */ block doc-comments.
//
// S09-01 — no compiler changes required; uses kestrel:dev/parser/lexer only.

import * as Str from "kestrel:data/string"
import * as Lst from "kestrel:data/list"
import * as Arr from "kestrel:data/array"
import * as Dict from "kestrel:data/dict"
import * as Res from "kestrel:data/result"
import * as Lex from "kestrel:dev/parser/lexer"
import { parseFromList } from "kestrel:dev/parser/parser"
import { Token, TkWs, TkLineComment, TkBlockComment, TkKw, TkOp, TkPunct,
         TkIdent, TkUpper, TkEof } from "kestrel:dev/parser/token"
import * as TC from "kestrel:dev/typecheck/typecheck"
import * as Ty from "kestrel:dev/typecheck/types"
import { readText, NotFound, PermissionDenied, IoError } from "kestrel:io/fs"

// ── ADTs ─────────────────────────────────────────────────────────────────────

/// Discriminator for the kind of a documented declaration.
export type DocKind =
    DKFun
  | DKType
  | DKVal
  | DKVar
  | DKException
  | DKExternType
  | DKExternFun

/// A single exported declaration and its attached documentation.
export type DocEntry = {
  name:      String,
  kind:      DocKind,
  signature: String,   // declaration head up to (not incl.) `=` or `{`
  doc:       String    // concatenated doc-comment lines; "" if none
}

/// The documentation for one source module.
export type DocModule = {
  moduleSpec:   String,         // e.g. "kestrel:data/list"
  moduleProse:  String,         // //! lines from file top; "" if none
  entries:      List<DocEntry>  // one per exported declaration, in order
}

// Fallback marker for inferred binding signatures when inference is unavailable.
val inferredTypeFallback = "<inference-unavailable>"

// ── Token helpers ─────────────────────────────────────────────────────────────

fun isTriviaToken(t: Token): Bool =
  t.kind == TkWs | t.kind == TkLineComment | t.kind == TkBlockComment

fun isDocLine(t: Token): Bool =
  t.kind == TkLineComment & Str.startsWith("///", t.text)

fun isModuleProseLine(t: Token): Bool =
  t.kind == TkLineComment & Str.startsWith("//!", t.text)

fun isDocBlock(t: Token): Bool =
  t.kind == TkBlockComment & Str.startsWith("/**", t.text)

fun containsBlankLine(t: Token): Bool =
  t.kind == TkWs & Str.contains("\n\n", t.text)

fun containsNewline(t: Token): Bool =
  t.kind == TkWs & Str.contains("\n", t.text)

fun hasExplicitTypeAnnotation(sig: String): Bool =
  Str.contains(":", sig)

fun inferExportTypeStrings(source: String): Dict<String, String> =
  match (parseFromList(Lex.lex(source))) {
    Err(_) => Dict.emptyStringDict()
    Ok(program) => {
      Ty.resetVarId();
      val tc = TC.typecheck(program, {
        importBindings = None,
        typeAliasBindings = None,
        importOpaqueTypes = None,
        sourceFile = "<doc-extract>"
      });
      Dict.map(tc.exports.items, (_name: String, t: Ty.InternalType) => Ty.typeToString(t))
    }
  }

fun applyInferredBindingType(entry: DocEntry, inferredTypes: Dict<String, String>): DocEntry = {
  val shouldInfer = (entry.kind == DKVal | entry.kind == DKVar) & !hasExplicitTypeAnnotation(entry.signature);
  if (!shouldInfer)
    entry
  else {
    val inferredText = match (Dict.get(inferredTypes, entry.name)) {
      Some(s) => s
      None    => inferredTypeFallback
    };
    {
      name = entry.name,
      kind = entry.kind,
      signature = "${entry.signature}: ${inferredText}",
      doc = entry.doc
    }
  }
}

// ── Text helpers ──────────────────────────────────────────────────────────────

// stripDocLine: remove "/// " or "///" prefix.  The lexer does NOT include the
// trailing \n in TkLineComment, so no newline stripping is needed.
fun stripDocLine(raw: String): String = {
  if (Str.startsWith("/// ", raw)) Str.dropLeft(raw, 4)
  else if (Str.startsWith("///", raw)) Str.dropLeft(raw, 3)
  else raw
}

fun stripModuleProseLine(raw: String): String = {
  if (Str.startsWith("//! ", raw)) Str.dropLeft(raw, 4)
  else if (Str.startsWith("//!", raw)) Str.dropLeft(raw, 3)
  else raw
}

// stripBlockDoc: extract body from /** … */ comment.
// Removes delimiters and strips leading " * " per line (JavaDoc style).
fun stripBlockDoc(raw: String): String = {
  val inner =
    if (Str.startsWith("/**", raw) & Str.endsWith("*/", raw))
      Str.slice(raw, 3, Str.length(raw) - 2)
    else raw;
  val linesList = Str.split(inner, "\n");
  val stripped = Lst.map(linesList, (line: String) => {
    val t = Str.trim(line);
    if (Str.startsWith("* ", t)) Str.dropLeft(t, 2)
    else if (Str.startsWith("*", t)) Str.dropLeft(t, 1)
    else t
  });
  val nonEmpty = Lst.filter(stripped, (s: String) => !Str.isEmpty(s));
  Str.join("\n", nonEmpty)
}

// normalizeWs: collapse whitespace runs to a single space, trim ends.
fun normalizeWs(s: String): String = {
  val noCtrl = Str.replace("\r", " ", Str.replace("\t", " ", Str.replace("\n", " ", s)));
  val words   = Lst.filter(Str.split(noCtrl, " "), (w: String) => !Str.isEmpty(w));
  Str.trim(Str.join(" ", words))
}

// skipTrivia: advance index past consecutive trivia tokens.
fun skipTrivia(arr: Array<Token>, i: Int, n: Int): Int = {
  var j = i;
  while (j < n & isTriviaToken(Arr.get(arr, j))) {
    j := j + 1
  };
  j
}

// ── Signature extraction ──────────────────────────────────────────────────────

// collectSig: collect normalised token text from startIdx (inclusive) up to
// (but not including) `=` or `{` at paren depth 0, OR a newline at depth 0
// after seeing at least one non-trivia token.
fun collectSig(arr: Array<Token>, startIdx: Int, n: Int): String = {
  var i    = startIdx;
  var depth = 0;
  val parts: Array<String> = Arr.new();
  var seenContent = False;
  var done = False;

  while (i < n & !done) {
    val t = Arr.get(arr, i);
    if (t.kind == TkEof) {
      done := True
    } else if (t.kind == TkWs) {
      if (depth == 0 & seenContent & containsNewline(t)) {
        done := True
      } else {
        Arr.push(parts, " ");
        i := i + 1
      }
    } else if (t.kind == TkLineComment | t.kind == TkBlockComment) {
      i := i + 1 // skip inline comments (should not appear in sigs)
    } else {
      // non-trivia token
      if (depth == 0 & t.kind == TkOp & Str.equals(t.text, "=")) {
        done := True
      } else if (depth == 0 & t.kind == TkPunct & Str.equals(t.text, "{")) {
        done := True
      } else {
        Arr.push(parts, t.text);
        seenContent := True;
        if (t.kind == TkPunct & Str.equals(t.text, "(")) {
          depth := depth + 1
        } else if (t.kind == TkPunct & Str.equals(t.text, ")")) {
          if (depth > 0) { depth := depth - 1 }
        } else if (t.kind == TkPunct & Str.equals(t.text, "[")) {
          depth := depth + 1
        } else if (t.kind == TkPunct & Str.equals(t.text, "]")) {
          if (depth > 0) { depth := depth - 1 }
        };
        i := i + 1
      }
    }
  };
  normalizeWs(Str.join("", Arr.toList(parts)))
}

// collectTypeSig: collect a full `type` declaration, including `=` and the RHS.
//
// Unlike collectSig (which stops at `=`) this function continues past `=` so
// the complete declaration is captured:
//   • ADT / type-alias:  stops at a blank line, or at a single newline when
//     the next non-trivia token is NOT `|`.  This handles both single-line ADTs
//     and multi-line ones where each continuation line starts with `|`.
//   • Record type: stops after the closing `}` that returns brace depth to 0.
//
// Original source whitespace is preserved verbatim (including newlines and
// indentation) so that multi-line record bodies render correctly inside <pre>.
fun collectTypeSig(arr: Array<Token>, startIdx: Int, n: Int): String = {
  var i          = startIdx;
  var braceDepth = 0;
  var parenDepth = 0;
  val parts: Array<String> = Arr.new();
  var seenEquals = False;
  var done       = False;

  while (i < n & !done) {
    val t = Arr.get(arr, i);
    if (t.kind == TkEof) {
      done := True
    } else if (t.kind == TkWs) {
      if (braceDepth == 0 & parenDepth == 0 & !seenEquals & containsNewline(t)) {
        // Newline before `=`: extern/opaque type head ends here
        done := True
      } else if (braceDepth == 0 & parenDepth == 0 & seenEquals & containsBlankLine(t)) {
        // Blank line at top level after `=`: end of ADT variant list
        done := True
      } else if (braceDepth == 0 & parenDepth == 0 & seenEquals & containsNewline(t)) {
        // Single newline at top level after `=`: continue when the next
        // non-trivia token is `|` (subsequent variant) or TkUpper (first
        // variant on a continuation line without a leading `|`).
        // Stop for keywords (fun, export, type, …) and lowercase identifiers.
        val j    = skipTrivia(arr, i + 1, n);
        val next = if (j < n) Arr.get(arr, j) else Arr.get(arr, n - 1);
        val cont = (next.kind == TkOp & Str.equals(next.text, "|")) | next.kind == TkUpper;
        if (cont) {
          Arr.push(parts, t.text);  // preserve newline + indent
          i := i + 1
        } else {
          done := True
        }
      } else {
        Arr.push(parts, t.text);   // preserve whitespace verbatim
        i := i + 1
      }
    } else if (t.kind == TkLineComment | t.kind == TkBlockComment) {
      i := i + 1;  // skip inline comments
      // Also skip the whitespace token immediately following the comment so
      // that comment lines inside record bodies don't leave blank lines in
      // the output (the whitespace *before* the comment is already in parts).
      if (i < n & Arr.get(arr, i).kind == TkWs) {
        i := i + 1
      }
    } else {
      if (t.kind == TkPunct & Str.equals(t.text, "{")) {
        braceDepth := braceDepth + 1;
        Arr.push(parts, t.text);
        i := i + 1
      } else if (t.kind == TkPunct & Str.equals(t.text, "}")) {
        braceDepth := braceDepth - 1;
        Arr.push(parts, t.text);
        i := i + 1;
        if (braceDepth == 0) { done := True }  // closed record body
      } else if (t.kind == TkPunct & Str.equals(t.text, "(")) {
        parenDepth := parenDepth + 1;
        Arr.push(parts, t.text);
        i := i + 1
      } else if (t.kind == TkPunct & Str.equals(t.text, ")")) {
        if (parenDepth > 0) { parenDepth := parenDepth - 1 };
        Arr.push(parts, t.text);
        i := i + 1
      } else {
        if (t.kind == TkOp & Str.equals(t.text, "=") & !seenEquals & braceDepth == 0 & parenDepth == 0) {
          seenEquals := True
        };
        Arr.push(parts, t.text);
        i := i + 1
      }
    }
  };
  Str.trim(Str.join("", Arr.toList(parts)))
}

// ── Declaration extraction ────────────────────────────────────────────────────

// resolveKind: determine DocKind from the tokens immediately after `export`.
// i0 is the index of the first non-trivia token after `export`.
// Returns None for re-exports (export { … } / export * from) or unknown forms.
fun resolveKind(arr: Array<Token>, i0: Int, n: Int): Option<DocKind> =
  if (i0 >= n)
    None
  else {
    val tok0 = Arr.get(arr, i0);
    if (tok0.kind == TkKw & Str.equals(tok0.text, "fun"))
      Some(DKFun)
    else if (tok0.kind == TkKw & Str.equals(tok0.text, "async")) {
      val i1 = skipTrivia(arr, i0 + 1, n);
      if (i1 < n & Arr.get(arr, i1).kind == TkKw & Str.equals(Arr.get(arr, i1).text, "fun"))
        Some(DKFun)
      else None
    }
    else if (tok0.kind == TkKw & Str.equals(tok0.text, "type"))      Some(DKType)
    else if (tok0.kind == TkKw & Str.equals(tok0.text, "val"))       Some(DKVal)
    else if (tok0.kind == TkKw & Str.equals(tok0.text, "var"))       Some(DKVar)
    else if (tok0.kind == TkKw & Str.equals(tok0.text, "exception")) Some(DKException)
    else if (tok0.kind == TkKw & Str.equals(tok0.text, "extern")) {
      val i1 = skipTrivia(arr, i0 + 1, n);
      if (i1 >= n) None
      else {
        val tok1 = Arr.get(arr, i1);
        if (tok1.kind == TkKw & Str.equals(tok1.text, "fun"))  Some(DKExternFun)
        else if (tok1.kind == TkKw & Str.equals(tok1.text, "type")) Some(DKExternType)
        else if (tok1.kind == TkKw & Str.equals(tok1.text, "opaque")) {
          val i2 = skipTrivia(arr, i1 + 1, n);
          if (i2 < n & Arr.get(arr, i2).kind == TkKw & Str.equals(Arr.get(arr, i2).text, "type"))
            Some(DKExternType)
          else None
        }
        else None
      }
    }
    else None
  }

// tryExtractEntry: starting at the `export` token at exportIdx, look ahead to
// determine the declaration kind, name, and normalised signature.
// Returns (Some(entry), nextIdx) or (None, exportIdx+1).
fun tryExtractEntry(arr: Array<Token>, exportIdx: Int, doc: String, n: Int): (Option<DocEntry>, Int) = {
  val i0   = skipTrivia(arr, exportIdx + 1, n);
  val kind = resolveKind(arr, i0, n);

  match (kind) {
    None => (None, exportIdx + 1),
    Some(k) => {
      val sigStart = i0; // signature begins at the keyword AFTER export (not at export)

      // Find the declaration name: first TkIdent or TkUpper after sigStart,
      // skipping any keyword tokens (async, extern, opaque, fun, type, …).
      var j       = skipTrivia(arr, sigStart, n);
      j           := j + 1; // skip the first keyword (fun / type / val / etc.)
      var nameStr = "";
      var found   = False;
      var guard   = 0;

      while (!found & guard < 8 & j < n) {
        j := skipTrivia(arr, j, n);
        if (j < n) {
          val nt = Arr.get(arr, j);
          if (nt.kind == TkIdent | nt.kind == TkUpper) {
            nameStr := nt.text;
            found   := True
          } else if (nt.kind == TkKw) {
            j := j + 1
          } else {
            guard := 8 // unexpected token — abort name search
          }
        };
        guard := guard + 1
      };

      val sig   = match (k) {
        DKType => collectTypeSig(arr, sigStart, n)
        _      => collectSig(arr, sigStart, n)
      };
      val entry = { name = nameStr, kind = k, signature = sig, doc = doc };
      (Some(entry), exportIdx + 1)
    }
  }
}

// ── Main extract function ─────────────────────────────────────────────────────

/// extract: produce a DocModule from a raw Kestrel source string.
export fun extract(source: String, spec: String): DocModule = {
  val inferredTypes = inferExportTypeStrings(source);
  val tokens = Lex.lex(source);
  val arr    = Arr.fromList(tokens);
  val n      = Arr.length(arr);

  // ── Phase 1: collect //! module-level prose from file top ──────────────────
  var i            = 0;
  val modProseBuf: Array<String> = Arr.new();
  var doneModProse = False;

  while (i < n & !doneModProse) {
    val t = Arr.get(arr, i);
    if (t.kind == TkWs) {
      i := i + 1
    } else if (isModuleProseLine(t)) {
      Arr.push(modProseBuf, stripModuleProseLine(t.text));
      i := i + 1
    } else {
      doneModProse := True
    }
  };

  val moduleProse = Str.join("\n", Arr.toList(modProseBuf));

  // ── Phase 2: scan for exported declarations with attached doc-comments ──────
  val entries: Array<DocEntry> = Arr.new();
  var scan               = 0;
  var pendingDocLines: Array<String> = Arr.new();
  var afterDocOnly       = False; // true iff only doc-comments+ws seen since last reset

  while (scan < n) {
    val t = Arr.get(arr, scan);
    if (t.kind == TkWs) {
      if (containsBlankLine(t)) {
        pendingDocLines := Arr.new();
        afterDocOnly    := False
      };
      scan := scan + 1
    } else if (isDocLine(t)) {
      if (!afterDocOnly) {
        // Starting a new doc block — discard any stale lines
        pendingDocLines := Arr.new()
      };
      Arr.push(pendingDocLines, stripDocLine(t.text));
      afterDocOnly := True;
      scan := scan + 1
    } else if (isDocBlock(t)) {
      if (!afterDocOnly) {
        pendingDocLines := Arr.new()
      };
      Arr.push(pendingDocLines, stripBlockDoc(t.text));
      afterDocOnly := True;
      scan := scan + 1
    } else if (t.kind == TkLineComment | t.kind == TkBlockComment) {
      // Non-doc comment resets pending block
      pendingDocLines := Arr.new();
      afterDocOnly    := False;
      scan            := scan + 1
    } else if (t.kind == TkKw & Str.equals(t.text, "export")) {
      val docStr =
        if (afterDocOnly) Str.join("\n", Arr.toList(pendingDocLines))
        else "";
      val extracted = tryExtractEntry(arr, scan, docStr, n);
      val entryOpt  = extracted.0;
      match (entryOpt) {
        Some(entry) => Arr.push(entries, applyInferredBindingType(entry, inferredTypes)),
        None        => ()
      };
      pendingDocLines := Arr.new();
      afterDocOnly    := False;
      scan            := scan + 1
    } else {
      // Any other non-trivia token resets pending doc
      pendingDocLines := Arr.new();
      afterDocOnly    := False;
      scan            := scan + 1
    }
  };

  { moduleSpec = spec, moduleProse = moduleProse, entries = Arr.toList(entries) }
}

/// extractFile: read a source file and call extract.
/// Returns Err(message) if the file cannot be read.
export async fun extractFile(path: String, spec: String): Task<Result<DocModule, String>> = {
  val result = await readText(path);
  match (result) {
    Ok(source)  => Ok(extract(source, spec)),
    Err(err)    => match (err) {
      NotFound         => Err("not_found: ${path}"),
      PermissionDenied => Err("permission_denied: ${path}"),
      IoError(msg)     => Err("io_error: ${msg}")
    }
  }
}
