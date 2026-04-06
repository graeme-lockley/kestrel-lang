import * as Ast from "kestrel:dev/parser/ast"
import { lex } from "kestrel:dev/parser/lexer"
import * as Token from "kestrel:dev/parser/token"

export exception ParseError { message: String, offset: Int, line: Int, col: Int }

// MINIMAL PARSER STUB - Phases G & H
// Provides entry points for testing while full implementation is developed.

export fun parse(tokens: List<Token.Token>): Result<Ast.Program, ParseError> =
  Ok({imports=[], body=[]})

export fun parseExpr(tokens: List<Token.Token>): Result<Ast.Expr, ParseError> =
  Ok(Ast.ELit("unit","()"))
