"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const vitest_1 = require("vitest");
const completion_1 = require("../../src/server/providers/completion");
(0, vitest_1.describe)('collectCompletions', () => {
    (0, vitest_1.it)('includes keywords, imports, and declarations', () => {
        const ast = {
            kind: 'Program',
            imports: [{ kind: 'NamedImport', specs: [{ local: 'println' }] }],
            body: [
                { kind: 'FunDecl', name: 'add', params: [{ name: 'a' }, { name: 'b' }] },
                { kind: 'ValDecl', name: 'answer' },
                {
                    kind: 'TypeDecl',
                    name: 'Option',
                    body: { kind: 'ADTBody', constructors: [{ name: 'Some' }, { name: 'None' }] },
                },
            ],
        };
        const items = (0, completion_1.collectCompletions)(ast);
        const labels = new Set(items.map((i) => i.label));
        (0, vitest_1.expect)(labels.has('fun')).toBe(true);
        (0, vitest_1.expect)(labels.has('println')).toBe(true);
        (0, vitest_1.expect)(labels.has('add')).toBe(true);
        (0, vitest_1.expect)(labels.has('answer')).toBe(true);
        (0, vitest_1.expect)(labels.has('Some')).toBe(true);
        (0, vitest_1.expect)(labels.has('a')).toBe(true);
    });
});
//# sourceMappingURL=completion.test.js.map