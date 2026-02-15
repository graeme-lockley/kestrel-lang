/**
 * Token kinds and span (spec 01 §2).
 */
export interface Span {
  start: number;
  end: number;
  line: number;
  column: number;
}

export type TokenKind =
  | 'keyword'
  | 'ident'
  | 'int'
  | 'float'
  | 'string'
  | 'char'
  | 'true'
  | 'false'
  | 'unit' // synthetic for ()
  | 'op'   // := == != >= <= => ** <| :: |> + - * / % | & < >
  | 'lparen' | 'rparen' | 'lbrace' | 'rbrace' | 'lbrack' | 'rbrack'
  | 'comma' | 'colon' | 'dot' | 'semicolon'
  | 'newline'
  | 'eof';

export interface Token {
  kind: TokenKind;
  value?: string;
  span: Span;
}

export const KEYWORDS = new Set([
  'fun', 'type', 'val', 'var', 'mut', 'if', 'else', 'match', 'try', 'catch', 'throw',
  'async', 'await', 'export', 'import', 'from', 'exception', 'is', 'True', 'False',
]);

export const MULTI_OPS = [
  '=>', ':=', '==', '!=', '>=', '<=', '**', '<|', '::', '|>', '->',
];
