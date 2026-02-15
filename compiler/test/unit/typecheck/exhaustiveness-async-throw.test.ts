/**
 * Unit tests for typecheck: exhaustiveness, await outside async, throw (spec 06 §5–§7).
 * Uses typecheck() on minimal program strings (black-box).
 */
import { describe, it, expect } from 'vitest';
import { tokenize } from '../../../src/lexer/index.js';
import { parse } from '../../../src/parser/index.js';
import { typecheck } from '../../../src/typecheck/index.js';

function tc(source: string): ReturnType<typeof typecheck> {
  const tokens = tokenize(source);
  const ast = parse(tokens);
  return typecheck(ast);
}

describe('checkExhaustive', () => {
  it('exhaustive match ([] and ::) passes', () => {
    const result = tc(`
      val xs = [1, 2]
      val r = match (xs) {
        [] => 0
        head :: tail => head
      }
    `);
    expect(result.ok).toBe(true);
  });

  it('non-exhaustive match (missing Nil case) fails with exhaustiveness error', () => {
    const result = tc(`
      val xs = [1, 2, 3]
      val r = match (xs) {
        Cons { head, tail } => head
      }
    `);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.errors.some((e) => e.includes('Non-exhaustive') && e.includes('Nil'))).toBe(true);
    }
  });

  it('match with catch-all passes', () => {
    const result = tc(`
      val xs = [1, 2]
      val r = match (xs) {
        _ => 0
      }
    `);
    expect(result.ok).toBe(true);
  });
});

describe('await outside async', () => {
  it('program with await outside async context fails typecheck', () => {
    const result = tc(`
      async fun getTask(): Task<Int> = 1
      val x = await getTask()
    `);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.errors.length).toBeGreaterThan(0);
    }
  });
});

describe('throw exception type', () => {
  it('throw e typechecks (checker currently accepts any type for throw)', () => {
    const result = tc(`
      val x = 1
      val _ = throw x
    `);
    expect(result.ok).toBe(true);
  });
});

describe('return type must match body when body type is from parameter', () => {
  it('rejects fun apply(f: T -> S, x: T): Int = f(x) because return should be S', () => {
    const result = tc(`
      fun apply(f: T -> S, x: T): Int = f(x)
    `);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.errors.some((e) => e.includes('Return type must be the same as the body type'))).toBe(true);
    }
  });
});
