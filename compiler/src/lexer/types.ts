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

/** String literal with interpolation: parts alternate literal segments and expression sources. */
export type TemplatePart =
  | { type: 'literal'; value: string }
  | { type: 'interp'; source: string };

export interface Token {
  kind: TokenKind;
  value?: string;
  /** Set for string tokens that contain interpolation; then value is the empty string. */
  templateParts?: TemplatePart[];
  span: Span;
}

export const KEYWORDS = new Set([
  'as', 'fun', 'type', 'val', 'var', 'mut', 'if', 'else', 'match', 'try', 'catch', 'throw',
  'async', 'await', 'export', 'import', 'from', 'exception', 'is', 'opaque', 'True', 'False',
]);

export const MULTI_OPS = [
  '=>', ':=', '==', '!=', '>=', '<=', '**', '<|', '::', '|>', '->', '...',
];
