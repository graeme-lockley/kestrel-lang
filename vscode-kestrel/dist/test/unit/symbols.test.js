"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const vitest_1 = require("vitest");
const symbols_1 = require("../../src/server/providers/symbols");
(0, vitest_1.describe)('collectDocumentSymbols', () => {
    (0, vitest_1.it)('collects top-level declarations', () => {
        const ast = {
            kind: 'Program',
            body: [
                { kind: 'FunDecl', name: 'add', span: { line: 1, column: 1, endLine: 2, endColumn: 1 } },
                { kind: 'ValDecl', name: 'answer', span: { line: 3, column: 1, endLine: 3, endColumn: 10 } },
            ],
        };
        const symbols = (0, symbols_1.collectDocumentSymbols)(ast);
        (0, vitest_1.expect)(symbols.map((s) => s.name)).toEqual(['add', 'answer']);
    });
    (0, vitest_1.it)('nests ADT constructors under type symbols', () => {
        const ast = {
            kind: 'Program',
            body: [
                {
                    kind: 'TypeDecl',
                    name: 'Option',
                    span: { line: 1, column: 1, endLine: 4, endColumn: 1 },
                    body: {
                        kind: 'ADTBody',
                        constructors: [
                            { name: 'Some', span: { line: 2, column: 3, endLine: 2, endColumn: 8 } },
                            { name: 'None', span: { line: 3, column: 3, endLine: 3, endColumn: 8 } },
                        ],
                    },
                },
            ],
        };
        const symbols = (0, symbols_1.collectDocumentSymbols)(ast);
        (0, vitest_1.expect)(symbols).toHaveLength(1);
        (0, vitest_1.expect)(symbols[0]?.children?.map((c) => c.name)).toEqual(['Some', 'None']);
    });
});
//# sourceMappingURL=symbols.test.js.map