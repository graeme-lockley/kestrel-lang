import { describe, it, expect } from 'vitest';
import { tokenize } from '../../src/lexer/index.js';
import { parse } from '../../src/parser/index.js';

describe('parse (integration)', () => {
  it('tokenize then parse yields Program with body', () => {
    const tokens = tokenize('val x = 1');
    const ast = parse(tokens);
    expect(ast.kind).toBe('Program');
    expect(ast.body.length).toBe(1);
    expect(ast.body[0]).toMatchObject({ kind: 'ValStmt', name: 'x' });
  });

  it('parses if/else expression', () => {
    const ast = parse(tokenize('val a = if (True) 1 else 2'));
    expect(ast.kind).toBe('Program');
    expect(ast.body[0]).toMatchObject({ kind: 'ValStmt', name: 'a' });
    const valStmt = ast.body[0];
    if (valStmt.kind === 'ValStmt') expect(valStmt.value.kind).toBe('IfExpr');
  });

  it('parses fun decl with param and return type', () => {
    const ast = parse(tokenize('fun id(x): Int = 1'));
    expect(ast.kind).toBe('Program');
    expect(ast.body[0]).toMatchObject({ kind: 'FunDecl', name: 'id' });
  });

  it('parses fun decl with typed param', () => {
    const ast = parse(tokenize('fun id(x: Int): Int = 1'));
    expect(ast.kind).toBe('Program');
    const fn = ast.body[0];
    expect(fn).toMatchObject({ kind: 'FunDecl', name: 'id' });
    if (fn.kind === 'FunDecl') expect(fn.params[0].type).toBeDefined();
  });
});
