import { describe, it, expect } from 'vitest';
import { report } from '../../src/diagnostics/index.js';
import type { Diagnostic } from '../../src/diagnostics/types.js';

describe('diagnostics reporter', () => {
  const sample: Diagnostic[] = [{
    severity: 'error',
    code: 'type:unknown_variable',
    message: 'Unknown variable: x',
    location: { file: '/project/main.ks', line: 10, column: 5 },
  }];

  it('format json emits one JSON object per line', () => {
    const chunks: string[] = [];
    const stream = { write: (chunk: string) => { chunks.push(chunk); } } as NodeJS.WritableStream;
    report(sample, { format: 'json', stream });
    const out = chunks.join('');
    expect(out).toContain('"code":"type:unknown_variable"');
    expect(out).toContain('"message":"Unknown variable: x"');
    const line = out.trim().split('\n')[0];
    expect(() => JSON.parse(line!)).not.toThrow();
  });

  it('format human contains location and message', () => {
    const chunks: string[] = [];
    const stream = { write: (chunk: string) => { chunks.push(chunk); }, isTTY: false } as NodeJS.WritableStream;
    report(sample, { format: 'human', stream });
    const out = chunks.join('');
    expect(out).toContain('-->');
    expect(out).toContain('main.ks:10:5');
    expect(out).toContain('Unknown variable: x');
  });
});
