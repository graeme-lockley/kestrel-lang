//! Token model shared by lexer and parser.
//!
//! Defines source spans, token kinds, template-literal parts, and the `Token`
//! record used throughout parsing and formatting.

import * as Lst from "kestrel:data/list"

// Span records the source location of a token.
export type Span = { start: Int, end: Int, line: Int, col: Int }

// TemplatePart represents one segment of an interpolated string literal.
// TPLiteral — a decoded literal text segment between interpolations.
// TPInterp  — the raw source of an interpolated expression (between ${ and }).
export type TemplatePart =
    TPLiteral(String)
  | TPInterp(String)

// TokenKind discriminates every token produced by the lexer.
// Invariant: token.text is always the raw source text. Concatenating all
// token texts in order reconstructs the original source exactly (round-trip).
export type TokenKind =
    TkInt               // integer literal; text = raw ("42", "0xff", "0b101")
  | TkFloat             // float literal;   text = raw ("3.14", "1e10")
  | TkStr               // plain string;    text = raw source incl. surrounding "quotes"
  | TkTemplate(List<TemplatePart>)  // interpolated; text = full raw source incl. quotes
  | TkChar              // char literal;    text = raw source incl. surrounding 'quotes'
  | TkIdent             // lowercase-first identifier; text = name
  | TkUpper             // uppercase-first ident (incl. True, False); text = name
  | TkKw                // keyword; text = the keyword string
  | TkOp                // operator; text = operator text
  | TkPunct             // punctuation; text = single char
  | TkWs                // whitespace (spaces, tabs, newlines); text = raw
  | TkLineComment       // // ... to end-of-line; text = raw incl. "//"
  | TkBlockComment      // /* ... */; text = raw incl. delimiters
  | TkEof               // end of file; text = ""

// Token bundles a TokenKind with its raw source text and source location.
export type Token = { kind: TokenKind, text: String, span: Span }

// isTrivia returns True for whitespace and comment tokens (TkWs, TkLineComment,
// TkBlockComment). The parser pre-filters these out before parsing.
export fun isTrivia(t: Token): Bool =
  match (t.kind) {
    TkWs => True,
    TkLineComment => True,
    TkBlockComment => True,
    _ => False
  }

// spanZero produces a zero-width span at the very start of the source (line 1, col 1).
export fun spanZero(): Span = { start = 0, end = 0, line = 1, col = 1 }
