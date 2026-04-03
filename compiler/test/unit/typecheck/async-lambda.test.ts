import { describe, it, expect } from 'vitest';
import { tokenize } from '../../../src/lexer/index.js';
import { parse } from '../../../src/parser/index.js';
import { getInferredType, typecheck } from '../../../src/typecheck/index.js';

function parseAndTypecheck(source: string) {
  const ast = parse(tokenize(source));
  return { ast, result: typecheck(ast) };
}

describe('async lambdas', () => {
  it('infers Task return type for async lambdas', () => {
    const { ast, result } = parseAndTypecheck('val inc = async (x: Int) => x + 1');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const stmt = ast.body[0];
    if (stmt?.kind !== 'ValStmt' || stmt.value.kind !== 'LambdaExpr') return;
    const inferred = getInferredType(stmt.value);
    expect(inferred?.kind).toBe('arrow');
    if (inferred?.kind !== 'arrow') return;
    expect(inferred.return.kind).toBe('app');
    if (inferred.return.kind !== 'app') return;
    expect(inferred.return.name).toBe('Task');
    expect(inferred.return.args[0]?.kind).toBe('prim');
    if (inferred.return.args[0]?.kind === 'prim') {
      expect(inferred.return.args[0].name).toBe('Int');
    }
  });

  it('rejects await inside a non-async lambda', () => {
    const { result } = parseAndTypecheck(`
      async fun getTask(): Task<Int> = 1
      val bad = (x: Int) => await getTask()
    `);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.diagnostics.some((d) => d.message.includes('async contexts'))).toBe(true);
  });

  it('rejects await inside a non-async lambda nested in an async function', () => {
    const { result } = parseAndTypecheck(`
      async fun getTask(): Task<Int> = 1
      async fun run(): Task<Int> = {
        val bad = (x: Int) => await getTask()
        0
      }
    `);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.diagnostics.some((d) => d.message.includes('async contexts'))).toBe(true);
  });

  it('typechecks generic async lambdas and higher-order usage', () => {
    const { result } = parseAndTypecheck(`
      fun use(f: Int -> Task<Int>, x: Int): Task<Int> = f(x)
      val inc = async (x: Int) => x + 1
      val id = async <T>(x: T) => x
      async fun run(): Task<Int> = {
        val a = await use(inc, 41)
        val b = await id(1)
        a + b
      }
    `);
    expect(result.ok).toBe(true);
  });
});