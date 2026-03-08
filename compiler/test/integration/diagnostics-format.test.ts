import { describe, it, expect } from 'vitest';
import { compile } from '../../src/index.js';
import { report } from '../../src/diagnostics/index.js';

describe('diagnostics format (spec 10)', () => {
  it('parse error: human format has file:line:column, source line, caret', () => {
    const result = compile('val x =');
    expect(result.ok).toBe(false);
    if (!result.ok) {
      const chunks: string[] = [];
      const stream = { write: (chunk: string) => chunks.push(chunk), isTTY: false } as NodeJS.WritableStream;
      report(result.diagnostics, { format: 'human', stream });
      const out = chunks.join('');
      expect(out).toContain('-->');
      expect(out).toMatch(/\d+:\d+/);
      expect(result.diagnostics.some((d) => d.code.startsWith('parse:'))).toBe(true);
      expect(result.diagnostics[0]).toMatchObject({
        severity: 'error',
        message: expect.any(String),
        location: expect.objectContaining({ file: expect.any(String), line: expect.any(Number), column: expect.any(Number) }),
      });
    }
  });

  it('parse error: JSON format emits one JSON object per line with severity, code, message, location', () => {
    const result = compile('val x =');
    expect(result.ok).toBe(false);
    if (!result.ok) {
      const chunks: string[] = [];
      const stream = { write: (chunk: string) => chunks.push(chunk) } as NodeJS.WritableStream;
      report(result.diagnostics, { format: 'json', stream });
      const out = chunks.join('');
      const lines = out.trim().split('\n').filter(Boolean);
      expect(lines.length).toBeGreaterThan(0);
      for (const line of lines) {
        const obj = JSON.parse(line);
        expect(obj).toHaveProperty('severity', 'error');
        expect(obj).toHaveProperty('code');
        expect(obj.code).toMatch(/^parse:/);
        expect(obj).toHaveProperty('message');
        expect(obj).toHaveProperty('location');
        expect(obj.location).toMatchObject({
          file: expect.any(String),
          line: expect.any(Number),
          column: expect.any(Number),
        });
      }
    }
  });

  it('type error: human format has location and message', () => {
    const result = compile('val x: Int = "hello"');
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.diagnostics.length).toBeGreaterThan(0);
      const chunks: string[] = [];
      const stream = { write: (chunk: string) => chunks.push(chunk), isTTY: false } as NodeJS.WritableStream;
      report(result.diagnostics, { format: 'human', stream });
      const out = chunks.join('');
      expect(out).toContain('-->');
      expect(out).toMatch(/\d+:\d+/);
      expect(result.diagnostics[0]).toMatchObject({
        severity: 'error',
        code: expect.stringMatching(/^type:|^parse:/),
        message: expect.any(String),
        location: expect.objectContaining({ file: expect.any(String), line: expect.any(Number), column: expect.any(Number) }),
      });
    }
  });

  it('type error: JSON format has severity, code, message, location', () => {
    const result = compile('println(y)');
    expect(result.ok).toBe(false);
    if (!result.ok) {
      const chunks: string[] = [];
      const stream = { write: (chunk: string) => chunks.push(chunk) } as NodeJS.WritableStream;
      report(result.diagnostics, { format: 'json', stream });
      const out = chunks.join('');
      const line = out.trim().split('\n')[0];
      expect(line).toBeDefined();
      const obj = JSON.parse(line!);
      expect(obj).toHaveProperty('severity', 'error');
      expect(obj).toHaveProperty('code');
      expect(obj.code).toMatch(/^type:/);
      expect(obj).toHaveProperty('message');
      expect(obj).toHaveProperty('location');
      expect(obj.location).toMatchObject({
        file: expect.any(String),
        line: expect.any(Number),
        column: expect.any(Number),
      });
    }
  });

  it('type error with suggestion: unknown variable includes suggestion when similar name exists', () => {
    const result = compile('println(prinln("hi"))');
    expect(result.ok).toBe(false);
    if (!result.ok) {
      const d = result.diagnostics.find((x) => x.message.includes('Unknown variable') && x.message.includes('prinln'));
      expect(d).toBeDefined();
      expect(d?.code).toBe('type:unknown_variable');
      expect(d?.suggestion).toMatch(/Did you mean/);
    }
  });

  it('type error with related: at least one diagnostic has related location', () => {
    const result = compile('val _ = { var x = 0; x := "bad"; 0 }');
    expect(result.ok).toBe(false);
    if (!result.ok) {
      const withRelated = result.diagnostics.filter((d) => d.related != null && d.related.length > 0);
      expect(withRelated.length).toBeGreaterThan(0);
      const d = withRelated[0]!;
      expect(d.related).toBeDefined();
      expect(Array.isArray(d.related)).toBe(true);
      expect(d.related!.length).toBeGreaterThan(0);
      expect(d.related![0]).toMatchObject({ message: 'expected type from here', location: expect.any(Object) });
    }
  });
});
