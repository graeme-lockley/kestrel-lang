import { describe, it, expect } from 'vitest';
import { compile, tokenize, parse } from '../../src/index.js';
import { codegen } from '../../src/codegen/codegen.js';
import { ConstTag } from '../../src/bytecode/constants.js';

describe('compile', () => {
  it('returns ok: true and AST for valid program', () => {
    const result = compile('val x = 1');
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.ast.kind).toBe('Program');
      expect(result.ast.body.length).toBe(1);
      expect(result.ast.body[0]).toMatchObject({ kind: 'ValStmt', name: 'x' });
    }
  });

  it('returns ok: false and diagnostics for parse error', () => {
    const result = compile('val x =');
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.diagnostics.length).toBeGreaterThan(0);
  });

  it('returns ok: false for typecheck error (unknown variable)', () => {
    const result = compile('val x = y');
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.diagnostics.some((d) => d.message.includes('Unknown variable') && d.message.includes('y'))).toBe(true);
    }
  });

  it('compiles program with function and emits function table', () => {
    const result = compile('fun double(x: Int): Int = x + x\nval a = double(3)');
    expect(result.ok).toBe(true);
    if (result.ok) {
      const { functionTable, code } = codegen(result.ast);
      expect(functionTable.length).toBe(1);
      expect(functionTable[0]).toMatchObject({ nameIndex: expect.any(Number), arity: 1, codeOffset: expect.any(Number) });
      expect(code.length).toBeGreaterThan(1);
    }
  });

  it('compiles recursive factorial (if, comparison, call)', () => {
    const result = compile('fun fact(n: Int): Int = if (n == 0) 1 else n * fact(n - 1)\nval x = fact(5)');
    expect(result.ok).toBe(true);
    if (result.ok) {
      const { functionTable } = codegen(result.ast);
      expect(functionTable.length).toBe(1);
      expect(functionTable[0]!.arity).toBe(1);
    }
  });

  it('compiles short-circuit & and |', () => {
    const r1 = compile('val a = True & False');
    expect(r1.ok).toBe(true);
    const r2 = compile('val b = False | True');
    expect(r2.ok).toBe(true);
  });

  it('compiles record literal and emits shape table', () => {
    const result = compile('val r = { x = 1, y = 2 }');
    expect(result.ok).toBe(true);
    if (result.ok) {
      const { shapes, code } = codegen(result.ast);
      expect(shapes.length).toBe(1);
      expect(shapes[0]!.nameIndices.length).toBe(2);
      expect(code.length).toBeGreaterThan(5);
    }
  });

  it('compiles field access on variable (r.x)', () => {
    const result = compile('val r = { x = 1, y = 2 }\nval a = r.x');
    expect(result.ok).toBe(true);
    if (result.ok) {
      const { code } = codegen(result.ast);
      expect(code.length).toBeGreaterThan(10);
    }
  });

  it('compiles mutable record and field assignment (r.x := e)', () => {
    const result = compile('val r = { mut x = 1 }\nr.x := 2\nval a = r.x');
    expect(result.ok).toBe(true);
    if (result.ok) {
      const { code } = codegen(result.ast);
      expect(code.length).toBeGreaterThan(10);
    }
  });

  it('returns ok: false for assign to immutable field', () => {
    const result = compile('val r = { x = 1 }\nr.x := 2');
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.diagnostics.some((d) => d.message.includes('immutable field') || d.message.includes('Cannot assign'))).toBe(true);
    }
  });

  it('compiles tuple literal and field access (t.0, t.1)', () => {
    const result = compile('val t = (1, 2)\nval a = t.0\nval b = t.1');
    expect(result.ok).toBe(true);
    if (result.ok) {
      const { code, shapes } = codegen(result.ast);
      expect(shapes.length).toBeGreaterThanOrEqual(1);
      expect(code.length).toBeGreaterThan(10);
    }
  });

  it('emits correct bytecode for logical NOT (!True and !False)', () => {
    // Per ISA 04: !x compiles to (x == False). Constant-folding !True->False, !False->True is allowed.
    const r1 = compile('val a = !True');
    expect(r1.ok).toBe(true);
    const r2 = compile('val b = !False');
    expect(r2.ok).toBe(true);
    if (r1.ok && r2.ok) {
      const out1 = codegen(r1.ast);
      const out2 = codegen(r2.ast);
      // !True must yield False
      expect(out1.constantPool.some((c) => c.tag === ConstTag.False)).toBe(true);
      // !False must yield True
      expect(out2.constantPool.some((c) => c.tag === ConstTag.True)).toBe(true);
      expect(Array.from(out1.code).some((b) => b === 0x01)).toBe(true); // LOAD_CONST present
    }
  });

  it('emits import table when program has imports', () => {
    const result = compile('import { x } from "kestrel:string"\nval a = 1');
    expect(result.ok).toBe(true);
    if (result.ok) {
      const { importSpecifierIndices, stringTable } = codegen(result.ast);
      expect(importSpecifierIndices.length).toBe(1);
      expect(stringTable[importSpecifierIndices[0]!]).toBe('kestrel:string');
    }
  });

  it('compiles nested fun (FunStmt inside block)', () => {
    const result = compile('fun outer(): Int = { fun inner(): Int = 42; inner() }\nval x = outer()');
    expect(result.ok).toBe(true);
    if (result.ok) {
      const out = codegen(result.ast);
      expect(out.code.length).toBeGreaterThan(0);
      expect(out.functionTable.length).toBeGreaterThanOrEqual(1);
    }
  });
});
