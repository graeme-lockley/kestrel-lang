"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const vitest_1 = require("vitest");
const definition_1 = require("../../src/server/providers/definition");
(0, vitest_1.describe)('findDefinition', () => {
    (0, vitest_1.it)('resolves top-level function definitions', () => {
        const source = 'fun add(a: Int, b: Int): Int = a + b\nval x = add(1, 2)\n';
        const ast = {
            kind: 'Program',
            imports: [],
            body: [
                { kind: 'FunDecl', name: 'add', span: { line: 1, column: 1, endLine: 1, endColumn: 4 } },
            ],
        };
        const def = (0, definition_1.findDefinition)(ast, source, 'file:///tmp/test.ks', { line: 1, character: 9 });
        (0, vitest_1.expect)(def?.range.start.line).toBe(0);
        (0, vitest_1.expect)(def?.range.start.character).toBe(0);
    });
    (0, vitest_1.it)('returns null when symbol is unresolved', () => {
        const source = 'val x = unknown\n';
        const ast = { kind: 'Program', imports: [], body: [] };
        const def = (0, definition_1.findDefinition)(ast, source, 'file:///tmp/test.ks', { line: 0, character: 10 });
        (0, vitest_1.expect)(def).toBeNull();
    });
});
//# sourceMappingURL=definition.test.js.map