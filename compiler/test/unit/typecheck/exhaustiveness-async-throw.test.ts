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
      expect(result.diagnostics.some((d) => d.message.includes('Non-exhaustive') && d.message.includes('Nil'))).toBe(true);
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

  it('int literal patterns require catch-all', () => {
    const bad = tc(`
      val n = 1
      val r = match (n) {
        0 => 10
      }
    `);
    expect(bad.ok).toBe(false);
    if (!bad.ok) {
      expect(bad.diagnostics.some((d) => d.message.includes('literal patterns on Int require a catch-all'))).toBe(true);
    }

    const good = tc(`
      val n = 1
      val r = match (n) {
        0 => 10,
        _ => 20
      }
    `);
    expect(good.ok).toBe(true);
  });

  it('float literal patterns require catch-all', () => {
    const bad = tc(`
      val x = 1.5
      val r = match (x) {
        1.5 => 10
      }
    `);
    expect(bad.ok).toBe(false);
    if (!bad.ok) {
      expect(bad.diagnostics.some((d) => d.message.includes('literal patterns on Float require a catch-all'))).toBe(true);
    }

    const good = tc(`
      val x = 1.5
      val r = match (x) {
        1.5 => 10,
        _ => 20
      }
    `);
    expect(good.ok).toBe(true);
  });

  it('string literal patterns require catch-all', () => {
    const bad = tc(`
      val s = "x"
      val r = match (s) {
        "x" => 10
      }
    `);
    expect(bad.ok).toBe(false);
    if (!bad.ok) {
      expect(bad.diagnostics.some((d) => d.message.includes('literal patterns on String require a catch-all'))).toBe(true);
    }
  });

  it('char literal patterns require catch-all', () => {
    const bad = tc(`
      val c = 'a'
      val r = match (c) {
        'a' => 10
      }
    `);
    expect(bad.ok).toBe(false);
    if (!bad.ok) {
      expect(bad.diagnostics.some((d) => d.message.includes('literal patterns on Char require a catch-all'))).toBe(true);
    }
  });

  it('unit literal pattern is exhaustive by itself', () => {
    const good = tc(`
      val u = ()
      val r = match (u) {
        () => 1
      }
    `);
    expect(good.ok).toBe(true);
  });

  it('rejects literal pattern type mismatch', () => {
    const result = tc(`
      val b = True
      val r = match (b) {
        0 => 10,
        _ => 20
      }
    `);
    expect(result.ok).toBe(false);
  });

  it('supports nested literal pattern in constructor record pattern', () => {
    const ok = tc(`
      val o = Some(42)
      val r = match (o) {
        Some { value = 42 } => 1,
        _ => 0
      }
    `);
    expect(ok.ok).toBe(true);
  });

  it('rejects nested literal type mismatch in constructor record pattern', () => {
    const bad = tc(`
      val o = Some(42)
      val r = match (o) {
        Some { value = "x" } => 1,
        _ => 0
      }
    `);
    expect(bad.ok).toBe(false);
  });

  it('tuple match: single arm with only variables is exhaustive', () => {
    const ok = tc(`
      val p = (1, 2)
      val r = match (p) { (x, y) => x + y }
    `);
    expect(ok.ok).toBe(true);
  });

  it('tuple match: literal in tuple slot requires catch-all', () => {
    const bad = tc(`
      val p = (1, 2)
      val r = match (p) { (0, y) => y }
    `);
    expect(bad.ok).toBe(false);
    if (!bad.ok) {
      expect(bad.diagnostics.some((d) => d.message.includes('Non-exhaustive match') && d.message.includes('tuple'))).toBe(
        true
      );
    }
    const good = tc(`
      val p = (1, 2)
      val r = match (p) { (0, y) => y, _ => 0 }
    `);
    expect(good.ok).toBe(true);
  });

  it('tuple pattern arity mismatch is a type error', () => {
    const bad = tc(`
      val p = (1, 2)
      val r = match (p) { (a, b, c) => a }
    `);
    expect(bad.ok).toBe(false);
  });

  it('tuple pattern against non-tuple scrutinee is a type error', () => {
    const bad = tc(`
      val n = 1
      val r = match (n) { (a, b) => a }
    `);
    expect(bad.ok).toBe(false);
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
      expect(result.diagnostics.length).toBeGreaterThan(0);
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
      expect(result.diagnostics.some((d) => d.message.includes('Return type must be the same as the body type'))).toBe(true);
    }
  });
});
