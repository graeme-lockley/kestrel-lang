/**
 * Type narrowing via `e is T` (spec 06 §4) and `IsExpr` typing.
 */
import { describe, it, expect } from 'vitest';
import { tokenize } from '../../../src/lexer/index.js';
import { parse } from '../../../src/parser/index.js';
import { typecheck, getInferredType } from '../../../src/typecheck/index.js';
import { CODES } from '../../../src/diagnostics/types.js';

function tc(src: string) {
  return typecheck(parse(tokenize(src)));
}

describe('is expression and narrowing', () => {
  it('infers Bool for standalone is on Option', () => {
    const ast = parse(tokenize('fun f(o: Option<Int>): Bool = o is None'));
    const r = typecheck(ast);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const fd = ast.body[0];
    if (fd?.kind !== 'FunDecl') return;
    const body = fd.body;
    if (body.kind !== 'IsExpr') return;
    const t = getInferredType(body);
    expect(t?.kind).toBe('prim');
    if (t?.kind === 'prim') expect(t.name).toBe('Bool');
  });

  it('narrows in then-branch for Option/Some', () => {
    const r = tc('fun f(o: Option<Int>): Int = if (o is Some) { 1 } else { 0 }');
    expect(r.ok).toBe(true);
  });

  it('narrows union Int | Bool in then', () => {
    const r = tc('fun f(x: Int | Bool): Int = if (x is Int) { x + 1 } else { 0 }');
    expect(r.ok).toBe(true);
  });

  it('user ADT constructor is', () => {
    const src = `
      type Color = Red | Blue
      fun f(c: Color): Int = if (c is Red) { 0 } else { 1 }
    `;
    expect(tc(src).ok).toBe(true);
  });

  it('record shape is', () => {
    const src = `
      fun f(r: { x: Int, y: Int }): Int = if (r is { x: Int }) { r.x + r.y } else { 0 }
    `;
    expect(tc(src).ok).toBe(true);
  });

  it('rejects impossible narrow', () => {
    const r = tc('fun f(x: Int): Bool = x is String');
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.diagnostics.some((d) => d.code === CODES.type.narrow_impossible)).toBe(true);
  });

  it('else branch keeps unrefined type', () => {
    const r = tc('fun f(x: Int | Bool): Int = if (x is Int) { x } else { x + 1 }');
    expect(r.ok).toBe(false);
  });

  it('standalone is on record subset (not only inside if)', () => {
    const src = `
      val r = { x = 1, y = 2 }
      fun f(): Bool = r is { x: Int }
    `;
    expect(tc(src).ok).toBe(true);
  });

  it('module-level val narrowRec then is (matches tests/unit/narrowing.test.ks)', () => {
    const src = `
val narrowRec = { x = 1, y = 2 }
fun f(): Bool = narrowRec is { x: Int }
`;
    expect(tc(src).ok).toBe(true);
  });
});
