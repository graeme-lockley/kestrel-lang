"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const vitest_1 = require("vitest");
const formatting_1 = require("../../src/server/providers/formatting");
(0, vitest_1.describe)('formatting provider', () => {
    (0, vitest_1.it)('returns a full-document edit when formatter output differs', async () => {
        const edits = await (0, formatting_1.testFormatDocument)('val x = 1   \n', { executable: 'kestrel', enabled: true }, async () => ({ ok: true, output: 'val x = 1\n' }));
        (0, vitest_1.expect)(edits).toHaveLength(1);
        (0, vitest_1.expect)(edits[0]?.newText).toBe('val x = 1\n');
        (0, vitest_1.expect)(edits[0]?.range.start.line).toBe(0);
    });
    (0, vitest_1.it)('returns no edits when output is identical', async () => {
        const source = 'val x = 1\n';
        const edits = await (0, formatting_1.testFormatDocument)(source, { executable: 'kestrel', enabled: true }, async () => ({ ok: true, output: source }));
        (0, vitest_1.expect)(edits).toHaveLength(0);
    });
    (0, vitest_1.it)('returns no edits when formatter fails', async () => {
        const edits = await (0, formatting_1.testFormatDocument)('val x =\n', { executable: 'kestrel', enabled: true }, async () => ({ ok: false, output: '' }));
        (0, vitest_1.expect)(edits).toHaveLength(0);
    });
});
//# sourceMappingURL=formatting.test.js.map