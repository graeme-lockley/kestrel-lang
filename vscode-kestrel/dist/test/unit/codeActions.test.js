"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const vitest_1 = require("vitest");
const codeActions_1 = require("../../src/server/providers/codeActions");
function lspDiagnostic(code, message) {
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
(0, vitest_1.describe)('collectCodeActions', () => {
    (0, vitest_1.it)('offers add-import quick fix for unknown println', () => {
        const source = 'val x = println("hi")\n';
        const diagnostics = [lspDiagnostic('type:unknown_variable', 'Unknown variable `println`')];
        const actions = (0, codeActions_1.collectCodeActions)('file:///tmp/sample.ks', source, diagnostics, []);
        (0, vitest_1.expect)(actions).toHaveLength(1);
        (0, vitest_1.expect)(actions[0]?.title).toContain('Import println from');
        const edit = actions[0]?.edit?.changes?.['file:///tmp/sample.ks']?.[0];
        (0, vitest_1.expect)(edit?.newText).toContain('import { println } from "kestrel:io/console"');
    });
    (0, vitest_1.it)('offers missing-match-arms quick fix from diagnostic hint', () => {
        const source = [
            'val x = match (v) {',
            '  | Some(n) => n',
            '}',
            '',
        ].join('\n');
        const diagnostics = [lspDiagnostic('type:non_exhaustive_match', 'Non-exhaustive match for Option')];
        const compilerDiagnostics = [
            {
                severity: 'error',
                code: 'type:non_exhaustive_match',
                message: 'Non-exhaustive match for Option',
                hint: 'Missing constructors: None',
                location: { file: '<source>', line: 1, column: 1 },
            },
        ];
        const actions = (0, codeActions_1.collectCodeActions)('file:///tmp/sample.ks', source, diagnostics, compilerDiagnostics);
        (0, vitest_1.expect)(actions).toHaveLength(1);
        (0, vitest_1.expect)(actions[0]?.title).toBe('Add missing match arms');
        const edit = actions[0]?.edit?.changes?.['file:///tmp/sample.ks']?.[0];
        (0, vitest_1.expect)(edit?.newText).toContain('| None(_) =>');
    });
    (0, vitest_1.it)('returns no actions for unrelated diagnostics', () => {
        const diagnostics = [lspDiagnostic('type:check', 'Type mismatch')];
        const actions = (0, codeActions_1.collectCodeActions)('file:///tmp/sample.ks', 'val x = 1\n', diagnostics, []);
        (0, vitest_1.expect)(actions).toHaveLength(0);
    });
});
//# sourceMappingURL=codeActions.test.js.map