import { describe, it, expect } from 'vitest';
import { tokenize } from '../../src/lexer/index.js';

describe('tokenize', () => {
  it('returns eof for empty source', () => {
    const tokens = tokenize('');
    expect(tokens.length).toBe(1);
    expect(tokens[0].kind).toBe('eof');
  });

  it('tokenizes keywords', () => {
    const tokens = tokenize('fun val if else match while break continue');
    const kinds = tokens.map((t) => t.kind);
    expect(kinds).toContain('keyword');
    expect(tokens.find((t) => t.value === 'fun')?.kind).toBe('keyword');
    expect(tokens.find((t) => t.value === 'val')?.kind).toBe('keyword');
    expect(tokens.find((t) => t.value === 'break')?.kind).toBe('keyword');
    expect(tokens.find((t) => t.value === 'continue')?.kind).toBe('keyword');
  });

  it('tokenizes True and False as boolean literals', () => {
    const tokens = tokenize('True False');
    expect(tokens.find((t) => t.value === 'True')?.kind).toBe('true');
    expect(tokens.find((t) => t.value === 'False')?.kind).toBe('false');
  });

  it('tokenizes identifiers (lower and upper)', () => {
    const tokens = tokenize('foo Bar _x');
    expect(tokens.find((t) => t.value === 'foo')?.kind).toBe('ident');
    expect(tokens.find((t) => t.value === 'Bar')?.kind).toBe('ident');
    expect(tokens.find((t) => t.value === '_x')?.kind).toBe('ident');
  });

  it('tokenizes integers (decimal, hex, binary, octal)', () => {
    expect(tokenize('0')[0].kind).toBe('int');
    expect(tokenize('123')[0]).toMatchObject({ kind: 'int', value: '123' });
    expect(tokenize('0xFF')[0]).toMatchObject({ kind: 'int', value: '0xFF' });
    expect(tokenize('0b1010')[0]).toMatchObject({ kind: 'int', value: '0b1010' });
    expect(tokenize('0o77')[0]).toMatchObject({ kind: 'int', value: '0o77' });
  });

  it('tokenizes floats', () => {
    expect(tokenize('1.0')[0]).toMatchObject({ kind: 'float', value: '1.0' });
    expect(tokenize('.5')[0]).toMatchObject({ kind: 'float' });
    expect(tokenize('1e10')[0]).toMatchObject({ kind: 'float' });
  });

  it('tokenizes strings with escapes', () => {
    const tokens = tokenize('"hello"');
    expect(tokens[0]).toMatchObject({ kind: 'string', value: 'hello' });
    const t2 = tokenize('"\\n\\t"');
    expect(t2[0]).toMatchObject({ kind: 'string', value: '\n\t' });
  });

  it('tokenizes => as single op', () => {
    const tokens = tokenize('=>');
    expect(tokens[0]).toMatchObject({ kind: 'op', value: '=>' });
  });

  it('tokenizes longest match for >= and <=', () => {
    expect(tokenize('>=')[0].value).toBe('>=');
    expect(tokenize('<=')[0].value).toBe('<=');
  });

  it('skips shebang on first line', () => {
    const tokens = tokenize('#!/usr/bin/env kestrel\nval x = 1');
    expect(tokens[0]).toMatchObject({ kind: 'keyword', value: 'val' });
  });

  it('tokenizes ): as rparen then colon', () => {
    const tokens = tokenize('):');
    expect(tokens[0].kind).toBe('rparen');
    expect(tokens[1].kind).toBe('colon');
  });

  it('tokenizes fun id(x: Int): Int = x with rparen before second colon', () => {
    const tokens = tokenize('fun id(x: Int): Int = x');
    const kinds = tokens.map((t) => t.kind);
    const idxInt = tokens.findIndex((t) => t.value === 'Int');
    expect(idxInt).toBeGreaterThanOrEqual(0);
    const afterFirstInt = tokens[idxInt + 1];
    expect(afterFirstInt?.kind).toBe('rparen');
  });

  it('skips line and block comments', () => {
    const tokens = tokenize('val // comment\nx = 1');
    expect(tokens.find((t) => t.value === 'x')).toBeDefined();
    const t2 = tokenize('val /* block */ x = 1');
    expect(t2.find((t) => t.value === 'x')).toBeDefined();
  });
});
