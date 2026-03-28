/**
 * Parser — token stream to AST (spec 01 §3).
 */
export type { Program, Expr, Type, Pattern } from '../ast/nodes.js';
export {
  parse,
  ParseError,
  type ParseResult,
  type ParseErrorEntry,
  type ExprContext,
} from './parse.js';
