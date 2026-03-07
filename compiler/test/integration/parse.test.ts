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

  it('parses if without else', () => {
    const ast = parse(tokenize('val a = if (True) { println("ok") }'));
    expect(ast.kind).toBe('Program');
    const valStmt = ast.body[0];
    if (valStmt.kind === 'ValStmt' && valStmt.value.kind === 'IfExpr') {
      expect(valStmt.value.else).toBeUndefined();
    }
  });

  it('parses fun decl with param and return type', () => {
    const ast = parse(tokenize('fun id(x): Int = 1'));
    expect(ast.kind).toBe('Program');
    expect(ast.body[0]).toMatchObject({ kind: 'FunDecl', exported: false, name: 'id' });
  });

  it('parses export fun decl', () => {
    const ast = parse(tokenize('export fun id(x): Int = 1'));
    expect(ast.kind).toBe('Program');
    expect(ast.body[0]).toMatchObject({ kind: 'FunDecl', exported: true, name: 'id' });
  });

  it('parses fun decl with typed param', () => {
    const ast = parse(tokenize('fun id(x: Int): Int = 1'));
    expect(ast.kind).toBe('Program');
    const fn = ast.body[0];
    expect(fn).toMatchObject({ kind: 'FunDecl', exported: false, name: 'id' });
    if (fn.kind === 'FunDecl') expect(fn.params[0].type).toBeDefined();
  });

  it('parses type decl as non-exported', () => {
    const ast = parse(tokenize('type Foo = Int'));
    expect(ast.kind).toBe('Program');
    expect(ast.body[0]).toMatchObject({ kind: 'TypeDecl', visibility: 'local', name: 'Foo' });
  });

  it('parses export type decl', () => {
    const ast = parse(tokenize('export type Foo = Int'));
    expect(ast.kind).toBe('Program');
    expect(ast.body[0]).toMatchObject({ kind: 'TypeDecl', visibility: 'export', name: 'Foo' });
  });

  it('parses opaque type decl (ADT)', () => {
    const ast = parse(tokenize('opaque type Token = Num(Int) | Op(String)'));
    expect(ast.kind).toBe('Program');
    expect(ast.body[0]).toMatchObject({ kind: 'TypeDecl', visibility: 'opaque', name: 'Token' });
  });

  it('parses opaque type decl (alias)', () => {
    const ast = parse(tokenize('opaque type UserId = Int'));
    expect(ast.kind).toBe('Program');
    expect(ast.body[0]).toMatchObject({ kind: 'TypeDecl', visibility: 'opaque', name: 'UserId' });
  });

  it('parses opaque type decl with generic params', () => {
    const ast = parse(tokenize('opaque type Result<T, E> = Ok(T) | Err(E)'));
    expect(ast.kind).toBe('Program');
    expect(ast.body[0]).toMatchObject({ kind: 'TypeDecl', visibility: 'opaque', name: 'Result' });
  });

  it('errors on export opaque type (both cannot be used together)', () => {
    expect(() => parse(tokenize('export opaque type Foo = Int'))).toThrow('Cannot use both "export" and "opaque"');
  });

  it('parses block with nested fun (emitted as FunStmt)', () => {
    const ast = parse(tokenize('fun outer(): Int = { fun inner(): Int = 42; inner() }'));
    expect(ast.kind).toBe('Program');
    expect(ast.body[0]).toMatchObject({ kind: 'FunDecl', name: 'outer' });
    const fn = ast.body[0];
    if (fn.kind === 'FunDecl' && fn.body.kind === 'BlockExpr') {
      expect(fn.body.stmts.length).toBe(1);
      expect(fn.body.stmts[0]).toMatchObject({ kind: 'FunStmt', name: 'inner' });
      const stmt = fn.body.stmts[0];
      if (stmt.kind === 'FunStmt') expect(stmt.body.kind).toBeDefined();
      expect(fn.body.result.kind).toBe('CallExpr');
    }
  });
});
