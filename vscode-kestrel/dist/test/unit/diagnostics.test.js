"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const vitest_1 = require("vitest");
const diagnostics_1 = require("../../src/server/diagnostics");
(0, vitest_1.describe)('compilerDiagnosticToLsp', () => {
    (0, vitest_1.it)('maps severity, range, and related hint/suggestion information', () => {
        const lsp = (0, diagnostics_1.compilerDiagnosticToLsp)({
            severity: 'error',
            code: 'type:unknown_variable',
            message: 'Unknown variable `foo`',
            location: { file: '<source>', line: 3, column: 5, endLine: 3, endColumn: 8 },
            hint: 'Did you mean `food`?',
            suggestion: 'Add an import for `foo`.',
        }, 'file:///tmp/sample.ks');
        (0, vitest_1.expect)(lsp.severity).toBe(1);
        (0, vitest_1.expect)(lsp.range.start.line).toBe(2);
        (0, vitest_1.expect)(lsp.range.start.character).toBe(4);
        (0, vitest_1.expect)(lsp.code).toBe('type:unknown_variable');
        (0, vitest_1.expect)(lsp.relatedInformation?.map((r) => r.message)).toContain('hint: Did you mean `food`?');
        (0, vitest_1.expect)(lsp.relatedInformation?.map((r) => r.message)).toContain('suggestion: Add an import for `foo`.');
    });
    (0, vitest_1.it)('maps warnings to warning severity', () => {
        const lsp = (0, diagnostics_1.compilerDiagnosticToLsp)({
            severity: 'warning',
            code: 'type:check',
            message: 'Possible issue',
            location: { file: '<source>', line: 1, column: 1 },
        }, 'file:///tmp/sample.ks');
        (0, vitest_1.expect)(lsp.severity).toBe(2);
    });
});
//# sourceMappingURL=diagnostics.test.js.map