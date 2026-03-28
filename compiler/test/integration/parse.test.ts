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

  it('parses while with block body', () => {
    const ast = parse(tokenize('val x = while (False) { 1 }'));
    expect(ast.kind).toBe('Program');
    const valStmt = ast.body[0];
    expect(valStmt).toMatchObject({ kind: 'ValStmt', name: 'x' });
    if (valStmt.kind === 'ValStmt') {
      expect(valStmt.value.kind).toBe('WhileExpr');
      if (valStmt.value.kind === 'WhileExpr') {
        expect(valStmt.value.body.kind).toBe('BlockExpr');
      }
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
    const result = parse(tokenize('export opaque type Foo = Int'));
    expect('ok' in result && !result.ok).toBe(true);
    if ('ok' in result && !result.ok) {
      expect(result.errors.some((e) => e.message.includes('Cannot use both "export" and "opaque"'))).toBe(true);
    }
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

  it('parses primitive literal patterns in match cases', () => {
    const ast = parse(tokenize(`val x = match (n) { 1 => 10, 1.5 => 20, "s" => 30, 'a' => 40, () => 50, _ => 60 }`));
    expect(ast.kind).toBe('Program');
    const stmt = ast.body[0];
    expect(stmt).toMatchObject({ kind: 'ValStmt', name: 'x' });
    if (stmt.kind !== 'ValStmt' || stmt.value.kind !== 'MatchExpr') return;
    const literals = stmt.value.cases
      .filter((c) => c.pattern.kind === 'LiteralPattern')
      .map((c) => (c.pattern.kind === 'LiteralPattern' ? c.pattern.literal : ''));
    expect(literals).toEqual(['int', 'float', 'string', 'char', 'unit']);
  });

  it('parses block val with int literal then parenthesized | chain without semicolon (literal is not call callee)', () => {
    const src = `fun f(): Bool = {
  val cp = 1
  (cp >= 48 & cp <= 57) | (cp >= 65 & cp <= 70)
}`;
    const ast = parse(tokenize(src));
    expect(ast.kind).toBe('Program');
    const fn = ast.body[0];
    if (fn.kind !== 'FunDecl' || fn.body.kind !== 'BlockExpr') return;
    expect(fn.body.stmts.length).toBe(1);
    const vs = fn.body.stmts[0];
    expect(vs).toMatchObject({ kind: 'ValStmt', name: 'cp' });
    if (vs.kind === 'ValStmt') expect(vs.value.kind).toBe('LiteralExpr');
    expect(fn.body.result.kind).toBe('BinaryExpr');
    if (fn.body.result.kind === 'BinaryExpr') expect(fn.body.result.op).toBe('|');
  });

  it('parses block val ending in call then `(` line only when `;` terminates the val (currying otherwise)', () => {
    const withSemi = `fun f(): Bool = {
  val cp = g(1);
  (cp >= 48 & cp <= 57) | (cp >= 65 & cp <= 70)
}`;
    const astOk = parse(tokenize(withSemi));
    expect(astOk.kind).toBe('Program');
    const fn = astOk.body[0];
    if (fn.kind !== 'FunDecl' || fn.body.kind !== 'BlockExpr') return;
    expect(fn.body.stmts.length).toBe(1);
    expect(fn.body.result.kind).toBe('BinaryExpr');

    const noSemi = `fun f(): Bool = {
  val cp = g(1)
  (cp >= 48 & cp <= 57) | (cp >= 65 & cp <= 70)
}`;
    const astBad = parse(tokenize(noSemi));
    expect('ok' in astBad && !astBad.ok).toBe(true);
  });

  it('allows implicit Unit when block ends with assign/binding in statement-oriented while body', () => {
    const src = `fun f(): Unit = { while (False) { if (True) { var x = 1 } } }`;
    const ast = parse(tokenize(src));
    expect(ast.kind).toBe('Program');
  });

  it('rejects block ending with binding only when if branch is in expression context (e.g. fun body block)', () => {
    const result = parse(tokenize('fun f(): Unit = { if (True) { var x = 1 } }'));
    expect('ok' in result && !result.ok).toBe(true);
    if ('ok' in result && !result.ok) {
      expect(result.errors.some((e) => e.message.includes('Expected expression before'))).toBe(true);
    }
  });

  it('parses nested literal patterns in list and record patterns', () => {
    const ast = parse(tokenize(`
      val y = match (xs) {
        [1, rest] => 10,
        Some { value = 42 } => 20,
        _ => 30
      }
    `));
    expect(ast.kind).toBe('Program');
    const stmt = ast.body[0];
    if (stmt.kind !== 'ValStmt' || stmt.value.kind !== 'MatchExpr') return;

    const listCase = stmt.value.cases[0];
    expect(listCase?.pattern.kind).toBe('ListPattern');
    if (listCase?.pattern.kind === 'ListPattern') {
      expect(listCase.pattern.elements[0]).toMatchObject({ kind: 'LiteralPattern', literal: 'int', value: '1' });
    }

    const recordCase = stmt.value.cases[1];
    expect(recordCase?.pattern.kind).toBe('ConstructorPattern');
    if (recordCase?.pattern.kind === 'ConstructorPattern') {
      expect(recordCase.pattern.fields?.[0]?.pattern).toMatchObject({ kind: 'LiteralPattern', literal: 'int', value: '42' });
    }
  });
});
