import { describe, expect, it } from 'vitest';
import type { Diagnostic } from 'vscode-languageserver/node';

import type { CompilerDiagnostic } from '../../src/server/document-manager';
import { collectCodeActions } from '../../src/server/providers/codeActions';

function lspDiagnostic(code: string, message: string): Diagnostic {
  return {
    code,
    message,
    range: {
      start: { line: 1, character: 0 },
      end: { line: 1, character: 10 },
    },
    severity: 1,
    source: 'kestrel',
  };
}

describe('collectCodeActions', () => {
  it('offers add-import quick fix for unknown println', () => {
    const source = 'val x = println("hi")\n';
    const diagnostics = [lspDiagnostic('type:unknown_variable', 'Unknown variable `println`')];

    const actions = collectCodeActions('file:///tmp/sample.ks', source, diagnostics, []);
    expect(actions).toHaveLength(1);
    expect(actions[0]?.title).toContain('Import println from');
    const edit = actions[0]?.edit?.changes?.['file:///tmp/sample.ks']?.[0];
    expect(edit?.newText).toContain('import { println } from "kestrel:io/console"');
  });

  it('offers missing-match-arms quick fix from diagnostic hint', () => {
    const source = [
      'val x = match (v) {',
      '  | Some(n) => n',
      '}',
      '',
    ].join('\n');

    const diagnostics = [lspDiagnostic('type:non_exhaustive_match', 'Non-exhaustive match for Option')];
    const compilerDiagnostics: CompilerDiagnostic[] = [
      {
        severity: 'error',
        code: 'type:non_exhaustive_match',
        message: 'Non-exhaustive match for Option',
        hint: 'Missing constructors: None',
        location: { file: '<source>', line: 1, column: 1 },
      },
    ];

    const actions = collectCodeActions('file:///tmp/sample.ks', source, diagnostics, compilerDiagnostics);
    expect(actions).toHaveLength(1);
    expect(actions[0]?.title).toBe('Add missing match arms');
    const edit = actions[0]?.edit?.changes?.['file:///tmp/sample.ks']?.[0];
    expect(edit?.newText).toContain('| None(_) =>');
  });

  it('returns no actions for unrelated diagnostics', () => {
    const diagnostics = [lspDiagnostic('type:check', 'Type mismatch')];
    const actions = collectCodeActions('file:///tmp/sample.ks', 'val x = 1\n', diagnostics, []);
    expect(actions).toHaveLength(0);
  });
});
