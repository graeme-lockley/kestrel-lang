import { describe, expect, it } from 'vitest';

import { compilerDiagnosticToLsp } from '../../src/server/diagnostics';

describe('compilerDiagnosticToLsp', () => {
  it('maps severity, range, and related hint/suggestion information', () => {
    const lsp = compilerDiagnosticToLsp(
      {
        severity: 'error',
        code: 'type:unknown_variable',
        message: 'Unknown variable `foo`',
        location: { file: '<source>', line: 3, column: 5, endLine: 3, endColumn: 8 },
        hint: 'Did you mean `food`?',
        suggestion: 'Add an import for `foo`.',
      },
      'file:///tmp/sample.ks',
    );

    expect(lsp.severity).toBe(1);
    expect(lsp.range.start.line).toBe(2);
    expect(lsp.range.start.character).toBe(4);
    expect(lsp.code).toBe('type:unknown_variable');
    expect(lsp.relatedInformation?.map((r) => r.message)).toContain('hint: Did you mean `food`?');
    expect(lsp.relatedInformation?.map((r) => r.message)).toContain('suggestion: Add an import for `foo`.');
  });

  it('maps warnings to warning severity', () => {
    const lsp = compilerDiagnosticToLsp(
      {
        severity: 'warning',
        code: 'type:check',
        message: 'Possible issue',
        location: { file: '<source>', line: 1, column: 1 },
      },
      'file:///tmp/sample.ks',
    );

    expect(lsp.severity).toBe(2);
  });
});
