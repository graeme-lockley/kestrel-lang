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

  it('parses break and continue in while body', () => {
    const ast = parse(tokenize('fun f(): Unit = { while (True) { break; continue } }'));
    expect(ast.body[0]?.kind).toBe('FunDecl');
    const fd = ast.body[0];
    if (fd?.kind !== 'FunDecl') return;
    expect(fd.body.kind).toBe('BlockExpr');
    const wb = fd.body;
    if (wb.kind !== 'BlockExpr') return;
    const wh = wb.result;
    expect(wh.kind).toBe('WhileExpr');
    if (wh.kind !== 'WhileExpr') return;
    const inner = wh.body;
    expect(inner.stmts.map((s) => s.kind)).toEqual(['BreakStmt', 'ContinueStmt']);
  });

  it('parses expression-oriented block ending with break as NeverExpr tail', () => {
    const ast = parse(tokenize('fun f(): Unit = { break }'));
    const fd = ast.body[0];
    expect(fd?.kind).toBe('FunDecl');
    if (fd?.kind !== 'FunDecl') return;
    expect(fd.body.kind).toBe('BlockExpr');
    const b = fd.body;
    if (b.kind !== 'BlockExpr') return;
    expect(b.stmts.map((s) => s.kind)).toEqual(['BreakStmt']);
    expect(b.result.kind).toBe('NeverExpr');
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

  it('parses export async fun decl', () => {
    const ast = parse(tokenize('export async fun run(s): Task<Unit> = ()'));
    expect(ast.kind).toBe('Program');
    expect(ast.body[0]).toMatchObject({ kind: 'FunDecl', exported: true, async: true, name: 'run' });
  });

  it('parses top-level async fun', () => {
    const ast = parse(tokenize('async fun f(): Task<Int> = 1'));
    expect(ast.kind).toBe('Program');
    expect(ast.body[0]).toMatchObject({ kind: 'FunDecl', async: true, name: 'f' });
  });

  it('parses async lambda expressions', () => {
    const ast = parse(tokenize('val inc = async (x: Int) => x + 1'));
    expect(ast.kind).toBe('Program');
    const stmt = ast.body[0];
    expect(stmt).toMatchObject({ kind: 'ValStmt', name: 'inc' });
    if (stmt.kind !== 'ValStmt') return;
    expect(stmt.value).toMatchObject({ kind: 'LambdaExpr', async: true });
  });

  it('parses generic async lambda expressions', () => {
    const ast = parse(tokenize('val id = async <T>(x: T) => x'));
    expect(ast.kind).toBe('Program');
    const stmt = ast.body[0];
    expect(stmt).toMatchObject({ kind: 'ValStmt', name: 'id' });
    if (stmt.kind !== 'ValStmt' || stmt.value.kind !== 'LambdaExpr') return;
    expect(stmt.value.async).toBe(true);
    expect(stmt.value.typeParams).toEqual(['T']);
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

  it('parses extern type decl', () => {
    const ast = parse(tokenize('extern type HashMap = jvm("java.util.HashMap")'));
    expect(ast.kind).toBe('Program');
    expect(ast.body[0]).toMatchObject({ kind: 'ExternTypeDecl', visibility: 'local', name: 'HashMap', jvmClass: 'java.util.HashMap' });
  });

  it('parses export extern type decl', () => {
    const ast = parse(tokenize('export extern type HashMap = jvm("java.util.HashMap")'));
    expect(ast.kind).toBe('Program');
    expect(ast.body[0]).toMatchObject({ kind: 'ExternTypeDecl', visibility: 'export', name: 'HashMap', jvmClass: 'java.util.HashMap' });
  });

  it('errors on extern type missing = jvm(...)', () => {
    const result = parse(tokenize('extern type HashMap'));
    expect('ok' in result && !result.ok).toBe(true);
    if ('ok' in result && !result.ok) {
      expect(result.errors.some((e) => e.message.includes('Expected = jvm("...")'))).toBe(true);
    }
  });

  it('errors on extern type non-jvm RHS', () => {
    const result = parse(tokenize('extern type HashMap = "java.util.HashMap"'));
    expect('ok' in result && !result.ok).toBe(true);
    if ('ok' in result && !result.ok) {
      expect(result.errors.some((e) => e.message.includes('Expected jvm("...")'))).toBe(true);
    }
  });

  it('parses extern fun decl', () => {
    const ast = parse(tokenize('extern fun length(s: String): Int = jvm("java.lang.String#length()")'));
    expect(ast.kind).toBe('Program');
    expect(ast.body[0]).toMatchObject({ kind: 'ExternFunDecl', exported: false, name: 'length', jvmDescriptor: 'java.lang.String#length()' });
  });

  it('parses export extern fun decl', () => {
    const ast = parse(tokenize('export extern fun length(s: String): Int = jvm("java.lang.String#length()")'));
    expect(ast.kind).toBe('Program');
    expect(ast.body[0]).toMatchObject({ kind: 'ExternFunDecl', exported: true, name: 'length' });
  });

  it('errors on extern fun missing = jvm(...)', () => {
    const result = parse(tokenize('extern fun foo(x: Int): Int'));
    expect('ok' in result && !result.ok).toBe(true);
    if ('ok' in result && !result.ok) {
      expect(result.errors.some((e) => e.message.includes('Expected = jvm("...") in extern fun declaration'))).toBe(true);
    }
  });

  it('parses parametric extern fun decl', () => {
    const ast = parse(tokenize('extern fun get<V>(k: String): V = jvm("kestrel.runtime.KRuntime#formatOne(java.lang.Object)")'));
    expect(ast.kind).toBe('Program');
    expect(ast.body[0]).toMatchObject({ kind: 'ExternFunDecl', name: 'get', typeParams: ['V'] });
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
    // Without ';', 'g(1)' followed by '(...)' on the next line fuses into a
    // single call expression 'g(1)(...)' as the val RHS; the block then ends
    // with an implicit '()' result.  This is a valid parse (type-checker will
    // report the mismatch).  Semicolon is needed to express the intended
    // program where '(...)' is the block result.
    const astBad = parse(tokenize(noSemi));
    expect(astBad.kind).toBe('Program');
  });

  it('allows implicit Unit when block ends with assign/binding in statement-oriented while body', () => {
    const src = `fun f(): Unit = { while (False) { if (True) { var x = 1 } } }`;
    const ast = parse(tokenize(src));
    expect(ast.kind).toBe('Program');
  });

  it('allows implicit Unit in if branch in expression context (e.g. fun body block)', () => {
    // Blocks ending with a binding now produce an implicit '()' result in all
    // contexts, so this is a valid parse; type-checking will verify the types.
    const result = parse(tokenize('fun f(): Unit = { if (True) { var x = 1 } }'));
    expect(result.kind).toBe('Program');
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

  it('parses is with union type on RHS (type | binds tighter than is)', () => {
    const ast = parse(tokenize('fun f(): Bool = x is Int | String'));
    const fd = ast.body[0];
    expect(fd?.kind).toBe('FunDecl');
    if (fd?.kind !== 'FunDecl') return;
    expect(fd.body.kind).toBe('IsExpr');
    if (fd.body.kind === 'IsExpr') {
      expect(fd.body.testedType.kind).toBe('UnionType');
    }
  });

  it('parses relational tighter than is: a == b is Bool', () => {
    const ast = parse(tokenize('fun f(a: Int, b: Int): Bool = a == b is Bool'));
    const fd = ast.body[0];
    if (fd?.kind !== 'FunDecl') return;
    expect(fd.body.kind).toBe('IsExpr');
    if (fd.body.kind === 'IsExpr') {
      expect(fd.body.expr.kind).toBe('BinaryExpr');
    }
  });

  it('parses a & b is Int as a & (b is Int)', () => {
    const ast = parse(tokenize('fun f(a: Bool, b: Int): Bool = a & b is Int'));
    const fd = ast.body[0];
    if (fd?.kind !== 'FunDecl') return;
    expect(fd.body.kind).toBe('BinaryExpr');
    if (fd.body.kind === 'BinaryExpr' && fd.body.op === '&') {
      expect(fd.body.right.kind).toBe('IsExpr');
    }
  });

  // extern import
  it('parses extern import with empty override block', () => {
    const ast = parse(tokenize('extern import "java:java.util.HashMap" as HashMap { }'));
    expect(ast.kind).toBe('Program');
    expect(ast.body[0]).toMatchObject({
      kind: 'ExternImportDecl',
      target: 'java:java.util.HashMap',
      alias: 'HashMap',
      overrides: [],
    });
  });

  it('parses extern import without braces', () => {
    const ast = parse(tokenize('extern import "java:java.lang.String" as JString'));
    expect(ast.kind).toBe('Program');
    expect(ast.body[0]).toMatchObject({
      kind: 'ExternImportDecl',
      target: 'java:java.lang.String',
      alias: 'JString',
      overrides: [],
    });
  });

  it('parses extern import with method overrides', () => {
    const ast = parse(tokenize(
      'extern import "java:java.util.HashMap" as HashMap { fun size(m: HashMap): Int }'
    ));
    expect(ast.kind).toBe('Program');
    const decl = ast.body[0];
    expect(decl).toMatchObject({ kind: 'ExternImportDecl', alias: 'HashMap' });
    if (decl.kind === 'ExternImportDecl') {
      expect(decl.overrides.length).toBe(1);
      expect(decl.overrides[0]).toMatchObject({ kind: 'ExternImportOverride', name: 'size' });
    }
  });

  it('parses extern import with multiple overrides', () => {
    const ast = parse(tokenize(
      'extern import "java:java.util.HashMap" as HashMap { fun size(m: HashMap): Int; fun isEmpty(m: HashMap): Bool }'
    ));
    expect(ast.kind).toBe('Program');
    const decl = ast.body[0];
    if (decl.kind === 'ExternImportDecl') {
      expect(decl.overrides.length).toBe(2);
      expect(decl.overrides[0].name).toBe('size');
      expect(decl.overrides[1].name).toBe('isEmpty');
    }
  });

  it('errors on extern import missing string literal', () => {
    const result = parse(tokenize('extern import HashMap'));
    expect('ok' in result && !result.ok).toBe(true);
    if ('ok' in result && !result.ok) {
      expect(result.errors.some((e) => e.message.includes('Expected string literal after extern import'))).toBe(true);
    }
  });

  it('errors on export extern import', () => {
    const result = parse(tokenize('export extern import "java:java.util.HashMap" as HashMap { }'));
    expect('ok' in result && !result.ok).toBe(true);
    if ('ok' in result && !result.ok) {
      expect(result.errors.some((e) => e.message.includes('export extern import is not supported'))).toBe(true);
    }
  });
});
