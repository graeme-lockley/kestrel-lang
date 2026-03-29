/**
 * Integration tests: parse then typecheck (Plan 2.4–2.5).
 */
import { describe, it, expect } from 'vitest';
import { tokenize } from '../../src/lexer/index.js';
import { parse } from '../../src/parser/index.js';
import { typecheck, getInferredType } from '../../src/typecheck/index.js';
import { CODES } from '../../src/diagnostics/types.js';

describe('parse then typecheck (multi-declaration)', () => {
  it('typechecks program with multiple val and fun declarations', () => {
    const source = `
      fun id(x: Int): Int = x
      fun add(a: Int, b: Int): Int = a + b
      val one = 1
      val two = 2
      val sum = add(one, two)
      val three = id(sum)
    `;
    const tokens = tokenize(source);
    const ast = parse(tokens);
    const tc = typecheck(ast);
    expect(tc.ok).toBe(true);
    if (tc.ok) {
      expect(ast.body.length).toBeGreaterThanOrEqual(5);
    }
  });

  it('typechecks program with val, fun, and match', () => {
    const source = `
      val xs = [1, 2, 3]
      fun head(l: List<Int>): Int = match (l) {
        [] => 0
        h :: _ => h
      }
      val first = head(xs)
    `;
    const tokens = tokenize(source);
    const ast = parse(tokens);
    const tc = typecheck(ast);
    expect(tc.ok).toBe(true);
  });

  it('typechecks block-local fun with full signature', () => {
    const source = 'fun f(): Int = { fun add(x: Int): Int = x + 1; add(2) }';
    const tokens = tokenize(source);
    const ast = parse(tokens);
    const tc = typecheck(ast);
    expect(tc.ok).toBe(true);
  });

  it('inferred types are set on key nodes after typecheck', () => {
    const source = 'val x = 42';
    const tokens = tokenize(source);
    const ast = parse(tokens);
    const tc = typecheck(ast);
    expect(tc.ok).toBe(true);
    if (tc.ok && ast.body[0]?.kind === 'ValStmt') {
      const valStmt = ast.body[0];
      const typeOnValue = getInferredType(valStmt.value);
      expect(typeOnValue).toBeDefined();
      if (typeOnValue && typeOnValue.kind === 'prim') {
        expect(typeOnValue.name).toBe('Int');
      }
    }
  });

  it('rejects break outside loop with type:break_outside_loop', () => {
    const source = 'fun f(): Unit = { break }';
    const tc = typecheck(parse(tokenize(source)));
    expect(tc.ok).toBe(false);
    if (!tc.ok) {
      expect(tc.diagnostics.some((d) => d.code === CODES.type.break_outside_loop)).toBe(true);
    }
  });

  it('allows if-branch block ending with break in expression context inside while', () => {
    const source = 'fun f(): Unit = { while (True) { if (True) { break } else () } }';
    const tc = typecheck(parse(tokenize(source)));
    expect(tc.ok).toBe(true);
  });

  it('accepts union parameter when passing Int or Bool (subtyping)', () => {
    const source = `
      fun id(x: Int | Bool): Int = if (x is Int) x else 0
      val a = id(1)
      val b = id(True)
      fun g(): Int | Bool = 1
    `;
    const tc = typecheck(parse(tokenize(source)));
    expect(tc.ok).toBe(true);
  });

  it('rejects passing Int|Bool where Int is required', () => {
    const source = `
      fun needInt(x: Int): Int = x
      fun u(): Int | Bool = True
      val bad = needInt(u())
    `;
    const tc = typecheck(parse(tokenize(source)));
    expect(tc.ok).toBe(false);
  });

  it('rejects assignment to immutable record field inside a block', () => {
    const source = 'val _ = { val r = { x = 1 }; r.x := 2; () }';
    const tc = typecheck(parse(tokenize(source)));
    expect(tc.ok).toBe(false);
    if (!tc.ok) {
      expect(tc.diagnostics.some((d) => d.message.includes('immutable field'))).toBe(true);
    }
  });
});
