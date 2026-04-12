"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const vitest_1 = require("vitest");
const semanticTokens_1 = require("../../src/server/providers/semanticTokens");
(0, vitest_1.describe)('collectSemanticTokens', () => {
    (0, vitest_1.it)('emits semantic tokens for basic source', async () => {
        const source = 'fun add(a: Int): Int = a\nval x = add(1)\n';
        const tokens = await (0, semanticTokens_1.collectSemanticTokens)(source);
        (0, vitest_1.expect)(tokens.data.length).toBeGreaterThan(0);
    });
});
//# sourceMappingURL=semanticTokens.test.js.map