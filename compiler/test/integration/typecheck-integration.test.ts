/**
 * Integration tests: parse then typecheck (Plan 2.4–2.5).
 */
import { describe, it, expect } from 'vitest';
import { tokenize } from '../../src/lexer/index.js';
import { parse } from '../../src/parser/index.js';
import { typecheck, getInferredType } from '../../src/typecheck/index.js';

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
});
