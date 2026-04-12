"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const vitest_1 = require("vitest");
const codeLens_1 = require("../../src/server/providers/codeLens");
(0, vitest_1.describe)('collectTestCodeLenses', () => {
    (0, vitest_1.it)('creates run/debug lenses for each test call', () => {
        const source = [
            'test("adds", () => 1)',
            'val x = 1',
            'test("multiplies", () => 2)',
            '',
        ].join('\n');
        const lenses = (0, codeLens_1.collectTestCodeLenses)('file:///tmp/sample.ks', source);
        (0, vitest_1.expect)(lenses).toHaveLength(4);
        (0, vitest_1.expect)(lenses[0]?.command?.command).toBe('kestrel.runTest');
        (0, vitest_1.expect)(lenses[1]?.command?.command).toBe('kestrel.debugTest');
        (0, vitest_1.expect)(lenses[0]?.command?.arguments?.[0]).toBe('adds');
        (0, vitest_1.expect)(lenses[2]?.command?.arguments?.[0]).toBe('multiplies');
    });
    (0, vitest_1.it)('ignores non-test calls', () => {
        const source = 'println("hello")\n';
        const lenses = (0, codeLens_1.collectTestCodeLenses)('file:///tmp/sample.ks', source);
        (0, vitest_1.expect)(lenses).toHaveLength(0);
    });
});
//# sourceMappingURL=codeLens.test.js.map