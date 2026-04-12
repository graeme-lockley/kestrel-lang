"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const vitest_1 = require("vitest");
const folding_1 = require("../../src/server/providers/folding");
(0, vitest_1.describe)('collectFoldingRanges', () => {
    (0, vitest_1.it)('collects folding ranges from block/type spans', () => {
        const ast = {
            kind: 'Program',
            body: [
                { kind: 'FunDecl', name: 'x', span: { line: 1, endLine: 4 }, body: { kind: 'BlockExpr', span: { line: 1, endLine: 4 } } },
                { kind: 'TypeDecl', name: 'Option', span: { line: 5, endLine: 8 } },
            ],
        };
        const ranges = (0, folding_1.collectFoldingRanges)(ast, '');
        (0, vitest_1.expect)(ranges.some((r) => r.startLine === 0 && r.endLine === 3)).toBe(true);
        (0, vitest_1.expect)(ranges.some((r) => r.startLine === 4 && r.endLine === 7)).toBe(true);
    });
    (0, vitest_1.it)('collects multiline block comment folding ranges', () => {
        const source = 'val x = 1\n/* a\n b\n*/\nval y = 2\n';
        const ranges = (0, folding_1.collectFoldingRanges)(null, source);
        (0, vitest_1.expect)(ranges.some((r) => r.startLine === 1 && r.endLine === 3)).toBe(true);
    });
});
//# sourceMappingURL=folding.test.js.map