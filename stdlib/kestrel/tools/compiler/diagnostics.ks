//! Compiler diagnostic types and location utilities.
//!
//! Defines `Severity`, `Diagnostic`, `SourceLocation`, `Span`, and `CODES` —
//! the data structures shared by all compiler passes that produce or consume diagnostics.
import * as Str from "kestrel:data/string"

/// Diagnostic severity level.
export type Severity =
    Error
  | Warning
  | Info
  | Hint

/// A half-open byte-offset range `[startOffset, endOffset)` in a source file,
/// with pre-computed start line/column.
export type Span = {
  file: String,
  startOffset: Int,
  endOffset: Int,
  startLine: Int,
  startColumn: Int
}

/// A resolved source location, typically derived from a `Span`.
/// Includes optional end position for range highlighting.
export type SourceLocation = {
  file: String,
  line: Int,
  column: Int,
  endLine: Option<Int>,
  endColumn: Option<Int>,
  offset: Option<Int>,
  endOffset: Option<Int>
}

/// A secondary location attached to a diagnostic, e.g. a previous declaration site.
export type RelatedLocation = { message: String, location: SourceLocation }

/// A single compiler diagnostic: severity, structured code, human-readable message,
/// source location, and optional hint and suggestion.
export type Diagnostic = {
  severity: Severity,
  code: String,
  message: String,
  location: SourceLocation,
  sourceLine: Option<String>,
  related: List<RelatedLocation>,
  suggestion: Option<String>,
  hint: Option<String>
}

/// Well-known diagnostic code strings, grouped by compiler phase.
export val CODES = {
  parse = {
    unexpectedToken = "parse:unexpected_token",
    expectedSemicolon = "parse:expected_semicolon",
    unmatchedBrace = "parse:unmatched_brace",
    expectedExpr = "parse:expected_expr"
  },
  resolve = {
    moduleNotFound = "resolve:module_not_found",
    stdlibNotConfigured = "resolve:stdlib_not_configured",
    urlNotSupported = "resolve:url_not_supported"
  },
  type_ = {
    unknownVariable = "type:unknown_variable",
    unify = "type:unify",
    nonExhaustiveMatch = "type:non_exhaustive_match",
    check = "type:check",
    breakOutsideLoop = "type:break_outside_loop",
    continueOutsideLoop = "type:continue_outside_loop",
    narrowImpossible = "type:narrow_impossible",
    narrowOpaque = "type:narrow_opaque"
  },
  export_ = {
    notExported = "export:not_exported",
    importConflict = "export:import_conflict",
    reexportConflict = "export:reexport_conflict"
  },
  file = {
    readError = "file:read_error",
    circularImport = "file:circular_import"
  },
  compile = {
    jvmNamespaceConstructor = "compile:jvm_namespace_constructor"
  }
}

fun lineColumnFromOffsetLoop(source: String, offset: Int, i: Int, line: Int, col: Int): (Int, Int) =
  if (i >= offset) (line, col)
  else {
    val cp = Str.codePointAt(source, i)
    if (cp == 10) lineColumnFromOffsetLoop(source, offset, i + 1, line + 1, 1)
    else lineColumnFromOffsetLoop(source, offset, i + 1, line, col + 1)
  }

/// Returns a 1-based (line, column) pair for the given 0-based source offset.
export fun lineColumnFromOffset(source: String, offset: Int): (Int, Int) = {
  val n = Str.length(source)
  if (offset < 0 | offset >= n)
    (1, 1)
  else
    lineColumnFromOffsetLoop(source, offset, 0, 1, 1)
}

/// Build a SourceLocation from a span and optional source for end location.
export fun locationFromSpan(file: String, span: Span, source: Option<String>): SourceLocation =
  match (source) {
    None => {
      file = file,
      line = span.startLine,
      column = span.startColumn,
      endLine = None,
      endColumn = None,
      offset = Some(span.startOffset),
      endOffset = Some(span.endOffset)
    },
    Some(src) => {
      val endLc = lineColumnFromOffset(src, span.endOffset)
      {
        file = file,
        line = span.startLine,
        column = span.startColumn,
        endLine = Some(endLc.0),
        endColumn = Some(endLc.1),
        offset = Some(span.startOffset),
        endOffset = Some(span.endOffset)
      }
    }
  }

/// Location when only a file path is known.
export fun locationFileOnly(file: String): SourceLocation = {
  file = file,
  line = 1,
  column = 1,
  endLine = None,
  endColumn = None,
  offset = None,
  endOffset = None
}
