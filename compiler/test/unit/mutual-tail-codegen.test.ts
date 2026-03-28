import { describe, it, expect } from 'vitest';
import { compile } from '../../src/index.js';
import { codegen } from '../../src/codegen/codegen.js';
import { Op } from '../../src/bytecode/instructions.js';

function countOpInRange(code: Uint8Array, op: number, start: number, end: number): number {
  let c = 0;
  for (let i = start; i < end; i++) {
    if (code[i] === op) c += 1;
  }
  return c;
}

describe('mutual tail-call lowering (kbc)', () => {
  const src = `
fun isEven(n: Int): Bool = if (n == 0) True else isOdd(n - 1)
fun isOdd(n: Int): Bool = if (n == 0) False else isEven(n - 1)
val _x = isEven(0)
`;
  it('does not emit CALL between mutually tail-recursive top-level pair', () => {
    const result = compile(src);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const { code, functionTable } = codegen(result.ast, { sourceFile: 't.ks' });
    expect(functionTable.length).toBeGreaterThanOrEqual(2);
    const a = functionTable[0]!.codeOffset;
    const b = functionTable[1]!.codeOffset;
    const c = functionTable[2]?.codeOffset ?? code.length;
    const callsInEven = countOpInRange(code, Op.CALL, a, b);
    const callsInOdd = countOpInRange(code, Op.CALL, b, c);
    expect(callsInEven).toBe(0);
    expect(callsInOdd).toBe(0);
  });

  it('emits CALL when the partner call is not in tail position', () => {
    const srcNonTail = `
fun a(n: Int): Int = if (n <= 0) 0 else 1 + b(n - 1)
fun b(n: Int): Int = if (n <= 0) 0 else a(n - 1)
val _z = a(2)
`;
    const result = compile(srcNonTail);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const { code, functionTable } = codegen(result.ast, { sourceFile: 'u.ks' });
    const startA = functionTable[0]!.codeOffset;
    const startB = functionTable[1]!.codeOffset;
    const callsInA = countOpInRange(code, Op.CALL, startA, startB);
    expect(callsInA).toBeGreaterThan(0);
  });
});
