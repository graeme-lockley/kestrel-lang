/**
 * Tokenize source into tokens (spec 01 §2). Longest match, shebang/comment skip.
 */
import type { Token, Span } from './types.js';
import { KEYWORDS, MULTI_OPS } from './types.js';

export function tokenize(source: string): Token[] {
  const tokens: Token[] = [];
  let i = 0;
  let line = 1;
  let column = 1;

  // Optional BOM
  if (source.length >= 3 && source.slice(0, 3) === '\uFEFF') {
    i = 3;
  }

  // Shebang (first line only)
  if (source.slice(i, i + 2) === '#!') {
    while (i < source.length && source[i] !== '\n') i++;
    if (i < source.length) i++;
    line = 2;
    column = 1;
  }

  function span(start: number, end: number, l: number, c: number): Span {
    return { start, end, line: l, column: c };
  }

  function peek(n = 0): string {
    return source[i + n] ?? '';
  }

  function take(): string {
    if (i >= source.length) return '';
    const c = source[i++];
    if (c === '\n') {
      line++;
      column = 1;
    } else {
      column++;
    }
    return c;
  }

  function skipWhitespace(): void {
    while (i < source.length) {
      const c = peek();
      if (c === ' ' || c === '\t' || c === '\r' || c === '\n') take();
      else break;
    }
  }

  function skipLineComment(): void {
    while (i < source.length && peek() !== '\n') take();
  }

  function skipBlockComment(): void {
    take(); // *
    while (i < source.length) {
      if (peek() === '*' && peek(1) === '/') {
        take();
        take();
        return;
      }
      take();
    }
  }

  function readIdentOrKeyword(): Token {
    const start = i;
    const l = line;
    const c = column;
    let raw = '';
    const first = peek();
    if (/[a-zA-Z_]/.test(first)) {
      raw += take();
      while (/[A-Za-z0-9_]/.test(peek())) raw += take();
    }
    const end = i;
    if (KEYWORDS.has(raw)) {
      const kind = raw === 'True' || raw === 'False' ? (raw === 'True' ? 'true' : 'false') : 'keyword';
      return { kind, value: raw, span: span(start, end, l, c) };
    }
    return { kind: 'ident', value: raw, span: span(start, end, l, c) };
  }

  function readNumber(): Token | null {
    const start = i;
    const l = line;
    const c = column;
    if (peek() === '0' && /[xXbBoO]/.test(peek(1))) {
      const prefix = take() + take();
      let digits = '';
      const set = prefix[1].toLowerCase() === 'x' ? /[0-9a-fA-F_]/
        : prefix[1].toLowerCase() === 'b' ? /[01_]/
        : /[0-7_]/;
      while (set.test(peek())) digits += take();
      if (digits.length === 0) return null;
      return { kind: 'int', value: prefix + digits, span: span(start, i, l, c) };
    }
    if (peek() === '.' && /[0-9]/.test(peek(1))) {
      take();
      while (/[0-9_]/.test(peek())) take();
      if (/[eE]/.test(peek())) {
        take();
        if (peek() === '+' || peek() === '-') take();
        while (/[0-9]/.test(peek())) take();
      }
      return { kind: 'float', value: source.slice(start, i), span: span(start, i, l, c) };
    }
    if (!/[0-9]/.test(peek())) return null;
    let digits = '';
    while (/[0-9_]/.test(peek())) digits += take();
    const afterDigits = peek();
    if (afterDigits === '.' || afterDigits === 'e' || afterDigits === 'E') {
      if (afterDigits === '.') take();
      while (/[0-9_]/.test(peek())) take();
      if (/[eE]/.test(peek())) {
        take();
        if (peek() === '+' || peek() === '-') take();
        while (/[0-9]/.test(peek())) take();
      }
      return { kind: 'float', value: source.slice(start, i), span: span(start, i, l, c) };
    }
    return { kind: 'int', value: digits, span: span(start, i, l, c) };
  }

  function readString(): Token | null {
    if (peek() !== '"') return null;
    const start = i;
    const l = line;
    const c = column;
    take(); // "
    let value = '';
    while (i < source.length) {
      const c2 = peek();
      if (c2 === '"') {
        take();
        break;
      }
      if (c2 === '\\') {
        take();
        const esc = take();
        if (esc === 'n') value += '\n';
        else if (esc === 'r') value += '\r';
        else if (esc === 't') value += '\t';
        else if (esc === '"' || esc === '\\') value += esc;
        else if (esc === 'u' && peek() === '{') {
          take();
          let hex = '';
          while (/[0-9a-fA-F]/.test(peek())) hex += take();
          if (peek() !== '}' || hex.length === 0) return null;
          take();
          value += String.fromCodePoint(parseInt(hex, 16));
        } else return null;
      } else if (c2 === '\n') return null;
      else value += take();
    }
    return { kind: 'string', value, span: span(start, i, l, c) };
  }

  function readChar(): Token | null {
    if (peek() !== "'") return null;
    const start = i;
    const l = line;
    const c = column;
    take(); // '
    let value = '';
    if (peek() === '\\') {
      take();
      const esc = take();
      if (esc === 'n') value = '\n';
      else if (esc === 'r') value = '\r';
      else if (esc === 't') value = '\t';
      else if (esc === "'" || esc === '\\') value = esc;
      else if (esc === 'u' && peek() === '{') {
        take();
        let hex = '';
        while (/[0-9a-fA-F]/.test(peek())) hex += take();
        if (peek() !== '}') return null;
        take();
        value = String.fromCodePoint(parseInt(hex, 16));
      } else return null;
    } else {
      value = take();
    }
    if (peek() !== "'") return null;
    take();
    return { kind: 'char', value, span: span(start, i, l, c) };
  }

  function readOpOrDelim(): Token | null {
    const start = i;
    const l = line;
    const c = column;
    for (const op of MULTI_OPS) {
      if (source.slice(i, i + op.length) === op) {
        for (let k = 0; k < op.length; k++) take();
        return { kind: 'op', value: op, span: span(start, i, l, c) };
      }
    }
    const single = peek();
    const singleOps = '+-*/%|&<=>!';
    if (singleOps.includes(single)) {
      take();
      return { kind: 'op', value: single, span: span(start, i, l, c) };
    }
    const delims: [string, Token['kind']][] = [
      ['(', 'lparen'], [')', 'rparen'], ['{', 'lbrace'], ['}', 'rbrace'],
      ['[', 'lbrack'], [']', 'rbrack'], [',', 'comma'], [':', 'colon'],
      ['.', 'dot'], [';', 'semicolon'],
    ];
    for (const [d, kind] of delims) {
      if (peek() === d) {
        take();
        return { kind, span: span(start, i, l, c) };
      }
    }
    return null;
  }

  while (i < source.length) {
    skipWhitespace();
    if (i >= source.length) break;

    const c = peek();

    if (c === '/' && peek(1) === '/') {
      take();
      take();
      skipLineComment();
      continue;
    }
    if (c === '/' && peek(1) === '*') {
      take();
      skipBlockComment();
      continue;
    }

    if (c === ' ' || c === '\t' || c === '\r') {
      take();
      continue;
    }
    if (c === '\n') {
      take();
      continue;
    }

    if (/[a-zA-Z_]/.test(c)) {
      tokens.push(readIdentOrKeyword());
      continue;
    }

    if (c === '.' && /[0-9]/.test(peek(1))) {
      const t = readNumber();
      if (t) {
        tokens.push(t);
        continue;
      }
    }
    if (/[0-9]/.test(c)) {
      const t = readNumber();
      if (t) {
        tokens.push(t);
        continue;
      }
    }

    if (c === '"') {
      const t = readString();
      if (t) {
        tokens.push(t);
        continue;
      }
    }
    if (c === "'") {
      const t = readChar();
      if (t) {
        tokens.push(t);
        continue;
      }
    }

    const op = readOpOrDelim();
    if (op) {
      tokens.push(op);
      continue;
    }

    take(); // skip unknown char or throw
  }

  tokens.push({ kind: 'eof', span: span(i, i, line, column) });
  return tokens;
}
