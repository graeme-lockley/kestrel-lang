"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.formatDocument = formatDocument;
exports.formatDocumentRange = formatDocumentRange;
exports.testFormatDocument = testFormatDocument;
const node_child_process_1 = require("node:child_process");
function fullRange(source) {
    const lines = source.split('\n');
    const endLine = Math.max(0, lines.length - 1);
    const endChar = (lines[endLine] ?? '').length;
    return {
        start: { line: 0, character: 0 },
        end: { line: endLine, character: endChar },
    };
}
async function runFormatter(source, executable) {
    return new Promise((resolve) => {
        const child = (0, node_child_process_1.spawn)(executable, ['fmt', '--stdin'], { stdio: 'pipe' });
        let stdout = '';
        child.stdout.on('data', (chunk) => {
            stdout += chunk.toString();
        });
        child.on('error', () => {
            resolve({ ok: false, output: '' });
        });
        child.on('close', (code) => {
            if (code === 0) {
                resolve({ ok: true, output: stdout });
            }
            else {
                resolve({ ok: false, output: '' });
            }
        });
        child.stdin.end(source);
    });
}
async function formatWithRunner(source, settings, runner) {
    if (!settings.enabled) {
        return [];
    }
    const result = await runner(source, settings.executable);
    if (!result.ok) {
        return [];
    }
    if (result.output === source) {
        return [];
    }
    return [{ range: fullRange(source), newText: result.output }];
}
async function formatDocument(source, settings) {
    return formatWithRunner(source, settings, runFormatter);
}
async function formatDocumentRange(source, settings, _range) {
    return formatWithRunner(source, settings, runFormatter);
}
async function testFormatDocument(source, settings, runner) {
    return formatWithRunner(source, settings, runner);
}
//# sourceMappingURL=formatting.js.map