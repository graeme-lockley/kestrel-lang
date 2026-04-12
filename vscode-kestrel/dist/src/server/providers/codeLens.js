"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.collectTestCodeLenses = collectTestCodeLenses;
function makeRange(line, character) {
    const pos = { line, character };
    return { start: pos, end: pos };
}
function collectTestCodeLenses(uri, source) {
    const out = [];
    const lines = source.split('\n');
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i] ?? '';
        const m = line.match(/\btest\s*\(\s*"([^"]+)"/);
        if (m == null) {
            continue;
        }
        const testName = m[1] ?? '';
        const col = m.index ?? 0;
        const range = makeRange(i, col);
        out.push({
            range,
            command: {
                title: '▶ Run test',
                command: 'kestrel.runTest',
                arguments: [testName, uri],
            },
        });
        out.push({
            range,
            command: {
                title: '▶ Debug test',
                command: 'kestrel.debugTest',
                arguments: [testName, uri],
            },
        });
    }
    return out;
}
//# sourceMappingURL=codeLens.js.map