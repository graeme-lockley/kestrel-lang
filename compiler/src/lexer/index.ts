/**
 * Lexer — source string to token stream (spec 01 §2).
 */
export type { Token, TokenKind, Span } from './types.js';
export { KEYWORDS, MULTI_OPS } from './types.js';
export { tokenize } from './tokenize.js';
